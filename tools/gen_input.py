#!/usr/bin/env python3
import sys
from random import uniform, seed

# Uso: gen_input.py k n [seed]   (competição: k=50, n=1000000)
k = int(sys.argv[1])
n = int(sys.argv[2])
if len(sys.argv) > 3:
    seed(int(sys.argv[3]))      # reprodutibilidade dos experimentos

print(k)
print(n)
for _ in range(k + n):
    print("%f %f %f" % (uniform(-100, 100), uniform(-100, 100), uniform(-100, 100)))