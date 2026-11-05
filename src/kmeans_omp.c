#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <omp.h>
#define DIM 3

int main(void) {
    int i, j, k, n, c; 
    double dmin, dx; 
    double *x, *mean, *sum;
    int *cluster, *count, color; 
    int flips;

    // 0 - Bloco de Leitura de dados
    scanf("%d", &k);
    scanf("%d", &n);
    x = (double *)malloc(sizeof(double)*DIM*n);
    mean = (double *)malloc(sizeof(double)*DIM*k);
    sum = (double *)malloc(sizeof(double)*DIM*k);
    cluster = (int *)malloc(sizeof(int)*n); 
    count = (int *)malloc(sizeof(int)*k);

    for (i = 0; i < n; i++) 
        cluster[i] = 0; 
    for (i = 0; i < k; i++)
        scanf("%lf %lf %lf", mean+i*DIM, mean+i*DIM+1, mean+i*DIM+2); 
    for (i = 0; i < n; i++)
        scanf("%lf %lf %lf", x+i*DIM, x+i*DIM+1, x+i*DIM+2);
    flips = n; 

    while (flips > 0) {
        flips = 0;
        // Bloco 1 - Inicializa a contagem de pontos e a soma das coordenadas
        for (j = 0; j < k; j++) { 
            count[j] = 0; // inicializa o contador de pontos pertencentes a cada cluster
            for (i = 0; i < DIM; i++) 
                sum[j*DIM+i] = 0.0; // inicializa a soma dos pontos pertencentes a cada cluster
        }
        // Bloco 2 - Calcula distancia e atualiza cluster de cada ponto
        #pragma omp parallel for private(j, c, dx, dmin, color) \
                         reduction(+:flips)
        for (i = 0; i < n; i++) { // paralelizavel com omp for
            dmin = -1; color = cluster[i];
            // 2.1 - Calcula a distancia entre um ponto e todos os centroides
            for (c = 0; c < k; c++) { 
                dx = 0.0;
                for (j = 0; j < DIM; j++) 
                    dx += (x[i*DIM+j] - mean[c*DIM+j])*(x[i*DIM+j] - mean[c*DIM+j]); 
                if (dx < dmin || dmin == -1) {
                    color = c;
                    dmin = dx;
                }
            }
            // 2.2 - Atualiza o cluster do ponto caso ele tenha mudado de cluster
            if (cluster[i] != color) {
                flips++;
                cluster[i] = color;
            }
        }
        // Bloco 3 - Atualiza a qtd de pontos em cada cluster e a soma dos pontos pertencentes a cada cluster
        #pragma omp parallel for private(j) \
                         reduction(+:count[:k], sum[:k*DIM])
        for (i = 0; i < n; i++) { 
            count[cluster[i]]++; 
            for (j = 0; j < DIM; j++) 
                sum[cluster[i]*DIM+j] += x[i*DIM+j]; 
        }
        // Bloco 4 - Atualiza a posicao dos centroides
        for (i = 0; i < k; i++) { 
            for (j = 0; j < DIM; j++) {
                mean[i*DIM+j] = sum[i*DIM+j]/count[i];
            }
        }
    }
    // Bloco 5 - Impressao final.
    for (i = 0; i < k; i++) { // 5.1 - imprime os centroides 
        for (j = 0; j < DIM; j++)
            printf("%5.2f ", mean[i*DIM+j]);
        printf("\n");
    }

    #ifdef DEBUG 
    for (i = 0; i < n; i++) { // 5.2 - imprime os pontos e o cluster ao qual pertencem
        for (j = 0; j < DIM; j++)
            printf("%5.2f ", x[i*DIM+j]);
        printf("%d\n", cluster[i]);
    }
    #endif

    return(0);
}