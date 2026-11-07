#!/bin/bash
set -u

if [ $# -ne 1 ]; then #testa se o número de argumentos é diferente de 1
    echo "Uso: $0 <arquivo_de_entrada>" >&2
    exit 1
fi
if [ ! -f "$1" ]; then #testa se o arquivo de entrada existe
    echo "ERRO: entrada '$1' não encontrada." >&2
    exit 1
fi


IN=$(realpath "$1") # caminhho absoluto do arquivo de entrada
cd "$(dirname "$0")/.." || exit 1  #caminho absoluto do diretório do script, e sobe um nível (raiz do projeto)

REPS=${REPS:-5}
THREADS=${THREADS:-"1 2 3 4 5 6"}
PROCS=${PROCS:-"1 2 3 4 5 6"}
MAX_P=${MAX_P:-$(nproc)}   


if ! [[ $REPS =~ ^[0-9]+$ ]] || [ "$REPS" -lt 1 ]; then # se reps tiver qualquer letra,sinal ou ponto decimal falha
    echo "ERRO: REPS='$REPS' inválido; use um inteiro >= 1." >&2
    exit 1
fi

validar_lista() {
    local nome=$1 lista=$2 v
    for v in $lista; do
        if ! [[ $v =~ ^[0-9]+$ ]] || [ "$v" -lt 1 ] || [ "$v" -gt "$MAX_P" ]; then #se v tiver qualquer letra,sinal,ponto decimal ou p maior q 6 falha
            echo "ERRO: $nome contém '$v'; use inteiros entre 1 e $MAX_P." >&2
            exit 1
        fi
    done
}

BIN=bin
RES=results
CSV=$RES/benchmark.csv
REF=$RES/.ref_seq.txt     # saída de referência (sequencial)
TMP=$RES/.tmp_out.txt     # saída da execução corrente

mkdir -p "$RES"
trap 'rm -f "$REF" "$TMP"' EXIT #garante que os arquivos temporários serão apagados 

if [ ! -x "$BIN/kmeans_seq" ]; then
    echo "ERRO: $BIN/kmeans_seq não encontrado. Rode 'make seq'." >&2
    exit 1
fi

HAS_OMP=0
HAS_MPI=0
HAS_CUDA=0
if [ -x "$BIN/kmeans_omp" ]; then
    HAS_OMP=1
else
    echo "AVISO: $BIN/kmeans_omp não encontrado; OpenMP será pulado." >&2
fi
if [ -x "$BIN/kmeans_mpi" ]; then
    HAS_MPI=1
else
    echo "AVISO: $BIN/kmeans_mpi não encontrado; MPI será pulado." >&2
fi
if [ -x "$BIN/kmeans_cuda" ]; then
    HAS_CUDA=1
else
    echo "AVISO: $BIN/kmeans_cuda não encontrado; CUDA será pulado." >&2
fi

# Só valida as listas das versões que serão de fato executadas.
[ "$HAS_OMP" -eq 1 ] && validar_lista THREADS "$THREADS"
[ "$HAS_MPI" -eq 1 ] && validar_lista PROCS "$PROCS"

# imprime a linha de progresso e grava a linha no CSV.
run_one() {
    local versao=$1 p=$2 rep=$3
    shift 3

    local t leitura nucleo
    t=$("$@" < "$IN" 2>&1 >"$TMP" | tail -n 1) # 2>&1 redireciona o stderr para o stdout, que é redirecionado para o arquivo TMP. O tail pega a última linha do stderr (tempos).
    read -r leitura nucleo <<< "$t" # lê a última linha do stderr e separa em duas variáveis: leitura e nucleo

    local num='^[0-9]+([.][0-9]+)?$' #identifica se a variável é um número inteiro ou decimal (regex)
    if ! [[ $leitura =~ $num && ${nucleo:-} =~ $num ]]; then
        echo "ERRO: $versao p=$p rep=$rep não devolveu 'leitura nucleo' no stderr (recebido: '$t')." >&2
        exit 1
    fi

    local status
    if [ "$versao" = "seq" ]; then
        cp "$TMP" "$REF"
        status="referência"
    else
        local msg
        if msg=$(python3 tools/compare.py "$REF" "$TMP"); then
            status="OK"
        else
            echo "ERRO: saída de $versao p=$p rep=$rep diverge da sequencial:" >&2
            echo "$msg" >&2
            exit 1
        fi
    fi

    echo "$versao,$p,$rep,$leitura,$nucleo" >> "$CSV"
    printf '[rep %s/%s] %-4s p=%-2s leitura=%ss nucleo=%ss  %s\n' \ 
        "$rep" "$REPS" "$versao" "$p" "$leitura" "$nucleo" "$status" >&2 #escreve no terminal o progresso da execução
}

# Recria o CSV (rodadas diferentes não se misturam).
echo "versao,p,rep,leitura,nucleo" > "$CSV"

echo "Entrada: $IN | REPS=$REPS | THREADS=\"$THREADS\" | PROCS=\"$PROCS\"" >&2

for rep in $(seq 1 "$REPS"); do
    # O seq vem primeiro: gera a referência usada na validação desta repetição.
    run_one seq 1 "$rep" "$BIN/kmeans_seq"

    if [ "$HAS_OMP" -eq 1 ]; then
        for p in $THREADS; do
            run_one omp "$p" "$rep" env OMP_NUM_THREADS="$p" "$BIN/kmeans_omp"
        done
    fi

    if [ "$HAS_MPI" -eq 1 ]; then
        for p in $PROCS; do
            run_one mpi "$p" "$rep" mpirun -np "$p" "$BIN/kmeans_mpi"
        done
    fi

    if [ "$HAS_CUDA" -eq 1 ]; then
        run_one cuda 1 "$rep" "$BIN/kmeans_cuda"
    fi
done

echo "Concluído. Tempos em $CSV ($(($(wc -l < "$CSV") - 1)) execuções)." >&2 #qtd de linhas do CSV menos o cabeçalho