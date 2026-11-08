#!/usr/bin/env python3
"""Análise de desempenho do K-Means paralelo.
Uso:
  python3 tools/analyze.py results/benchmark.csv [--saida results]
"""
import argparse
import csv
import os
import sys
from collections import defaultdict

import numpy as np
import matplotlib

matplotlib.use("Agg")  # sem interface gráfica (WSL, servidores)
import matplotlib.pyplot as plt

ORDEM = ["seq", "omp", "mpi", "cuda"]
NOMES = {"seq": "Sequencial", "omp": "OpenMP", "mpi": "MPI", "cuda": "CUDA"}
CORES = {"seq": "tab:gray", "omp": "tab:blue", "mpi": "tab:orange", "cuda": "tab:green"}
ESCALAVEIS = ("omp", "mpi")  # versões em que p (threads/processos) varia
COLUNAS = ("versao", "p", "rep", "leitura", "nucleo")


#leitura
def ler_csv(caminho):
    """Devolve {(versao, p): {"leitura": [...], "nucleo": [...]}}."""
    dados = defaultdict(lambda: {"leitura": [], "nucleo": []})
    with open(caminho, newline="") as f:
        leitor = csv.DictReader(f)
        if not leitor.fieldnames or not set(COLUNAS) <= set(leitor.fieldnames):
            sys.exit(f"ERRO: o CSV precisa ter as colunas {','.join(COLUNAS)} "
                     f"(encontrado: {leitor.fieldnames}).")
        for linha in leitor:
            chave = (linha["versao"], int(linha["p"]))
            dados[chave]["leitura"].append(float(linha["leitura"]))
            dados[chave]["nucleo"].append(float(linha["nucleo"]))
    if not dados:
        sys.exit("ERRO: o CSV não tem nenhuma execução.")
    return dados


#estatísticas
def resumir(dados):
    """Estatísticas por configuração (versao, p)."""
    res = {}
    for chave, d in dados.items():
        leitura = np.array(d["leitura"])
        nucleo = np.array(d["nucleo"])
        total = leitura + nucleo
        n = len(nucleo)
        res[chave] = {
            "reps": n,
            "leitura": float(np.median(leitura)),
            "nucleo": float(np.median(nucleo)),
            "nucleo_media": float(nucleo.mean()),
            "nucleo_dp": float(nucleo.std(ddof=1)) if n > 1 else float("nan"),
            "total": float(np.median(total)),
        }
    return res


def calcular_metricas(res):
    """Acrescenta speedup, eficiência e Karp-Flatt a cada configuração."""
    if ("seq", 1) not in res:
        sys.exit("ERRO: o CSV não tem execuções do sequencial (versao=seq, p=1).")
    seq = res[("seq", 1)]
    for (versao, p), r in res.items():
        r["speedup"] = seq["nucleo"] / r["nucleo"]
        r["speedup_total"] = seq["total"] / r["total"]
        if versao in ESCALAVEIS:
            r["eficiencia"] = r["speedup"] / p
            # Karp-Flatt: fração sequencial "efetiva" implícita no speedup medido
            r["karp_flatt"] = ((1 / r["speedup"] - 1 / p) / (1 - 1 / p)) if p > 1 else float("nan")
        else:
            r["eficiencia"] = float("nan")
            r["karp_flatt"] = float("nan")
    return seq


#Amdahl
def amdahl(p, f):
    """Speedup previsto pela Lei de Amdahl para fração sequencial f."""
    p = np.asarray(p, dtype=float)
    return 1.0 / (f + (1.0 - f) / p)


def ajustar_amdahl(ps, speedups):
    """Estima f por mínimos quadrados.

    Amdahl: 1/S = f + (1-f)/p   ->   (1/S - 1/p) = f * (1 - 1/p)
    É uma regressão por origem em x = 1 - 1/p, y = 1/S - 1/p; f = sum(xy) / sum(x²).
    O ponto p = 1 não contribui (x = 0).
    """
    ps = np.asarray(ps, dtype=float)
    s = np.asarray(speedups, dtype=float)
    mask = ps > 1
    if not mask.any():
        return None
    x = 1.0 - 1.0 / ps[mask]
    y = 1.0 / s[mask] - 1.0 / ps[mask]
    f = float((x * y).sum() / (x * x).sum())
    return min(max(f, 0.0), 1.0)


