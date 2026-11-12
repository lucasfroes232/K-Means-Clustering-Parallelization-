#!/bin/bash
#SBATCH --job-name=kmeans_bench
#SBATCH --output=results/slurm_%j.out   
#SBATCH --partition=normal              
#SBATCH --nodes=1
#SBATCH --ntasks=40                     
#SBATCH --time=02:00:00                 

# variáveis de diretório
HOME_DIR="$HOME/K-Means-Clustering-Parallelization"
SCRATCH_DIR="/scratch/$USER/kmeans_$SLURM_JOB_ID"

#  Cria a pasta temporária no disco rápido e copia o código
mkdir -p "$SCRATCH_DIR"
cp -r "$HOME_DIR/"* "$SCRATCH_DIR/"


cd "$SCRATCH_DIR"

module load gcc openmpi
make all
mkdir -p data

#teste small
python3 tools/gen_input.py 16 1000000 42 > data/k16_n1e6.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k16_n1e6.txt
mv results/benchmark.csv benchmark_small.csv

#teste large
python3 tools/gen_input.py 50 50000000 42 > data/k50_n50e7.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k50_n10e6.txt
mv results/benchmark.csv benchmark_large.csv

# 5. Salva os resultados finais de volta na sua pasta segura (/home)
cp benchmark_small.csv "$HOME_DIR/results/"
cp benchmark_large.csv "$HOME_DIR/results/"

# 6. Limpa o disco rápido (respeitando as regras do cluster)
rm -rf "$SCRATCH_DIR"