#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define DIM 3
#include <time.h>

//Apesar de 3 dimensoes, preferimos utilizar vetores 1D,
//    para fazer bom uso dos valores contiguos na memoria

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;   // segundos, como double
}

int main(void) {
	int i, j, k, n, c;
	double dmin, dx;
	double *x, *mean, *sum;
	int *cluster, *count, color; 
	int flips;

	//k: numero de centroides
	// n: total de pontos
	//mean: coords dos centroides
	// cluster: guarda o centroide representante de cada ponto
	// count: qnts pontos tem cada centroide
	//sum: soma das coordenadas de cada centroide
	//flips: criterio de parada

	double t0 = now();
	scanf("%d", &k);
	scanf("%d", &n);
	x = (double *)malloc(sizeof(double)*DIM*n);
	mean = (double *)malloc(sizeof(double)*DIM*k);
	sum= (double *)malloc(sizeof(double)*DIM*k);
	cluster = (int *)malloc(sizeof(int)*n);
	count = (int *)malloc(sizeof(int)*k);
	for (i = 0; i<n; i++) 
		cluster[i] = 0;
	for (i = 0; i<k; i++)
		scanf("%lf %lf %lf", mean+i*DIM, mean+i*DIM+1, mean+i*DIM+2);
	for (i = 0; i<n; i++)
		scanf("%lf %lf %lf", x+i*DIM, x+i*DIM+1, x+i*DIM+2);
	flips = n;

	double t1 = now();
	while (flips>0) {
		flips = 0;
		//zerando variaveis para nova iteração
		for (j = 0; j < k; j++) {
			count[j] = 0; 
			for (i = 0; i < DIM; i++) 
				sum[j*DIM+i] = 0.0;
		}

		// calculo da distancia de todos os pontos para todos centroides
		for (i = 0; i < n; i++) {
			dmin = -1; color = cluster[i];
			for (c = 0; c < k; c++) {
				dx = 0.0;
				for (j = 0; j < DIM; j++) 
					dx +=  (x[i*DIM+j] - mean[c*DIM+j])*(x[i*DIM+j] - mean[c*DIM+j]);
				// dmin guarda a distancia para centroide mais proximo e color guarda qual eh tal centroide
				if (dx < dmin || dmin == -1) {
					color = c;
					dmin = dx;
				}
			}
			// troca/mantém o centroide de cada ponto + define critério de parada
			if (cluster[i] != color) {
				flips++;
				cluster[i] = color;
	      	}
		}
		//atualiza count e sum
	    for (i = 0; i < n; i++) {
			count[cluster[i]]++;
			for (j = 0; j < DIM; j++) 
				sum[cluster[i]*DIM+j] += x[i*DIM+j];
		}

		//atualiza coords dos centroies
		for (i = 0; i < k; i++) {
			for (j = 0; j < DIM; j++) {
				mean[i*DIM+j] = sum[i*DIM+j]/count[i];
  			}
		}
	}
	double t2 = now();
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
	return(0);
}
