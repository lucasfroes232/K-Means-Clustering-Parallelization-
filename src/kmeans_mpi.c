#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <mpi.h>

#define DIM 3
#include <time.h>

//Apesar de 3 dimensoes, preferimos utilizar vetores 1D,
//    para fazer bom uso dos valores contiguos na memoria

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;   // segundos, como double
}

int main(int argc, char *argv[]) {
	int i, j, k, n, c;
	double dmin, dx;
	double *x, *mean, *sum;
	int *cluster, *count, color; 
	int flips;

	//k: numero de centroides
	// n: total de pontos
    //x: coords de todos os pontos
	//mean: coords dos centroides
	// cluster: guarda o centroide representante de cada ponto
	// count: qnts pontos tem cada centroide
	//sum: soma das coordenadas de cada centroide
	//flips: criterio de parada

    int rank, size;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    double t0;
    if(rank == 0){
        //apenas mestre mede o tempo
    	t0 = now();
        // apenas mestre le entrada para evidaar race conditions
	    scanf("%d", &k);
	    scanf("%d", &n);
    }
    // passa valores de k e n para outros processos
    MPI_Bcast(&k, 1, MPI_INT, 0, MPI_COMM_WORLD);
    MPI_Bcast(&n, 1, MPI_INT, 0, MPI_COMM_WORLD);

	mean = (double *)malloc(sizeof(double)*DIM*k);
	sum= (double *)malloc(sizeof(double)*DIM*k);
	count = (int *)malloc(sizeof(int)*k);

    if(rank == 0){
        // aloca vetores para todos os pontos, serao subdividos depois
       x = (double *)malloc(sizeof(double)*DIM*n);
       cluster = (int *)malloc(sizeof(int)*n);

        // apenas mestre faz leitura dos pontos
       	for (i = 0; i<n; i++) 
		cluster[i] = 0;
	    for (i = 0; i<k; i++)
		    scanf("%lf %lf %lf", mean+i*DIM, mean+i*DIM+1, mean+i*DIM+2);
	    for (i = 0; i<n; i++)
		    scanf("%lf %lf %lf", x+i*DIM, x+i*DIM+1, x+i*DIM+2);

    }
    // passa centroides para outros processos
    MPI_Bcast(mean, k * DIM, MPI_DOUBLE, 0, MPI_COMM_WORLD);


    int *qtd_a_enviar = (int *)malloc(sizeof(int) * size);// quantos pontos proc p vai receber
    int *offset = (int *)malloc(sizeof(int) * size);// posicao de x em que proc p comeca a receber
    
     
    int resto = n % size;
    int tamanho_base = n / size;

    // define subdivisoes x para cada proc p
    for(int p = 0; p < size; p++){
        int pontos_deste_proc = tamanho_base;

        if(p == size -1){
            pontos_deste_proc = pontos_deste_proc + resto;
        }

        qtd_a_enviar[p] = pontos_deste_proc * DIM;
        offset[p] = p * tamanho_base * DIM;
    }
    int n_local = qtd_a_enviar[rank] / DIM;

    // declaracao dos vetores locais
    double* x_local = (double*)malloc(sizeof(double) *n_local * DIM);
    int* cluster_local = (int*)malloc(sizeof(int) * n_local);
    
    //padroniza representantes iniciais de cada ponto
    for(i = 0; i < n_local; i++)
        cluster_local[i] = 0;

    // repasse dos pontos para cada proc
    MPI_Scatterv(x, qtd_a_enviar, offset, MPI_DOUBLE, x_local, 
        qtd_a_enviar[rank], MPI_DOUBLE, 0, MPI_COMM_WORLD);
    
    // serao parametros do MPIReduce posteriormente
    double *sum_local = (double *)malloc(sizeof(double) * DIM * k);
    int* count_local = (int*)malloc(sizeof(int) * k);

    MPI_Barrier(MPI_COMM_WORLD); // garantir q todos processos estejam juntos

    double t1;
    if(rank == 0)
        t1 = now();

	flips = n;
	while (flips>0) {
		int flips_local = 0;
		//zerando variaveis para nova iteração
		for (j = 0; j < k; j++) {
			count_local[j] = 0; 
			for (i = 0; i < DIM; i++) 
				sum_local[j*DIM+i] = 0.0;
		}

		// calculo da distancia de todos os pontos desse proc para todos centroides
		for (i = 0; i < n_local; i++) {
			dmin = -1; color = cluster_local[i];
			for (c = 0; c < k; c++) {
				dx = 0.0;
				for (j = 0; j < DIM; j++) 
					dx +=  (x_local[i*DIM+j] - mean[c*DIM+j])*(x_local[i*DIM+j] - mean[c*DIM+j]);
				// dmin guarda a distancia para centroide mais proximo e color guarda qual eh tal centroide
				if (dx < dmin || dmin == -1) {
					color = c;
					dmin = dx;
				}
			}
			// troca/mantém o centroide de cada ponto + define critério de parada
			if (cluster_local[i] != color) {
				flips_local++;
				cluster_local[i] = color;
	      	}
		}
		//atualiza count e sum locais
	    for (i = 0; i < n_local; i++) {
			count_local[cluster_local[i]]++;
			for (j = 0; j < DIM; j++) 
				sum_local[cluster_local[i]*DIM+j] += x_local[i*DIM+j];
		}

        // atualizar flips, count e sum globais
        MPI_Allreduce(&flips_local, &flips, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
        MPI_Allreduce(count_local, count, k, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
        MPI_Allreduce(sum_local, sum, k * DIM, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);


		//atualiza coords dos centroies
		for (i = 0; i < k; i++) {
            if(count[i] > 0){
			    for (j = 0; j < DIM; j++) {
				    mean[i*DIM+j] = sum[i*DIM+j]/count[i];
  			    }
            }
		}
	}

	double t2;
    //apena mestre fara os prints
    if(rank == 0){
        t2 = now();

        //printa coordenadas dos centroides
	for (i = 0; i < k; i++) {
		for (j = 0; j < DIM; j++)
			printf("%5.2f ", mean[i*DIM+j]);
		printf("\n");


    }
	
	
	#ifdef DEBUG
	for (i = 0; i < n; i++) {
		for (j = 0; j < DIM; j++)
			printf("%5.2f ", x[i*DIM+j]);
		printf("%d\n", cluster[i]);
	}
	#endif
	// printa separadamente os tempos de leitura e cálculo
	fprintf(stderr, "%.4f %.4f\n", t1 - t0, t2 - t1);   
    }
    //libera memoria
    free(mean);
    free(sum);
    free(count);
    free(qtd_a_enviar);
    free(offset);
    free(x_local);
    free(cluster_local);
    free(sum_local);
    free(count_local);

    // libera a memoria alocada apenas no mestre
    if (rank == 0) {
        free(x);
        free(cluster);
    }

    MPI_Finalize();
	return(0);
}