#tabela
def linhas_tabela(res):
    chaves = sorted(res, key=lambda k: (ORDEM.index(k[0]) if k[0] in ORDEM else 99, k[1]))
    linhas = []
    for versao, p in chaves:
        r = res[(versao, p)]
        linhas.append({
            "versao": versao, "p": p, "reps": r["reps"],
            "leitura_s": r["leitura"], "nucleo_mediana_s": r["nucleo"],
            "nucleo_media_s": r["nucleo_media"], "nucleo_dp_s": r["nucleo_dp"],
            "total_mediana_s": r["total"],
            "speedup_nucleo": r["speedup"], "speedup_total": r["speedup_total"],
            "eficiencia": r["eficiencia"], "karp_flatt": r["karp_flatt"],
        })
    return linhas


def fmt(valor, casas=4):
    return "-" if valor is None or (isinstance(valor, float) and np.isnan(valor)) else f"{valor:.{casas}f}"


def salvar_tabela(linhas, saida):
    campos = list(linhas[0].keys())
    with open(os.path.join(saida, "tabela_desempenho.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        for l in linhas:
            w.writerow({k: (fmt(v, 6) if isinstance(v, float) else v) for k, v in l.items()})

    cab = ["Versão", "p", "Reps", "Leitura (s)", "Núcleo med. (s)", "Desvio (s)",
           "Speedup", "Speedup total", "Eficiência", "Karp-Flatt"]
    linhas_md = ["| " + " | ".join(cab) + " |", "|" + "|".join(["---"] * len(cab)) + "|"]
    for l in linhas:
        linhas_md.append("| " + " | ".join([
            NOMES.get(l["versao"], l["versao"]), str(l["p"]), str(l["reps"]),
            fmt(l["leitura_s"]), fmt(l["nucleo_mediana_s"], 3), fmt(l["nucleo_dp_s"], 3),
            fmt(l["speedup_nucleo"], 2), fmt(l["speedup_total"], 2),
            fmt(l["eficiencia"], 3), fmt(l["karp_flatt"], 3)]) + " |")
    with open(os.path.join(saida, "tabela_desempenho.md"), "w") as f:
        f.write("\n".join(linhas_md) + "\n")
    return linhas_md


#gráficos
def pontos(res, versao):
    ps = sorted(p for (v, p) in res if v == versao)
    return ps, [res[(versao, p)] for p in ps]


def grafico_speedup(res, fits, saida):
    fig, ax = plt.subplots(figsize=(7, 5))
    todos_p = sorted({p for (v, p) in res if v in ESCALAVEIS})
    if todos_p:
        ax.plot(todos_p, todos_p, "--", color="lightgray", label="Ideal (S = p)")
    for v in ESCALAVEIS:
        ps, rs = pontos(res, v)
        if not ps:
            continue
        ax.plot(ps, [r["speedup"] for r in rs], "o-", color=CORES[v], label=NOMES[v])
        if fits.get(v) is not None:
            grade = np.linspace(min(ps), max(ps), 100)
            ax.plot(grade, amdahl(grade, fits[v]), ":", color=CORES[v], alpha=0.8,
                    label=f"Amdahl {NOMES[v]} (f = {fits[v]*100:.1f}%)")
    # Limite vertical definido pelas versões escaláveis, para a GPU não achatar as curvas
    topo = 1.15 * max([max(todos_p, default=1)] + [r["speedup"] for (v, _), r in res.items() if v in ESCALAVEIS])
    if ("cuda", 1) in res:
        s = res[("cuda", 1)]["speedup"]
        if s <= topo:
            ax.axhline(s, color=CORES["cuda"], linestyle="-.", label=f"CUDA ({s:.1f}x)")
        else:
            ax.plot([], [], " ", label=f"CUDA: {s:.1f}x (fora da escala)")
    ax.set_ylim(0, topo)
    ax.set_xlabel("Threads (OpenMP) / processos (MPI)")
    ax.set_ylabel("Speedup do núcleo")
    ax.set_title("Speedup (escalabilidade forte, n fixo)")
    if todos_p:
        ax.set_xticks(todos_p)
    ax.grid(alpha=0.3)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(os.path.join(saida, "speedup.png"), dpi=150)
    plt.close(fig)


def grafico_eficiencia(res, saida):
    fig, ax = plt.subplots(figsize=(7, 5))
    todos_p = sorted({p for (v, p) in res if v in ESCALAVEIS})
    ax.axhline(1.0, linestyle="--", color="lightgray", label="Ideal (E = 1)")
    for v in ESCALAVEIS:
        ps, rs = pontos(res, v)
        if ps:
            ax.plot(ps, [r["eficiencia"] for r in rs], "o-", color=CORES[v], label=NOMES[v])
    ax.set_xlabel("Threads (OpenMP) / processos (MPI)")
    ax.set_ylabel("Eficiência  E = S / p")
    ax.set_title("Eficiência")
    ax.set_ylim(0, 1.1)
    if todos_p:
        ax.set_xticks(todos_p)
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(saida, "eficiencia.png"), dpi=150)
    plt.close(fig)


def grafico_decomposicao(res, saida):
    chaves = sorted(res, key=lambda k: (ORDEM.index(k[0]) if k[0] in ORDEM else 99, k[1]))
    rotulos = [v if v in ("seq", "cuda") else f"{v}\np={p}" for v, p in chaves]
    leitura = np.array([res[k]["leitura"] for k in chaves])
    nucleo = np.array([res[k]["nucleo"] for k in chaves])
    pct = 100 * leitura / (leitura + nucleo)
    x = np.arange(len(chaves))

    fig, (a1, a2) = plt.subplots(1, 2, figsize=(13, 5))
    a1.bar(x, nucleo, color="tab:blue", label="Núcleo (K-Means)")
    a1.bar(x, leitura, bottom=nucleo, color="tab:red", label="Leitura da entrada")
    a1.set_xticks(x, rotulos, fontsize=8)
    a1.set_ylabel("Tempo (s)")
    a1.set_title("Decomposição do tempo (mediana)")
    a1.legend()
    a1.grid(axis="y", alpha=0.3)

    a2.bar(x, pct, color="tab:red")
    a2.set_xticks(x, rotulos, fontsize=8)
    a2.set_ylabel("% do tempo total gasto na leitura")
    a2.set_title("Fração sequencial de leitura")
    a2.grid(axis="y", alpha=0.3)
    for xi, v in zip(x, pct):
        a2.text(xi, v, f"{v:.1f}%", ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(saida, "decomposicao.png"), dpi=150)
    plt.close(fig)


# main
def main():
    ap = argparse.ArgumentParser(description="Análise de desempenho do K-Means paralelo.")
    ap.add_argument("csv", help="CSV gerado por scripts/run_benchmarks.sh")
    ap.add_argument("--saida", default="results", help="pasta de saída (padrão: results)")
    args = ap.parse_args()

    os.makedirs(args.saida, exist_ok=True)
    res = resumir(ler_csv(args.csv))
    seq = calcular_metricas(res)

    linhas = linhas_tabela(res)
    print("\n".join(salvar_tabela(linhas, args.saida)))

    # Lei de Amdahl: f ajustado aos speedups medidos de cada versão escalável
    fits = {}
    for v in ESCALAVEIS:
        ps, rs = pontos(res, v)
        if ps:
            fits[v] = ajustar_amdahl(ps, [r["speedup"] for r in rs])

    f_leitura = seq["leitura"] / seq["total"]
    print("\nLei de Amdahl")
    print(f"  Leitura medida no seq: {f_leitura*100:.2f}% do tempo total "
          f"(teto de speedup total pela leitura: {1/f_leitura:.0f}x)")
    for v, f in fits.items():
        if f is None:
            continue
        teto = "ilimitado" if f == 0 else f"{1/f:.1f}x"
        print(f"  {NOMES[v]}: fração sequencial efetiva ajustada f = {f*100:.2f}% (teto de speedup: {teto})")
    if any(f is not None and f > f_leitura * 1.5 for f in fits.values()):
        print("  Obs.: f ajustado bem acima da fração de leitura -> há outros trechos "
              "sequenciais ou custos por iteração (redução, memória) além da leitura.")

    grafico_speedup(res, fits, args.saida)
    grafico_eficiencia(res, args.saida)
    grafico_decomposicao(res, args.saida)
    print(f"\nSalvo em {args.saida}/: tabela_desempenho.csv, tabela_desempenho.md, "
          "speedup.png, eficiencia.png, decomposicao.png")


if __name__ == "__main__":
    main()