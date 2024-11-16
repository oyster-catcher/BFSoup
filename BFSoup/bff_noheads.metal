//
//  bff_noheads.metal
//  BFSoup
//
//  Created by Adrian Skilling on 05/08/2024.
//

#include <metal_stdlib>

#include "ShaderDefinitions.h"

using namespace metal;

/*------------------------------- Compute Shaders -------------------------------------*/

uint32_t pcg32_random_r(thread pcg32_random_t* rng)
{
    uint64_t oldstate = rng->state;
    rng->state = oldstate * 6364136223846793005ULL + rng->inc;
    uint32_t xorshifted = ((oldstate >> 18u) ^ oldstate) >> 27u;
    uint32_t rot = oldstate >> 59u;
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
}

void pcg32_srandom_r(thread pcg32_random_t* rng, uint64_t initstate, uint64_t initseq)
{
    rng->state = 0U;
    rng->inc = (initseq << 1u) | 1u;
    pcg32_random_r(rng);
    rng->state += initstate;
    pcg32_random_r(rng);
}

// range 0 to 1.0
float randomF(thread pcg32_random_t* rng)
{
    //return pcg32_random_r(rng)/float(UINT_MAX);
    return ldexp(float(pcg32_random_r(rng)), -32);
}

float randNormWithMean(thread pcg32_random_t* rng, float mean, float sd)
{
   float u1 = randomF(rng);
   float u2 = randomF(rng);
   float z1 = sqrt(-2 * log(u1)) * cos(2 * M_PI_F * u2);
   return mean + sd * z1;
}


int evaluate(thread uint8_t *tape,
              size_t stepcount) {
  size_t nskip = 0;
  int pos = 0;
  int head0_pos = 0;
  int head1_pos = 0;

  size_t i = 0;
  for (; i < stepcount; i++) {
    head0_pos = head0_pos & (2 * KSINGLETAPESIZE - 1);
    head1_pos = head1_pos & (2 * KSINGLETAPESIZE - 1);
    //if (debug) {
    //  PrintProgramInternal(head0_pos, head1_pos, pos, tape,
    //                       2 * KSINGLETAPESIZE, nullptr, 0);
    //}
    char cmd = tape[pos];
    switch (cmd) {
      case '<':
        head0_pos--;
        break;
      case '>':
        head0_pos++;
        break;
      case '{':
        head1_pos--;
        break;
      case '}':
        head1_pos++;
        break;
      case '+':
        tape[head0_pos]++;
        break;
       case '-':
         tape[head0_pos]--;
         break;
       case '.':
         tape[head1_pos] = tape[head0_pos];
         break;
       case ',':
         tape[head0_pos] = tape[head1_pos];
         break;
       case '[':
         if (!tape[head0_pos]) {
           size_t scanclosed = 1;
           pos++;
           for (; pos < (2 * KSINGLETAPESIZE) && scanclosed > 0; pos++) {
             if (tape[pos] == ']') scanclosed--;
             if (tape[pos] == '[') scanclosed++;
           }
           pos--;
           if (scanclosed != 0) {
             pos = 2 * KSINGLETAPESIZE;
           }
         }
         break;
       case ']':
         if (tape[head0_pos]) {
           size_t scanopen = 1;
           pos--;
           for (; pos >= 0 && scanopen > 0; pos--) {
             if (tape[pos] == ']') scanopen++;
             if (tape[pos] == '[') scanopen--;
           }
           pos++;
           if (scanopen != 0) {
             pos = -1;
           }
         }
         break;
       default:
         nskip++;
     }
     if (pos < 0) {
       i++;
       break;
     }
     pos++;
     if (pos >= 2 * KSINGLETAPESIZE) {
       i++;
       break;
     }
   }
   return i - nskip;
}

kernel void step(device Cell *cells [[buffer(0)]],
                 const device WorldParams &world [[buffer(1)]],
                 const device uint32_t* order [[buffer(2)]],
                 texture2d<float, access::write> out_tex [[texture(3)]],
                 uint2 inpos [[thread_position_in_grid]])
{
   pcg32_random_t randstate;
   uint2 pos;
   uint32_t idx = order[inpos.y*WORLD_WIDTH+inpos.x];
   pos.x = (idx>>16) & 0xffff;
   pos.y = idx & 0xffff;
   randstate.inc = 504063;
   randstate.state = cells[pos.y*WORLD_WIDTH+pos.x].randstate;
   float r = randomF(&randstate);
   if (r < 0.5) {
      cells[pos.y*WORLD_WIDTH+pos.x].randstate = randstate.state;
      return;
   }
   float s = randomF(&randstate);
   float t = randomF(&randstate);
   cells[pos.y*WORLD_WIDTH+pos.x].randstate = randstate.state;
   int2 off = int2((int)((s-0.5)*(1+world.max_dist)*2), (int)((t-0.5)*(1+world.max_dist)*2));
   int2 pos2 = (int2(pos.x,pos.y) + off + int2(WORLD_WIDTH,WORLD_HEIGHT)) % int2(WORLD_WIDTH,WORLD_HEIGHT);
   
   // Don't evaluate this if one of these cells is already being executed on
   // (no a guarantee I think - but its help avoid clashed)
   if ((cells[pos.y*WORLD_WIDTH+pos.x].locked) || (cells[pos2.y*WORLD_WIDTH+pos2.x].locked)) {
      return;
   }
   
   cells[pos.y*WORLD_WIDTH+pos.x].locked = true;
   cells[pos2.y*WORLD_WIDTH+pos2.x].locked = true;
   
   device uint8_t* tape1 = &cells[pos.y*WORLD_WIDTH+pos.x].tape[0];
   device uint8_t* tape2 = &cells[pos2.y*WORLD_WIDTH+pos2.x].tape[0];
   thread uint8_t tape[KSINGLETAPESIZE*2];
   // copy from
   for(int i=0; i<KSINGLETAPESIZE; i++) {
      tape[i] = tape1[i];
      tape[i+KSINGLETAPESIZE] = tape2[i];
   }
 
   // mutate
   float p = world.background_mutation_rate * 0.01;
   for(int i=0; i<KSINGLETAPESIZE; i++) {
      float r = randomF(&randstate);
      if (r < p) {
         tape[i] = randstate.state & 0xff;
      }
   }
 
   // reproduce / run programs
   evaluate(tape, world.max_steps);
   
   // copy back
   for(int i=0; i<KSINGLETAPESIZE; i++) {
      tape1[i] = tape[i];
      tape2[i] = tape[i+KSINGLETAPESIZE];
   }
}

