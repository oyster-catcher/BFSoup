//#import <stdlib.h>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#import "ShaderDefinitions.h"

const int num_programs = 8192;
id<MTLBuffer> programsBuffer;
id<MTLBuffer> worldParamsBuffer;
id<MTLComputePipelineState> cpsStep;
id<MTLComputePipelineState> cpsRandomize;


id<MTLComputePipelineState> getCPSWithDevice(id<MTLDevice> device,
                id<MTLLibrary> library, NSString* funcname) {
   id<MTLFunction> func = [library newFunctionWithName:funcname];
   if (func == nil) {
      NSLog(@"Can't find GPU kernel function '%@'", funcname);
   }
   NSError *error;
   id<MTLComputePipelineState> cps = [device newComputePipelineStateWithFunction:func error:&error];
   if (cps==nil) {
      NSLog(@"Can't create Compute Pipeline State: %@", error);
   }
   return cps;
}

void step(id<MTLCommandQueue> commandQueue) {
   id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:cpsStep];
   [computeEncoder setBuffer:programsBuffer offset:0 atIndex:0];
   [computeEncoder setBuffer:worldParamsBuffer offset:0 atIndex:1];
   MTLSize gridSize = MTLSizeMake(WORLD_WIDTH, WORLD_HEIGHT, 1);
   MTLSize threadgroupSize = MTLSizeMake(256,1,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
}

void randomize(id<MTLCommandQueue> commandQueue) {
   id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:cpsRandomize];
   [computeEncoder setBuffer:programsBuffer offset:0 atIndex:0];
   [computeEncoder setBuffer:worldParamsBuffer offset:0 atIndex:1];
   MTLSize gridSize = MTLSizeMake(num_programs, 1, 1);
   MTLSize threadgroupSize = MTLSizeMake(256,1,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
}

void PrintProgramInternal(uint8_t *tape) {
  for(uint i=0; i<64; i++) {
     switch(tape[i]) {
        case '<':
        case '>':
        case '}':
        case '{':
        case '[':
        case ']':
        case '+':
        case '-':
        case '.':
        case ',':
           printf("%c", tape[i]);
           break;
        default:
           printf(" ");
           break;
    }
  }
}

void dump_programs() {
   for(int i=0; i<30; i++) {
     struct Cell *cells = (struct Cell*)(programsBuffer.contents);
     struct Cell *cell = &cells[i];
     printf("%-2d: ", i);
     //for(int b=0; b<64; b++) {
     // printf("%c,",cell->tape[b]);
     //}
     PrintProgramInternal(cell->tape);
     printf("\n");
   }
}

int main() {
  NSError *error;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  id<MTLLibrary> library = [device newDefaultLibrary];
  id<MTLCommandQueue> commandQueue = [device newCommandQueue];

  //id<MTLFunction> funcStep = [library newFunctionWithName:@"stepl"];
  //id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:funcStep error:&error];
  // Prepare data
  uint32_t N = num_programs;
  programsBuffer = [device newBufferWithLength:N*sizeof(struct Cell) options:MTLResourceStorageModeShared];

  worldParamsBuffer = [device newBufferWithLength:sizeof(struct WorldParams) options:MTLResourceStorageModeShared];

  struct  WorldParams* worldParams = (struct WorldParams*)worldParamsBuffer.contents;

  worldParams->max_steps = 1024;
  worldParams->max_dist = 1;
  worldParams->background_mutation_rate = 0.024;
  worldParams->width = num_programs;
  worldParams->height = 1;

  cpsStep = getCPSWithDevice(device, library, @"step");
  cpsRandomize = getCPSWithDevice(device, library, @"randomize");

  NSLog(@"%@",cpsStep);
  NSLog(@"%@",cpsRandomize);

  randomize(commandQueue);

  dump_programs();

  step(commandQueue);
}
