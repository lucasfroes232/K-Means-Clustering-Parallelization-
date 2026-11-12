#!/bin/bash
#SBATCH --job-name=kmeans_bench
#SBATCH --output=results/slurm_%j.out   # Guarda o log do terminal com o ID do job
#SBATCH --partition=normal              # Fila padrão (ajuste se a disciplina exigir outra)
#SBATCH --nodes=1
#SBATCH --ntasks=40                     # Aloca até 16 núcleos para o seu teste
#SBATCH --time=02:00:00                 # Tempo máximo de execução

# carrega os módulos necessários no cluster
module load gcc openmpi

# compila codigos
make all

# roda o benchmark para 2 datasets:


# python3 tools/gen_input.py 16 1000000 42 > data/k16_n1e6.txt
PROCS="1 2 4 8 12 16 32 40" THREADS="1 2 4 8 12 16 32 40" ./scripts/run_benchmark.sh data/k16_n1e6.txt
mv results/benchmark.csv results/benchmark_small.csv


# python3 tools/gen_input.py 50 10000000 42 > data/k50_n50e7.txt
PROCS="1 2 4 8 16 32 40" THREADS="1 2 4 8 16 32 40" ./scripts/run_benchmark.sh data/k50_n10e6.txt
mv results/benchmark.csv results/benchmark_large.csv