kernel void mutate(device Cell *cells [[buffer(0)]],
                   const device WorldParams &world [[buffer(1)]],
                   uint2 pos [[thread_position_in_grid]])
{
   float p = world.background_mutation_rate * 0.01;
   thread pcg32_random_t randstate;
   randstate.inc = 504063;
   randstate.state = cells[pos.y*WORLD_WIDTH+pos.x].randstate;
   float r = randomF(&randstate);
   device uint8_t* tape = &cells[pos.y*WORLD_WIDTH+pos.x].tape[0];
   for(int i=0; i<KSINGLETAPESIZE; i++) {
      r = randomF(&randstate);
      if (r < p) {
         tape[i] = randstate.state & 0xff;
      }
   }
   cells[pos.y*WORLD_WIDTH+pos.x].randstate = randstate.state;
}

kernel void randomize(device Cell *cells [[buffer(0)]],
                   const device WorldParams &world [[buffer(1)]],
                   uint2 pos [[thread_position_in_grid]])
{
   thread pcg32_random_t randstate;
   randstate.inc = 504063;
   randstate.state = cells[pos.y*WORLD_WIDTH+pos.x].randstate;
   float r = randomF(&randstate);
   device uint8_t* tape = &cells[pos.y*WORLD_WIDTH+pos.x].tape[0];
   for(int i=0; i<KSINGLETAPESIZE; i++) {
      r = randomF(&randstate);
      tape[i] = (int)(randomF(&randstate)*255);
   }
   cells[pos.y*WORLD_WIDTH+pos.x].randstate = randstate.state;
}

kernel void unlock(device Cell *cells [[buffer(0)]],
                   const device WorldParams &world [[buffer(1)]],
                   uint2 pos [[thread_position_in_grid]])
{
   cells[pos.y*WORLD_WIDTH+pos.x].locked = false;
}

kernel void shuffle_order(device Cell *cells [[buffer(0)]],
                          const device WorldParams &world [[buffer(1)]],
                          device uint32_t *order [[buffer(2)]],
                          uint2 pos [[thread_position_in_grid]])
{
   thread pcg32_random_t randstate;
   randstate.inc = 504063;
   randstate.state = cells[0].randstate;
   uint16_t px = 0;
   uint16_t py = 0;
   for(uint i=0; i<WORLD_WIDTH*WORLD_HEIGHT; i++) {
      order[i] = (px<<16) + py;
      px = px + 1;
      if (px > WORLD_WIDTH - 1) {
         px = 0;
         py = py + 1;
      }
   }
   for(uint i=0; i<WORLD_WIDTH*WORLD_HEIGHT/2; i++) {
      uint j = (uint)(randomF(&randstate) * WORLD_WIDTH * WORLD_HEIGHT);
      uint k = (uint)(randomF(&randstate) * WORLD_WIDTH * WORLD_HEIGHT);
      uint32_t tmp = order[j];
      order[j] = order[k];
      order[k] = tmp;
   }
}


// write color of alive cells to texture
kernel void draw(device Cell *cells [[buffer(0)]],
                 const device WorldParams &world [[buffer(1)]],
                 texture2d<float, access::write> out_tex [[texture(2)]],
                 uint2 pos [[thread_position_in_grid]])
{
   for(int e=0;e<=8;e++) {
      out_tex.write(float4(0.1,0.1,0.1,1), 9*pos + uint2(e,8));
      out_tex.write(float4(0.1,0.1,0.1,1), 9*pos + uint2(8,e));
   }

   Cell cell = cells[pos.y*WORLD_WIDTH+pos.x];
   for(int x=0; x<8; x++) {
      for(int y=0; y<8; y++) {
         uint2 posd = uint2(x,7-y);
         float3 col = float3(0,0,0);
         // First instruction top left on texture which has origin (left,bottom)
         int v = cell.tape[y*8+x];
         col = float3(192+v/4,192+v/4,192+v/4);
         switch(v) {
            case 0:
               col = float3(255,0,0);
               break;
            case '[':
            case ']':
               col = float3(0,192,0);
               break;
            case '+':
            case '-':
               //col = float3(200,0,200);
               col = float3(170,0,170);
               break;
            case '.':
            case ',':
               col = float3(200,0,200);
               break;
            case '<':
            case '>':
               col = float3(0,128,220);
               break;
            case '{':
            case '}':
               col = float3(0,128,220);
               break;
         }
         out_tex.write(float4(col/255.0,1), 9*pos + posd);
      }
   }
}
