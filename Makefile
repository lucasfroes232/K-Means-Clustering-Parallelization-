CC      ?= gcc
MPICC   ?= mpicc
NVCC    ?= nvcc
CFLAGS  += -O3 -march=native
LDLIBS  += -lm
BIN     := bin

.PHONY: all seq omp mpi cuda clean run
all: seq omp mpi

$(BIN):
	mkdir -p $(BIN)

seq: $(BIN)
	$(CC) $(CFLAGS) src/kmeans_seq.c -o $(BIN)/kmeans_seq $(LDLIBS)

omp: $(BIN)
	$(CC) $(CFLAGS) -fopenmp src/kmeans_omp.c -o $(BIN)/kmeans_omp $(LDLIBS)

mpi: $(BIN)
	$(MPICC) $(CFLAGS) src/kmeans_mpi.c -o $(BIN)/kmeans_mpi $(LDLIBS)

cuda: $(BIN)
	$(NVCC) -O3 src/kmeans_cuda.cu -o $(BIN)/kmeans_cuda

run: seq
	./$(BIN)/kmeans_seq < data/exemplo.txt

clean:
	rm -rf $(BIN)