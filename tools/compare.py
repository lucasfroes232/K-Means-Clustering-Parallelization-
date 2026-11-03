#!/usr/bin/env python3
import sys

def ler_centroides(caminho):
    linhas = [] 
    with open(caminho) as f:
        for linha in f:  # toda string em uma linha ate \n
            campos = linha.split() # transforma a linha em uma lista de strings, separadas por espaço
            if campos:
                linhas.append([float(c) for c in campos]) # transforma cada string em float e adiciona a lista de listas
    return linhas #Um centroide por linha, cada centroide é uma lista de floats com os valores dos eixos

def main():
    if len(sys.argv) < 3:
        print("Uso: compare.py arquivo_a arquivo_b [tolerancia]")
        sys.exit(2)

    a = ler_centroides(sys.argv[1])
    b = ler_centroides(sys.argv[2])
    tol = float(sys.argv[3]) if len(sys.argv) > 3 else 0.011

    if len(a) != len(b):
        print(f"DIFERENTE: {len(a)} linhas vs {len(b)} linhas")
        sys.exit(1)

    ok = True
    max_diff = 0.0
    for i, (la, lb) in enumerate(zip(a, b)): # zip une as duas listas de centroides em pares de centroides, representados por la e lb
        if len(la) != len(lb):
            print(f"DIFERENTE: linha {i} tem {len(la)} colunas no arquivo A vs {len(lb)} colunas no arquivo B")
            sys.exit(1)
        for j, (va, vb) in enumerate(zip(la, lb)): # une as coordenadas x,y e z de cada centroide em pares
            d = abs(va - vb)
            max_diff = max(max_diff, d)
            if d > tol:
                print(f"DIFERENTE: centroide {i}, coord {j}: {va} no arquivo A vs {vb} no arquivo B")
                ok = False

    if ok:
        print(f"OK (maior diferença: {max_diff:.4f})")
        sys.exit(0)
    sys.exit(1)

main()