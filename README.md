# K-Means Paralelo

Versões paralelas do algoritmo **K-Means** em 3D, desenvolvidas como trabalho da disciplina de Programação Paralela e Distribuída, que utiliza como enunciado o Problema D da *12ª Maratona de Programação Paralela (SBAC-PAD & WSCAD, 2017)*. O objetivo é acelerar o programa sequencial original **sem alterar o método de clusterização**.

O relatório executável está em [`relatório.ipynb`](relatório.ipynb). O estudo contempla as versões sequencial, OpenMP e MPI.

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
10. [Autores](#autores)

---

## Descrição do problema

Dado um conjunto de `n` pontos em ℝ³ e `k` centroides iniciais, o K-Means particiona os pontos em `k` clusters, associando cada ponto ao centroide mais próximo (distância euclidiana). O programa lê os centroides iniciais e os pontos da entrada padrão e imprime as coordenadas dos `k` centroides finais.

Restrição do enunciado: a paralelização **não pode mudar o método de clusterização**. As versões são comparadas com a saída sequencial, considerando diferenças de arredondamento causadas pela ordem das somas em ponto flutuante. Há uma diferença no tratamento de clusters vazios, descrita nas limitações.

## Formato de entrada e saída

**Entrada (stdin):**

```
k
n
x y z      # k linhas: centroides iniciais
x y z      # n linhas: pontos
```

**Saída (stdout):** `k` linhas com as coordenadas `x y z` dos centroides finais.

Cada programa também imprime no **stderr** dois tempos em segundos: preparação/leitura e núcleo do algoritmo. No MPI, o primeiro intervalo inclui distribuição dos pontos e sincronização inicial. Esses tempos ficam separados do stdout, que contém os centroides.

## Algoritmo

O algoritmo se baseia na repetição dos passos de **atribuição**, momento em que cada ponto é associado ao centroide de menor distância, e **atualização**, bloco em que cada centroide passa a ser a média dos pontos do seu cluster, até que nenhum ponto troque de cluster, condição verificada pelas implementações.

O custo por iteração é dado pela complexidade `O(n · k)` na atribuição, `O(n)` na acumulação da soma e da contagem de pontos de cada cluster e `O(k)` no recálculo dos centroides.

## Estratégia de paralelização

Os pontos são divididos entre trabalhadores, que calculam sua atribuição ao centroide mais próximo e acumulam somas e contagens por cluster. Os resultados são combinados a cada iteração para atualizar os centroides e determinar se houve mudanças de atribuição.

| Versão | Modelo | Decomposição | Combinação por iteração |
|---|---|---|---|
| OpenMP | Memória compartilhada | Pontos divididos entre threads | Reduções sobre mudanças, somas e contagens |
| MPI | Memória distribuída | Blocos de pontos distribuídos com `MPI_Scatterv` | Três chamadas `MPI_Allreduce` para mudanças, contagens e somas |

Cada ponto é comparado aos mesmos `k` centroides, o que tende a favorecer o balanceamento. No MPI, o último processo recebe todo o resto da divisão de pontos; no OpenMP o código não especifica uma cláusula `schedule`. Quando há poucos pontos por trabalhador, sincronização, reduções e comunicação passam a representar uma parcela maior do trabalho. No MPI, as reduções envolvem `O(k)` dados por processo, mas seu tempo também depende do número de processos e da rede.

## Requisitos do sistema

| Componente | Versão sugerida |
|---|---|
| Compilador C e `make` | GCC ≥ 9 (com suporte a OpenMP) e `make` (`build-essential` no Ubuntu) |
| MPI | OpenMPI ou MPICH |
| Python | ≥ 3.8 (gerador de entradas e `compare.py`); `numpy` e `matplotlib` apenas para o `analyze.py` |


## Estrutura do repositório

```
.
├── README.md
├── Makefile
├── job.sh                  # comandos de preparação para o cluster
├── relatório.ipynb         # relatório executável no Colab
├── src/
│   ├── kmeans_seq.c        # versão sequencial (referência)
│   ├── kmeans_omp.c        # OpenMP
│   └── kmeans_mpi.c        # MPI
├── tools/
│   ├── gen_input.py        # gerador de entradas aleatórias
│   ├── compare.py          # compara saídas com a versão sequencial
│   └── analyze.py          # calcula speedup e eficiência e gera os gráficos
├── scripts/
│   └── run_benchmark.sh   # executa os experimentos
├── bin/                    # executáveis gerados pelo make
├── data/                   # entradas de teste 
└── results/                # medições, tabelas e gráficos
    └── analise_FINAL/       # análise do experimento principal
```

## Desenvolvimento

### Compilação

O repositório apresenta um Makefile pronto para compilação dos arquivos contendo as diferentes abordagens para a solução do problema, que coloca os executáveis na pasta `bin/`. Para compilação destes arquivos basta seguir:

```bash
make all        # compila as versões seq, omp e mpi
make seq        # sequencial
make omp        # OpenMP
make mpi        # MPI
```

Se por algum motivo preferir não utilizar o Makefile, basta compilar via terminal com os comandos:

```bash
mkdir -p bin
gcc   -O3 -march=native -o bin/kmeans_seq  src/kmeans_seq.c -lm
gcc   -O3 -march=native -fopenmp -o bin/kmeans_omp src/kmeans_omp.c -lm
mpicc -O3 -march=native -o bin/kmeans_mpi  src/kmeans_mpi.c -lm
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
```

Os tempos de leitura e de núcleo saem no stderr e aparecem no terminal; para guardá-los basta redirecioná-los com `2>>`, por exemplo `2>> results/tempos_seq.txt`. Sem a variável `OMP_NUM_THREADS`, o OpenMP utiliza todas as CPUs lógicas visíveis ao sistema.

### Validação

Visando a validação das respostas de cada solução de maneira automática o repositório conta com a ferramenta `compare.py`, capaz de avaliar aos pares os resultados calculados e apontar caso haja divergências acima de um threshold configurável (default de 0.011, que acomoda a diferença de arredondamento na segunda casa decimal causada pela ordem das somas em ponto flutuante), por exemplo:

```bash
python3 tools/compare.py results/out_seq.txt results/out_omp_6.txt
```
### Execução geral

O script `scripts/run_benchmark.sh` executa as versões com diferentes quantidades de threads ou processos, compara as saídas e registra tempos em `results/benchmark.csv`. Antes de usá-lo, corrija o espaço após a barra de continuação na linha do `printf`, que impede a continuação correta do comando. Com essa correção, a chamada é:

```bash
./scripts/run_benchmark.sh data/k50_n1e6.txt
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

Na coluna `p` é registrado o número de threads (OpenMP), o número de processos (MPI) ou `1` (sequencial). A cada execução o script recria o arquivo, de modo que rodadas diferentes não se misturam.

## Análise de desempenho

Realizamos os experimentos em um cluster da universidade, usando uma entrada com `k = 16` centroides e `n = 1.000.000` pontos. Para OpenMP e MPI, usamos 1, 2, 4, 8, 16 e 20 threads ou processos, com cinco repetições por configuração.

As métricas abaixo usam as medianas das medições. O speedup do núcleo é `S(p) = T_seq / T_par(p)`, e a eficiência é `E(p) = S(p) / p`. Como a entrada permanece fixa e o número de trabalhadores varia, trata-se de escalabilidade forte. O speedup de leitura mais núcleo usa a mediana da soma desses intervalos em cada execução; essa soma não abrange necessariamente a execução completa.

### Ambiente de testes

| Item | Valor |
|---|---|
| CPU | x86_64, 2 sockets, 10 núcleos por socket e 2 threads por núcleo |
| CPUs lógicas | 40 |
| RAM | 386 GB |
| Sistema operacional | Rocky Linux 8.10 |
| Compilador | GCC 9.4.0 |

Uma execução MPI com entrada pequena está disponível no Colab para demonstração; os resultados a seguir foram coletados no cluster.

## Resultados

A tabela apresenta as medianas do núcleo e os speedups calculados a partir delas. A eficiência sequencial não se aplica; `p` indica threads no OpenMP e processos no MPI.

| Versão | p | Núcleo mediano (s) | Speedup do núcleo | Eficiência | Speedup leitura + núcleo |
|---|---:|---:|---:|---:|---:|
| Sequencial | 1 | 18,698 | 1,00 | — | 1,00 |
| OpenMP | 1 | 18,440 | 1,01 | 1,014 | 1,01 |
| OpenMP | 2 | 9,204 | 2,03 | 1,016 | 1,96 |
| OpenMP | 4 | 4,805 | 3,89 | 0,973 | 3,53 |
| OpenMP | 8 | 2,575 | 7,26 | 0,908 | 5,94 |
| OpenMP | 16 | 1,339 | 13,96 | 0,872 | 9,55 |
| OpenMP | 20 | 1,083 | 17,27 | 0,864 | 10,93 |
| MPI | 1 | 18,480 | 1,01 | 1,012 | 1,01 |
| MPI | 2 | 9,324 | 2,01 | 1,003 | 1,92 |
| MPI | 4 | 5,180 | 3,61 | 0,902 | 3,24 |
| MPI | 8 | 2,693 | 6,94 | 0,868 | 5,52 |
| MPI | 16 | 1,364 | 13,71 | 0,857 | 8,89 |
| MPI | 20 | 1,081 | 17,29 | 0,864 | 10,16 |

Com 20 trabalhadores, as duas versões atingiram cerca de 17,3 vezes o desempenho sequencial no núcleo. A eficiência ficou próxima de 86%, e o ganho calculado sobre leitura mais núcleo foi menor, pois a preparação representa uma parcela maior do intervalo medido. Os dados não isolam os custos de comunicação ou sincronização; portanto, as causas da queda de eficiência são hipóteses, não medições diretas.

Os resultados e gráficos estão disponíveis nos arquivos:

- [Medições principais](results/benchmark_FINAL.csv) e [tabela completa](results/analise_FINAL/tabela_desempenho.md).
- [Speedup](results/analise_FINAL/speedup.png), [eficiência](results/analise_FINAL/eficiencia.png) e [decomposição dos tempos](results/analise_FINAL/decomposicao.png).
- [Experimento grande incompleto](results/benchmark_large_INCOMPLETO.csv): uma repetição por configuração paralela e duas sequenciais. Ele é um registro parcial, sem análise de variabilidade comparável à do experimento principal.

Para gerar novamente a análise do CSV principal em outro diretório, sem sobrescrever os gráficos existentes:

```bash
python3 tools/analyze.py results/benchmark_FINAL.csv --saida results/analise_nova
```

O ajuste de Amdahl e o indicador Karp-Flatt da análise são calculados a partir do speedup do núcleo e devem ser interpretados nesse intervalo, não como medições diretas da fração de leitura.

### Limitações

A comparação de saídas usa os centroides impressos com duas casas decimais. Em clusters vazios, MPI mantém o centroide anterior, enquanto as versões sequencial e OpenMP podem produzir valores não finitos por divisão por zero. O comparador existente não rejeita explicitamente esses valores. Essas condições limitam a validação a partir das saídas disponíveis.

O script de benchmark recria `results/benchmark.csv` ao ser executado; preserve esse arquivo antes de uma nova rodada. O `job.sh` disponível contém comandos para gerar e executar outro script, portanto deve ser revisado antes de ser usado como arquivo Slurm. O projeto não pretende repetir os experimentos já coletados.

## Autores

- Lucas Froes Belinassi
- Marcus Vinicius de Andrade Silva
- Maurício Alonzo
- Vinícius Ferreira Araujo