#!/bin/bash
#SBATCH -J kmeans_bench
#SBATCH -o results/slurm_%j.out
#SBATCH -p normal,slow
#SBATCH --exclude=c23
#SBATCH -N 1
#SBATCH --ntasks=20
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=1G
#SBATCH -t 03:00:00

# ============================ CONFIGURAÇÕES ============================
LISTA="1 2 4 8 16 20"
K_SMALL=16;  N_SMALL=1000000;   REPS_SMALL=5
K_LARGE=50;  N_LARGE=5000000;  REPS_LARGE=3
# ========================================================================

set -u

# ---------------- Fase 1: no de login ('bash job.sh') ----------------
if [ -z "${SLURM_JOB_ID:-}" ]; then
  cd "$(dirname "$0")" || exit 1
  SCRIPT=$(basename "$0")

  command -v mpicc >/dev/null || { echo "ERRO: mpicc nao encontrado. Rode 'module load gnu9 openmpi4' e tente de novo."; exit 1; }

  make clean
  make CC=gcc CFLAGS="-O3 -march=x86-64-v2" seq omp mpi \
    || { echo "ERRO: compilacao falhou. Nada foi para a fila."; exit 1; }

  # teste minusculo no login (segundos): valida formato de saida, compare.py e mpirun
  TMP_IN=$(mktemp)
  python3 tools/gen_input.py 4 2000 1 > "$TMP_IN"
  MAX_P=2 REPS=1 PROCS="1 2" THREADS="1 2" timeout 120 ./scripts/run_benchmark.sh "$TMP_IN" \
    || { echo "ERRO: teste rapido falhou (veja acima). Use FORCE=1 para enviar mesmo assim."; [ "${FORCE:-0}" = 1 ] || exit 1; }
  rm -f results/benchmark.csv "$TMP_IN"

  mkdir -p results
  sbatch "$SCRIPT"
  exit $?
fi

# ---------------- Fase 2: no de computacao ----------------
HOME_DIR="$SLURM_SUBMIT_DIR"
SCRATCH_DIR="/scratch/$USER/kmeans_$SLURM_JOB_ID"

export OMPI_MCA_btl_tcp_if_include=200.18.104.0/24
export OMPI_MCA_oob_tcp_if_include=200.18.104.0/24
export OMPI_MCA_hwloc_base_binding_policy=core
export OMPI_MCA_rmaps_base_mapping_policy=core
export OMP_PROC_BIND=close OMP_PLACES=cores
export MAX_P=20

echo "job=$SLURM_JOB_ID maquinas=$SLURM_JOB_NODELIST processos=$SLURM_NTASKS"
date; gcc --version | head -1; mpirun --version | head -1; echo

for b in kmeans_seq kmeans_omp kmeans_mpi; do
  [ -x "$HOME_DIR/bin/$b" ] || { echo "ERRO: bin/$b nao existe. Use 'bash job.sh'."; exit 1; }
done
command -v python3 >/dev/null || { echo "ERRO: python3 nao encontrado no no."; exit 1; }

mkdir -p "$SCRATCH_DIR" || exit 1
cp -r "$HOME_DIR"/bin "$HOME_DIR"/scripts "$HOME_DIR"/tools "$SCRATCH_DIR/"
cd "$SCRATCH_DIR" || exit 1
chmod +x scripts/*.sh tools/*.py 2>/dev/null
mkdir -p data results

run_test() {
  local nome=$1 k=$2 n=$3 reps=$4 arq="data/k${k}_n${n}.txt" bg
  echo "--- Iniciando teste $nome (k=$k, n=$n, REPS=$reps) ---"; date
  python3 tools/gen_input.py "$k" "$n" 42 > "$arq" || { echo "ERRO ao gerar entrada $nome"; return 1; }

  # copia parcial a cada 2 min, para nao perder tudo se o tempo acabar
  ( while sleep 120; do [ -f results/benchmark.csv ] && cp results/benchmark.csv "$HOME_DIR/results/parcial_$nome.csv"; done ) &
  bg=$!

  REPS=$reps PROCS="$LISTA" THREADS="$LISTA" ./scripts/run_benchmark.sh "$arq" \
    || echo "AVISO: benchmark $nome terminou com erro"

  kill "$bg" 2>/dev/null
  [ -f results/benchmark.csv ] && cp results/benchmark.csv "$HOME_DIR/results/benchmark_$nome.csv"
  rm -f results/benchmark.csv "$arq"
}

run_test small "$K_SMALL" "$N_SMALL" "$REPS_SMALL"
run_test large "$K_LARGE" "$N_LARGE" "$REPS_LARGE"

cd "$HOME_DIR" && rm -rf "$SCRATCH_DIR"
echo "--- Job finalizado ---"; date