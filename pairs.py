#!/usr/bin/env python3

import random

used = set()
size = 10
dist = 2

def shuffled_neighbors(i, dist):
  y = int(i/size)
  x = i - (y*size)
  nbs = []
  for dx in range(-dist,dist+1):
    for dy in range(-dist,dist+1):
       if dx!=0 and dy!=0:
         nx = (x + dx + size) % size
         ny = (y + dy + size) % size
         j = (ny * size) + nx
         nbs.append(j)
  random.shuffle(nbs)
  return nbs


pairs = []

order = list(range(size*size))
random.shuffle(order)
#print(order)

successes = 0
fails = 0
# Go through order and find random neigbor
for i in order:
  nbs = shuffled_neighbors(i, dist)
  if i in used:
    #print("REJECTED:", i)
    fails = fails + 1
    continue
  success = False
  for j in nbs:
    if (j not in used):
      success = True
      used.add(i)
      used.add(j)
      pairs.append( (i,j) )
      successes = successes + 1
      break
  if not success:
    #print("FAIL:", i,j)
    fails = fails + 1
  if successes >= (size*size)//4:
    break
print("successes:", successes)
print("fails:", fails)

print(len(pairs))
print(pairs)
