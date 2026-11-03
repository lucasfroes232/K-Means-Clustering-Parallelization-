# K-Means Paralelo

Versões paralelas do algoritmo **K-Means** em 3D, desenvolvidas para o Problema D da *12ª Maratona de Programação Paralela (SBAC-PAD & WSCAD, 2017)*. O objetivo é acelerar o programa sequencial original **sem alterar o método de clusterização**.

> **Status:** em desenvolvimento. Veja a seção [Progresso](#progresso).

---

## Sumário

1. [Descrição do problema](#descrição-do-problema)
2. [Algoritmo](#algoritmo)
3. [Estratégia de paralelização](#estratégia-de-paralelização)
4. [Estrutura do repositório](#estrutura-do-repositório)
5. [Requisitos](#requisitos)
6. [Compilação e execução](#compilação-e-execução)
7. [Formato de entrada e saída](#formato-de-entrada-e-saída)
8. [Metodologia de avaliação](#metodologia-de-avaliação)
9. [Resultados](#resultados)
10. [Progresso](#progresso)
11. [Autores](#autores)

---

## Descrição do problema

Dado um conjunto de `n` pontos em ℝ³ e `k` centroides iniciais, o K-Means particiona os pontos em `k` clusters, associando cada ponto ao centroide mais próximo (distância euclidiana). O programa lê os centroides iniciais e os pontos da entrada padrão e imprime as coordenadas dos `k` centroides finais.

Restrição do enunciado: a paralelização **não pode mudar o método de clusterização**. Todas as versões devem produzir a mesma saída que a versão sequencial.

## Algoritmo

Repete-se até a convergência:

1. **Atribuição:** cada ponto é associado ao centroide de menor distância.
2. **Atualização:** cada centroide passa a ser a média dos pontos do seu cluster.

**Critério de parada:** nenhum centroide muda **e** nenhum ponto troca de cluster.

Custo por iteração: `O(n · k)` na atribuição e `O(k)` na atualização.

## Estratégia de paralelização

**Onde está o paralelismo.** Na etapa de atribuição, os pontos são independentes entre si (paralelismo de dados). Os centroides ocupam apenas `3k` valores e são replicados em todos os workers.

**Onde não está.** O laço de iterações é inerentemente sequencial, pois cada iteração depende dos centroides da anterior. Há uma redução global por iteração.

**Redução.** Para recalcular os centroides, cada worker acumula localmente, por cluster, a **soma de x, y, z** e a **contagem de pontos**. Esses acumuladores são combinados no fim de cada iteração. Só a contagem não basta.

**Balanceamento.** Cada ponto custa o mesmo (`k` distâncias), então a divisão estática em blocos é adequada.

**Otimizações comuns a todas as versões:**

- comparação de distâncias **ao quadrado** (sem `sqrt`);
- layout de memória contíguo (SoA: `x[]`, `y[]`, `z[]`) para cache e vetorização;
- mesmo critério de parada da versão sequencial.

| Versão | Modelo | Decomposição | Combinação por iteração |
|---|---|---|---|
| OpenMP | Memória compartilhada | Blocos de pontos por thread | `reduction` sobre `soma[3k]` e `cont[k]` |
| MPI | Memória distribuída | Blocos de pontos por processo (`MPI_Scatterv`) | `MPI_Allreduce` de `soma[3k]`, `cont[k]` e flag de mudança |
| GPU (CUDA) | Aceleradora | Uma thread por ponto | Redução por bloco em shared memory (ou `atomicAdd`) |

Em MPI, a comunicação por iteração é `O(k)`, independente de `n`.

## Estrutura do repositório

```
.
├── README.md
├── Makefile
├── src/
│   ├── kmeans_seq.c        # versão sequencial (referência)
│   ├── kmeans_omp.c        # OpenMP
│   ├── kmeans_mpi.c        # MPI
│   └── kmeans_cuda.cu      # GPU (CUDA)
├── tools/
│   ├── gen_input.py        # gerador de entradas aleatórias
│   └── compare.py          # compara saídas com a versão sequencial
├── scripts/
│   └── run_benchmarks.sh   # executa os experimentos
├── data/                   # entradas de teste (exemplo pequeno incluído)
├── results/                # tempos medidos e gráficos
└── docs/                   # relatório
```

## Requisitos

| Componente | Versão sugerida |
|---|---|
| Compilador C | GCC ≥ 9 (com suporte a OpenMP) |
| MPI | OpenMPI ou MPICH |
| CUDA Toolkit | ≥ 11 (apenas para a versão GPU) |
| Python | ≥ 3.8, com `numpy` e `matplotlib` (geração de entradas e gráficos) |

## Compilação e execução

### Compilação

```bash
make all        # compila todas as versões disponíveis
make seq        # sequencial
make omp        # OpenMP
make mpi        # MPI
make cuda       # GPU
```

Comandos equivalentes, sem o Makefile:

```bash
gcc   -O3 -march=native -o kmeans_seq  src/kmeans_seq.c -lm
gcc   -O3 -march=native -fopenmp -o kmeans_omp src/kmeans_omp.c -lm
mpicc -O3 -march=native -o kmeans_mpi  src/kmeans_mpi.c -lm
nvcc  -O3 -o kmeans_cuda src/kmeans_cuda.cu
```

### Execução

A entrada é lida da entrada padrão e a saída é escrita na saída padrão.

```bash
./kmeans_seq < data/exemplo.txt

OMP_NUM_THREADS=8 ./kmeans_omp < data/exemplo.txt

mpirun -np 4 ./kmeans_mpi < data/exemplo.txt

OMP_NUM_THREADS=4 mpirun -np 2 ./kmeans_mpi < data/exemplo.txt   # híbrido, se implementado

./kmeans_cuda < data/exemplo.txt
```

### Geração de entradas e verificação

```bash
python3 tools/gen_input.py --k 16 --n 1000000 --seed 42 > data/k16_n1e6.txt
./kmeans_seq < data/k16_n1e6.txt > out_seq.txt
./kmeans_omp < data/k16_n1e6.txt > out_omp.txt
python3 tools/compare.py out_seq.txt out_omp.txt
```

## Formato de entrada e saída

**Entrada (stdin):**

```
k
n
x y z      # k linhas: centroides iniciais
x y z      # n linhas: pontos
```

**Saída (stdout):** `k` linhas com as coordenadas `x y z` dos centroides finais.

**Exemplo** (`k = 3`, `n = 9`):

```
Entrada                         Saída
3
9
-2.0 0.0 1.5                    -0.97  0.67  0.67
 1.0 1.0 1.0                     0.90  1.00  0.40
-1.0 -1.0 0.0                    0.27 -1.17  1.37
-1.2 0.6 0.8
 1.5 0.5 1.8
 0.5 -1.0 0.8
-0.5 1.2 0.7
 1.0 1.5 -0.8
-1.2 0.2 0.5
 0.2 1.0 0.2
-0.2 -1.0 1.8
 0.5 -1.5 1.5
```

## Metodologia de avaliação

**Métricas:**

- **Speedup:** `S(p) = T_seq / T_par(p)`
- **Eficiência:** `E(p) = S(p) / p`
- **Escalabilidade forte:** `n` fixo, variando `p`
- **Escalabilidade fraca:** `n` proporcional a `p`
- **Lei de Amdahl:** estimativa da fração sequencial e comparação com o speedup medido
- **Decomposição do tempo:** leitura de entrada, atribuição, redução/comunicação

**Protocolo:**

- Cada configuração é executada várias vezes (mínimo de 5), reportando média/mediana e desvio.
- Os tempos medem o núcleo do algoritmo separadamente da leitura de entrada (`omp_get_wtime()` / `MPI_Wtime()` / eventos CUDA).
- Parâmetros variados: `n ∈ {10⁴, 10⁶, 10⁷}` e `k ∈ {4, 16, 64}` (ajustar conforme a máquina).
- Todas as saídas são comparadas com a sequencial para garantir correção.

**Ambiente de testes** *(preencher)*:

| Item | Valor |
|---|---|
| CPU | |
| Núcleos / threads | |
| RAM | |
| GPU | |
| SO | |
| Compilador e flags | |

## Resultados

*A preencher após os experimentos.*

| Versão | Configuração | Tempo (s) | Speedup | Eficiência |
|---|---|---|---|---|
| Sequencial | 1 thread | | 1,00 | 1,00 |
| OpenMP | | | | |
| MPI | | | | |
| GPU | | | | |

Gráficos em `results/`.

## Progresso

- [x] Versão sequencial de referência
- [ ] Gerador de entradas e script de comparação
- [ ] OpenMP
- [ ] MPI
- [ ] GPU (CUDA)
- [ ] Scripts de benchmark
- [ ] Análise de desempenho
- [ ] Relatório final

## Autores

- Lucas Froes Belinassi
