//
//  ShaderDefinitions.h
//  GravitySim
//
//  Created by Adrian Skilling on 07/03/2023.
//  Copyright © 2023 Apple. All rights reserved.
//

#ifndef ShaderDefinitions_h
#define ShaderDefinitions_h

#include <simd/simd.h>

#define WORLD_WIDTH  196
#define WORLD_HEIGHT 120

//#define WORLD_WIDTH  512
//#define WORLD_HEIGHT 256

#define TEX_WIDTH    (WORLD_WIDTH*9)
#define TEX_HEIGHT   (WORLD_HEIGHT*9)

#define KSINGLETAPESIZE 64

#define BACKGROUND_MUTATION_RATE  0.024

#define MAXDIST  30

#define PAIR_BUFFERS 10

struct Vertex {
   vector_float4 color;
   vector_float2 pos;
};

struct Cell {
   bool locked;
   uint8_t tape[KSINGLETAPESIZE];
   uint64_t randstate;
};

struct TexturedVertex {
   vector_float2 pos;
   vector_float2 texCoord;
};

struct SceneParams {
   vector_float2 cent;
   vector_float2 scale;
};

struct WorldParams {
   int seed;
   bool fixed_shuffle;
   int max_steps;
   int max_dist;
   float background_mutation_rate;
   int width;
   int height;
};

// random numbers
typedef struct { uint64_t state;  uint64_t inc; } pcg32_random_t;


#endif /* ShaderDefinitions_h */
