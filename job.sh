#!/bin/bash
#SBATCH --job-name=kmeans_bench
#SBATCH --output=results/slurm_%j.out   
#SBATCH --partition=normal              
#SBATCH --nodes=1
#SBATCH --ntasks=40                     
#SBATCH --time=02:00:00                 


HOME_DIR="$SLURM_SUBMIT_DIR"
SCRATCH_DIR="/scratch/$USER/kmeans_$SLURM_JOB_ID"

#usa a subpasta de scratch para realizar I/O
mkdir -p "$SCRATCH_DIR"
cp -r "$HOME_DIR/"* "$SCRATCH_DIR/"

cd "$SCRATCH_DIR" || exit 1

#  tenta carregar os módulos (se falhar, usa os compiladores do ambiente)
module load gnu9 openmpi 2>/dev/null || module load gcc/11.2.0 openmpi 2>/dev/null || true

# compila as três versões
make seq omp mpi
mkdir -p data results

# dataset small
python3 tools/gen_input.py 16 1000000 42 > data/k16_n1e6.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k16_n1e6.txt
mv results/benchmark.csv benchmark_small.csv

# dataset large
python3 tools/gen_input.py 50 50000000 42 > data/k50_n10e7.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k50_n10e6.txt
mv results/benchmark.csv benchmark_large.csv

# salva de volta na /home
cp benchmark_small.csv "$HOME_DIR/results/"
cp benchmark_large.csv "$HOME_DIR/results/"

# limpa o disco rápido
rm -rf "$SCRATCH_DIR"