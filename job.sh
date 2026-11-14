#!/bin/bash
#SBATCH --job-name=kmeans_bench
#SBATCH --output=results/slurm_%j.out   
#SBATCH --partition=normal              
#SBATCH --nodes=1
#SBATCH --ntasks=40                     
#SBATCH --time=03:00:00                 


HOME_DIR="$SLURM_SUBMIT_DIR"
SCRATCH_DIR="/scratch/$USER/kmeans_$SLURM_JOB_ID"

# purga módulos anteriores e carregar a combinação correta do OpenHPC
module purge
module load gnu9 openmpi4

# cria pasta no scratch
mkdir -p "$SCRATCH_DIR"
cp -r "$HOME_DIR/"* "$SCRATCH_DIR/"
cd "$SCRATCH_DIR" || exit 1


chmod +x scripts/*.sh tools/*.py 2>/dev/null || true
make seq omp mpi
mkdir -p data results

# teste small
echo "--- Iniciando Teste 1: Carga Pequena ---"
python3 tools/gen_input.py 16 1000000 42 > data/k16_n1e6.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k16_n1e6.txt
mv results/benchmark.csv benchmark_small.csv

#teste large
echo "--- Iniciando Teste 2: Carga Grande ---"
python3 tools/gen_input.py 50 10000000 42 > data/k50_n10e6.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k50_n10e6.txt
mv results/benchmark.csv benchmark_large.csv

# copia pro diretorio do projeto
cp benchmark_small.csv "$HOME_DIR/results/"
cp benchmark_large.csv "$HOME_DIR/results/"

# limpa scratch
cd "$HOME_DIR"
rm -rf "$SCRATCH_DIR"