cat > job_ht.sh << 'EOF'
#!/bin/bash
#SBATCH -J kmeans_ht
#SBATCH -o results/slurm_ht_%j.out
#SBATCH -p normal,slow
#SBATCH --exclude=c23
#SBATCH -N 1
#SBATCH --ntasks=40
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1G
#SBATCH -t 00:20:00

# ============================ CONFIGURACAO ============================
LISTA="20 32 40"
K=16; N=1000000; REPS=3
# ========================================================================

set -u

# ---------------- Fase 1: no de login ('bash job_ht.sh') ----------------
if [ -z "${SLURM_JOB_ID:-}" ]; then
  cd "$(dirname "$0")" || exit 1
  SCRIPT=$(basename "$0")
  for b in kmeans_seq kmeans_omp kmeans_mpi; do
    [ -x "bin/$b" ] || { echo "ERRO: bin/$b nao existe. Rode 'bash job.sh' ou o make antes."; exit 1; }
  done
  mkdir -p results
  sbatch "$SCRIPT"
  exit $?
fi

# ---------------- Fase 2: no de computacao ----------------
HOME_DIR="$SLURM_SUBMIT_DIR"
SCRATCH_DIR="/scratch/$USER/kmeans_ht_$SLURM_JOB_ID"

export OMPI_MCA_btl_tcp_if_include=200.18.104.0/24
export OMPI_MCA_oob_tcp_if_include=200.18.104.0/24
export OMPI_MCA_hwloc_base_binding_policy=core
export OMPI_MCA_rmaps_base_mapping_policy=core:oversubscribe
export OMP_PROC_BIND=close OMP_PLACES=cores
export MAX_P=40

echo "job=$SLURM_JOB_ID maquinas=$SLURM_JOB_NODELIST processos=$SLURM_NTASKS"
date; gcc --version | head -1; mpirun --version | head -1
lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|Socket'
echo

# Sonda: o mpirun aceita 40 processos com binding por nucleo?
if ERR=$(mpirun -np 40 hostname 2>&1 >/dev/null); then
  echo "mpirun -np 40 OK (mapeamento por nucleo, 2 processos por nucleo acima de 20)"
else
  echo "AVISO: mpirun -np 40 recusou o mapeamento por nucleo:"; echo "$ERR" | head -5
  echo "AVISO: usando fallback sem binding; o MPI fica mais ruidoso."
  export OMPI_MCA_hwloc_base_binding_policy=none
  export OMPI_MCA_rmaps_base_mapping_policy=slot
  mpirun -np 40 hostname >/dev/null 2>&1 || { echo "ERRO: mpirun -np 40 falhou tambem sem binding."; exit 1; }
fi
echo

for b in kmeans_seq kmeans_omp kmeans_mpi; do
  [ -x "$HOME_DIR/bin/$b" ] || { echo "ERRO: bin/$b nao existe."; exit 1; }
done

mkdir -p "$SCRATCH_DIR" || exit 1
cp -r "$HOME_DIR"/bin "$HOME_DIR"/scripts "$HOME_DIR"/tools "$SCRATCH_DIR/"
cd "$SCRATCH_DIR" || exit 1
mkdir -p data results

arq="data/k${K}_n${N}.txt"
echo "--- Teste hyperthreading (k=$K, n=$N, REPS=$REPS, p=\"$LISTA\") ---"; date
python3 tools/gen_input.py "$K" "$N" 42 > "$arq" || { echo "ERRO ao gerar entrada"; exit 1; }

REPS=$REPS PROCS="$LISTA" THREADS="$LISTA" ./scripts/run_benchmark.sh "$arq" \
  || echo "AVISO: benchmark terminou com erro"

[ -f results/benchmark.csv ] && cp results/benchmark.csv "$HOME_DIR/results/benchmark_ht.csv"

cd "$HOME_DIR" && rm -rf "$SCRATCH_DIR"
echo "--- Job finalizado ---"; date
EOF

bash -n job_ht.sh && echo "sintaxe OK"
bash job_ht.sh