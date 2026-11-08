# K-Means Paralelo

Versões paralelas do algoritmo **K-Means** em 3D, desenvolvidas como trabalho da disciplina de Programação Paralela e Distribuída, que utiliza como enunciado o Problema D da *12ª Maratona de Programação Paralela (SBAC-PAD & WSCAD, 2017)*. O objetivo é acelerar o programa sequencial original **sem alterar o método de clusterização**.

> **Status:** em desenvolvimento. Veja a seção [Progresso](#progresso).

---

## Sumário

1. [Descrição do problema](#descrição-do-problema)
2. [Formato de entrada e saída](#formato-de-entrada-e-saída)
3. [Algoritmo](#algoritmo)
4. [Estratégia de paralelização](#estratégia-de-paralelização)
5. [Requisitos do sistema](#requisitos-do-sistema)
6. [Estrutura do repositório](#estrutura-do-repositório)
7. [Desenvolvimento](#desenvolvimento)
8. [Análise de desempenho](#análise-de-desempenho)
9. [Resultados](#resultados)
10. [Progresso](#progresso)
11. [Autores](#autores)

---

## Descrição do problema

Dado um conjunto de `n` pontos em ℝ³ e `k` centroides iniciais, o K-Means particiona os pontos em `k` clusters, associando cada ponto ao centroide mais próximo (distância euclidiana). O programa lê os centroides iniciais e os pontos da entrada padrão e imprime as coordenadas dos `k` centroides finais.

Restrição do enunciado: a paralelização **não pode mudar o método de clusterização**. Todas as versões devem produzir a mesma saída que a versão sequencial, a menos de diferenças de arredondamento causadas pela ordem das somas em ponto flutuante.

## Formato de entrada e saída

**Entrada (stdin):**

```
k
n
x y z      # k linhas: centroides iniciais
x y z      # n linhas: pontos
```

**Saída (stdout):** `k` linhas com as coordenadas `x y z` dos centroides finais.

Além disso, cada programa imprime no **stderr** uma linha com o tempo de leitura da entrada e o tempo do núcleo do algoritmo (laço do K-Means), nessa ordem e em segundos, por exemplo `0.5003 68.3298`. Os tempos ficam separados do stdout para que a saída contenha apenas os centroides e possa ser comparada entre as versões.

## Algoritmo

O algoritmo se baseia na repetição dos passos de **atribuição**, momento em que cada ponto é associado ao centroide de menor distância, e **atualização**, bloco em que cada centroide passa a ser a média dos pontos do seu cluster, até alcançar o critério de parada, neste caso definido como o momento em que nenhum centroide é atualizado e nenhum ponto troca de cluster.

O custo por iteração é dado pela complexidade `O(n · k)` na atribuição, `O(n)` na acumulação da soma e da contagem de pontos de cada cluster e `O(k)` no recálculo dos centroides.

## Estratégia de paralelização
<!-- Estrategia que segui apenas no OMP, ainda nao fiz MPI nem CUDA -->
A estratégia utilizada para paralelização da solução partiu do processamento particionado de dados na etapa de atribuição, dividindo-se a quantidade de pontos em ℝ³ que cada thread receberá, visto que estas entradas são independentes entre si e usadas para comparação com os centroides de maneira individual. No OpenMP os centroides são compartilhados entre as threads e apenas lidos nessa etapa; nas versões de memória distribuída (MPI) e de GPU eles são replicados em todos os workers.

Ademais, para correta atualização dos centroides e análise do critério de parada cada worker acumula localmente a **soma**, **contagem de pontos** e **flips** (mudanças de ponto de um cluster a outro) e combina os valores ao final de cada iteração.

Acerca do balanceamento, uma vez que cada thread realizará a mesma operação de comparação entre os pontos e `k` distâncias, a divisão estática em blocos (`schedule(static)`) se apresenta adequada.


| Versão | Modelo | Decomposição | Combinação por iteração |
|---|---|---|---|
| OpenMP | Memória compartilhada | Blocos de pontos por thread | `reduction` sobre `soma[3k]`, `cont[k]` e `flips` |
| MPI | Memória distribuída | Blocos de pontos por processo (`MPI_Scatterv`) | `MPI_Allreduce` de `soma[3k]`, `cont[k]` e flag de mudança |
| GPU (CUDA) | Aceleradora | Uma thread por ponto | Redução por bloco em shared memory (ou `atomicAdd`) |

Em MPI, a comunicação por iteração é `O(k)`, independente de `n`.

## Requisitos do sistema

| Componente | Versão sugerida |
|---|---|
| Compilador C e `make` | GCC ≥ 9 (com suporte a OpenMP) e `make` (`build-essential` no Ubuntu) |
| MPI | OpenMPI ou MPICH |
| CUDA Toolkit | ≥ 11 (apenas para a versão GPU) |
| Python | ≥ 3.8 (gerador de entradas e `compare.py`); `numpy` e `matplotlib` apenas para o `analyze.py` |


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
│   ├── compare.py          # compara saídas com a versão sequencial
│   └── analyze.py          # calcula speedup e eficiência e gera os gráficos
├── scripts/
│   └── run_benchmarks.sh   # executa os experimentos
├── bin/                    # executáveis gerados pelo make
├── data/                   # entradas de teste 
├── results/                # saídas de teste
└── docs/                   # relatório
```

## Desenvolvimento

### Compilação

O repositório apresenta um Makefile pronto para compilação dos arquivos contendo as diferentes abordagens para a solução do problema, que coloca os executáveis na pasta `bin/`. Para compilação destes arquivos basta seguir:

```bash
make all        # compila as versões seq, omp e mpi
make seq        # sequencial
make omp        # OpenMP
make mpi        # MPI
make cuda       # GPU
```

Se por algum motivo preferir não utilizar o Makefile, basta compilar via terminal com os comandos:

```bash
mkdir -p bin
gcc   -O3 -march=native -o bin/kmeans_seq  src/kmeans_seq.c -lm
gcc   -O3 -march=native -fopenmp -o bin/kmeans_omp src/kmeans_omp.c -lm
mpicc -O3 -march=native -o bin/kmeans_mpi  src/kmeans_mpi.c -lm
nvcc  -O3 -o bin/kmeans_cuda src/kmeans_cuda.cu
```
### Criação de entradas

Como apresentado na estrutura do repositório a criação de entradas pode ser feita de maneira automatizada apenas declarando o número de centroides `k`, o número de pontos `n` e, opcionalmente, uma semente para reprodutibilidade. Ademais, para coerência do repositório é indicado que os dados gerados sejam salvos dentro do diretório `data/` utilizando a saída de stdout `>` e o nome do arquivo, como segue:

```bash
python3 tools/gen_input.py 16 1000000 42 > data/k16_n1e6.txt
python3 tools/gen_input.py 50 1000000 42 > data/k50_n1e6.txt
```

### Execução individual

Uma vez compilado o código da solução desejada e geradas as entradas, para a execução basta executar o arquivo indicando que a entrada virá de dentro do diretório `data/` utilizando a entrada de stdin `<`. É recomendado para coerência do repositório a execução mapeando a saída para o diretório `results/` usando a saída de stdout `>`, como segue:

```bash
./bin/kmeans_seq < data/k16_n1e6.txt > results/out_seq.txt 
OMP_NUM_THREADS=6 ./bin/kmeans_omp <  data/k16_n1e6.txt > results/out_omp_6.txt
mpirun -np 4 ./bin/kmeans_mpi < data/k16_n1e6.txt > results/out_mpi_4.txt
./bin/kmeans_cuda < data/k16_n1e6.txt > results/out_cuda.txt
```

Os tempos de leitura e de núcleo saem no stderr e aparecem no terminal; para guardá-los basta redirecioná-los com `2>>`, por exemplo `2>> results/tempos_seq.txt`. Sem a variável `OMP_NUM_THREADS`, o OpenMP utiliza todas as CPUs lógicas visíveis ao sistema.

### Validação

Visando a validação das respostas de cada solução de maneira automática o repositório conta com a ferramenta `compare.py`, capaz de avaliar aos pares os resultados calculados e apontar caso haja divergências acima de um threshold configurável (default de 0.011, que acomoda a diferença de arredondamento na segunda casa decimal causada pela ordem das somas em ponto flutuante), por exemplo:

```bash
python3 tools/compare.py results/out_seq.txt results/out_omp_6.txt
```
### Execução geral

Após a validação de todos os métodos, a execução dos testes de desempenho é automatizada pelo script `scripts/run_benchmarks.sh`. Para uma mesma entrada, ele executa cada versão com diferentes quantidades de threads ou processos, repete cada configuração `REPS` vezes, valida a saída contra a sequencial com o `compare.py` e registra os tempos em `results/benchmark.csv`. A utilização funciona como segue:

```bash
./scripts/run_benchmarks.sh data/k50_n1e6.txt
```

Os parâmetros podem ser ajustados por variáveis de ambiente:

| Variável | Padrão | Descrição |
|---|---|---|
| `REPS` | 5 | Repetições por configuração |
| `THREADS` | `1 2 3 4 5 6` | Quantidades de threads do OpenMP |
| `PROCS` | `1 2 3 4 5 6` | Quantidades de processos do MPI |

Os dados salvos em `results/benchmark.csv` têm a forma:

```
versao,p,rep,leitura,nucleo
seq,1,1,0.5003,68.3298
omp,6,1,0.3724,13.9934
```

Na coluna `p` é registrado o número de threads (OpenMP), o número de processos (MPI) ou `1` (sequencial e CUDA). A cada execução o script recria o arquivo, de modo que rodadas diferentes não se misturam.

## Análise de desempenho

A análise de desempenho foi feita a partir da medição, em cada execução, do tempo de leitura da entrada e do tempo do núcleo do algoritmo (laço do K-Means). Cada configuração é repetida `REPS` vezes e são calculados média, mediana e desvio padrão. As métricas utilizadas são:

- **Speedup:** `S(p) = T_seq / T_par(p)`
- **Eficiência:** `E(p) = S(p) / p`
- **Escalabilidade forte:** `n` fixo, variando `p`
- **Lei de Amdahl:** estimativa da fração sequencial e comparação com o speedup medido
- **Decomposição do tempo:** leitura da entrada e núcleo do algoritmo

O experimento principal usa `k = 50` e `n = 10⁶`, variando de 1 a 6 o número de threads (OpenMP) e de processos (MPI).

A análise é executada de forma automatizada a partir do CSV gerado pelo benchmark:

```bash
python3 tools/analyze.py results/benchmark.csv
```

### Ambiente de testes

| Item | Valor |
|---|---|
| CPU | AMD Ryzen 5 5500 |
| Núcleos / threads | 6 CPUs lógicas visíveis no WSL2 |
| RAM | 11 GiB (alocada ao WSL2) |
| GPU | *(preencher)* |
| SO | Ubuntu 22.04.5 LTS (WSL2) |
| Compilador e flags | gcc 11.4.0, `-O3 -march=native` (`-fopenmp` no OpenMP) |

## Resultados

| Versão | Configuração | Tempo (s) | Speedup | Eficiência |
|---|---|---|---|---|
| Sequencial | 1 thread | | 1,00 | 1,00 |
| OpenMP | | | | |
| MPI | | | | |
| GPU | | | | |

Gráficos em `results/`.

## Progresso

- [x] Versão sequencial de referência
- [x] Makefile para compilação
- [x] Gerador de entradas 
- [x] Script de validação
- [x] OpenMP
- [ ] MPI
- [ ] GPU (CUDA)
- [x] Script de benchmark
- [x] Script para análise de desempenho
- [ ] Análise de desempenho ( Rodar todos )
- [ ] Relatório final

## Autores

- Lucas Froes Belinassi