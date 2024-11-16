//
//  World.m
//  PlantSoup
//
//  Created by Adrian Skilling on 08/07/2024.
//

#import <Foundation/Foundation.h>

#import "Objects.h"
#import "World.h"
#import "ShaderDefinitions.h"
#import "NativeJSONSerializer.h"

@implementation World
id<MTLDevice> _device;
struct WorldParams* _worldParams;
id<MTLCommandQueue> _commandQueue;
id<MTLBuffer> _worldParamsBuffer;
id<MTLBuffer> _sceneParamsBuffer; // view transform and instance count for main view
id<MTLBuffer> _cellsBuffer1;
id<MTLBuffer> _tmpCellsBuffer;
id<MTLTexture> _texture;
id<MTLBuffer> _vertexBuffer;
id<MTLBuffer> _orderBuffer;
id<MTLBuffer> _pairsBuffer[PAIR_BUFFERS];
struct Cell* _cells;
Objects* _objects;
id<MTLComputePipelineState> _cpsDraw;
id<MTLComputePipelineState> _cpsStep;
id<MTLComputePipelineState> _cpsMutate;
id<MTLComputePipelineState> _cpsRandomize;
id<MTLComputePipelineState> _cpsUnlock;
id<MTLComputePipelineState> _cpsShuffleOrder;
int _epoch;

uint32_t pcg32_random_r(pcg32_random_t* rng)
{
    uint64_t oldstate = rng->state;
    rng->state = oldstate * 6364136223846793005ULL + rng->inc;
    uint32_t xorshifted = (uint32_t)(((oldstate >> 18u) ^ oldstate) >> 27u);
    uint32_t rot = oldstate >> 59u;
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
}

void pcg32_srandom_r(pcg32_random_t* rng, uint64_t initstate, uint64_t initseq)
{
    rng->state = 0U;
    rng->inc = (initseq << 1u) | 1u;
    pcg32_random_r(rng);
    rng->state += initstate;
    pcg32_random_r(rng);
}

- (id)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library worldParamsBuffer:(id<MTLBuffer>)worldParamsBuffer {
   self = [super init];
   _device = device;
   _commandQueue = [device newCommandQueue];
   _worldParamsBuffer = worldParamsBuffer;
   _worldParams = (struct WorldParams*)worldParamsBuffer.contents;
   _sceneParamsBuffer = [_device newBufferWithLength:sizeof(struct SceneParams) options:MTLResourceStorageModeShared];

   MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor new];
   textureDescriptor.textureType = MTLTextureType2D;
   textureDescriptor.usage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
   textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
   textureDescriptor.width = TEX_WIDTH;
   textureDescriptor.height = TEX_HEIGHT;
   textureDescriptor.depth = 1;
   textureDescriptor.sampleCount = 1;
   textureDescriptor.mipmapLevelCount = 6;
   textureDescriptor.storageMode = MTLStorageModePrivate;
   _texture = [_device newTextureWithDescriptor:textureDescriptor];
   
   _objects = [[Objects alloc] initWithDevice:device];

   // Create vertex buffer for texture drawing
   struct TexturedVertex vertices[6];
   float width = (float)TEX_WIDTH/(float)TEX_HEIGHT;
   vertices[0].pos.x = -width;
   vertices[0].pos.y = -1;
   vertices[0].texCoord.x = 0;
   vertices[0].texCoord.y = 0;
   vertices[1].pos.x = -width;
   vertices[1].pos.y = 1;
   vertices[1].texCoord.x = 0;
   vertices[1].texCoord.y = 1;
   vertices[2].pos.x = width;
   vertices[2].pos.y = 1;
   vertices[2].texCoord.x = 1;
   vertices[2].texCoord.y = 1;
   // next tri
   vertices[3].pos.x = -width;
   vertices[3].pos.y = -1;
   vertices[3].texCoord.x = 0;
   vertices[3].texCoord.y = 0;
   vertices[4].pos.x = width;
   vertices[4].pos.y = 1;
   vertices[4].texCoord.x = 1;
   vertices[4].texCoord.y = 1;
   vertices[5].pos.x = width;
   vertices[5].pos.y = -1;
   vertices[5].texCoord.x = 1;
   vertices[5].texCoord.y = 0;

   _worldParams->background_mutation_rate = BACKGROUND_MUTATION_RATE;
   _worldParams->max_steps = 512;
   _worldParams->max_dist = 2;
   _worldParams->fixed_shuffle = true;
   _worldParams->seed = 123456789;

   _vertexBuffer = [_device newBufferWithBytes:vertices length:sizeof(struct TexturedVertex)*6 options:MTLResourceStorageModeShared];

   _tmpCellsBuffer = [_device newBufferWithLength:sizeof(struct Cell)*WORLD_WIDTH*WORLD_HEIGHT options:MTLResourceStorageModeShared];

   //[self initRandomValues:(struct Cell*)_tmpCellsBuffer.contents seed:_worldParams->seed];
   
   _cellsBuffer1 = [_device newBufferWithLength:sizeof(struct Cell)*WORLD_WIDTH*WORLD_HEIGHT options:MTLResourceStorageModePrivate];
   [self copyBufferFrom:_tmpCellsBuffer to:_cellsBuffer1 size:_tmpCellsBuffer.length];
   
   _orderBuffer = [_device newBufferWithLength:sizeof(uint32_t)*WORLD_WIDTH*WORLD_HEIGHT options:MTLResourceStorageModePrivate];

   _cpsDraw = [self getCPSWithDevice:device library:library funcname:@"draw"];
   _cpsStep = [self getCPSWithDevice:device library:library funcname:@"step"];
   _cpsMutate = [self getCPSWithDevice:device library:library funcname:@"mutate"];
   _cpsRandomize = [self getCPSWithDevice:device library:library funcname:@"randomize"];
   _cpsUnlock = [self getCPSWithDevice:device library:library funcname:@"unlock"];
   _cpsShuffleOrder = [self getCPSWithDevice:device library:library funcname:@"shuffle_order"];
   _epoch = 0;
   
   [self reset:_worldParams->seed];
   [self shuffle_order];

   return self;
}

- (void)initRandomValues:(struct Cell*)cells seed:(long int)seed {
   pcg32_random_t rand;
   pcg32_srandom_r(&rand, seed, seed);
   rand.inc = 504063;
   long randstate = rand.state;
   for(int i=0; i<WORLD_WIDTH; i++) {
      for(int j=0; j<WORLD_HEIGHT; j++) {
         struct Cell *cell = &cells[j*WORLD_WIDTH+i];
         cell->randstate = seed++;
         //randstate = arc4random_uniform(1<<31);
      }
   }
}

- (int)epoch {
   return _epoch;
}

- (id<MTLComputePipelineState>)getCPSWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library funcname:(NSString*)funcname {
   id<MTLFunction> func = [library newFunctionWithName:funcname];
   NSAssert(func!=nil, @"Can't find GPU kernel function '%@'", funcname);
   NSError *error;
   id<MTLComputePipelineState> cps = [device newComputePipelineStateWithFunction:func error:&error];
   NSAssert(error==nil, @"Can't create Compute Pipeline State: %@", error);
   return cps;
}

- (void)copyBufferFrom:(id<MTLBuffer>)fromBuffer to:(id<MTLBuffer>)toBuffer size:(long)size {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLBlitCommandEncoder> blitCommandEncoder = [commandBuffer blitCommandEncoder];
   [blitCommandEncoder copyFromBuffer:fromBuffer sourceOffset:0 toBuffer:toBuffer destinationOffset:0 size:size];
   [blitCommandEncoder endEncoding];
   [commandBuffer commit];
   [commandBuffer waitUntilCompleted];
}

- (void)copyBufferFrom:(id<MTLBuffer>)fromBuffer fromOffset:(long)fromOffset to:(id<MTLBuffer>)toBuffer toOffset:(long)toOffset size:(int)size {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLBlitCommandEncoder> blitCommandEncoder = [commandBuffer blitCommandEncoder];
   [blitCommandEncoder copyFromBuffer:fromBuffer sourceOffset:fromOffset toBuffer:toBuffer destinationOffset:toOffset size:size];
   [blitCommandEncoder endEncoding];
   [commandBuffer commit];
   [commandBuffer waitUntilCompleted];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
         renderPipelineState:(id<MTLRenderPipelineState>)renderPipelineState
                        centX:(float)centX centY:(float)centY
                       scaleX:(float)scaleX scaleY:(float)scaleY {
   
   struct SceneParams scene;
   
   scene.cent.x = centX;
   scene.cent.y = centY;
   scene.scale.x = scaleX;
   scene.scale.y = scaleY;
   memcpy(_sceneParamsBuffer.contents, &scene, sizeof(struct SceneParams));
   

   // texture
   [renderEncoder setRenderPipelineState:renderPipelineState];
   [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
   [renderEncoder setVertexBuffer:_sceneParamsBuffer offset:0 atIndex:1];
   [renderEncoder setFragmentTexture:_texture atIndex:0];
   [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
   
}

- (void)compute:(int)speed {
   for(int step=0; step<speed; step++) {
      if (_epoch % 1 == 0) {
         if (!_worldParams->fixed_shuffle) {
            [self shuffle_order];
         }
         [self unlock];
         [self step];
         //[self mutate];
      }
      //if (_epoch % 4 == 0) {
      //   [self mutate];
      //}
      _epoch++;
   }

   [self draw];
   
}

- (void)setCellX:(int)x Y:(int)y program:(int)program {
   struct Cell* cells = _tmpCellsBuffer.contents;
   struct Cell* cell = &cells[y*WORLD_WIDTH+x];
   unsigned long offset = (y*WORLD_WIDTH+x) * sizeof(struct Cell);
   for(int i=0; i<KSINGLETAPESIZE; i++) {
      cell->tape[i] = 0;
   }
   switch(program) {
      case 1:
         cell->tape[0] = '.';
         cell->tape[1] = '[';
         cell->tape[2] = '[';
         cell->tape[3] = '<';
         cell->tape[4] = ',';
         cell->tape[5] = '}';
         cell->tape[6] = ']';
         cell->tape[7] = ']';
         cell->tape[8] = '}';
         cell->tape[9] = ',';
         cell->tape[10] = '<';
         cell->tape[11] = '[';
         cell->tape[12] = '[';
         cell->tape[13] = '.';
         cell->tape[14] = '.';
         break;
      case 2:
         cell->tape[0] = 64;
         cell->tape[1] = 64;
         cell->tape[2] = '[';
         cell->tape[3] = '-'; // decrement 64
         cell->tape[4] = '}'; // head1 = head1 + 1
         cell->tape[5] = ']'; // end of loop to increment head1 by 64
         cell->tape[6] = '>'; // move to next 64 at tape[1]
         cell->tape[7] = '.'; // tape[head1] = tape[head0]
         cell->tape[8] = '}'; // head1=head1+1
         cell->tape[9] = '[';
         cell->tape[10] = '.'; // tape[head1] = tape[head0]
         cell->tape[11] = '>';
         cell->tape[12] = '}';
         cell->tape[13] = ']'; // loop to bytes to destination until hit 0
         cell->tape[14] = 0;
         cell->tape[15] = 0;
         cell->tape[16] = 0;
         cell->tape[17] = 0;
         cell->tape[18] = 0;
         cell->tape[19] = 0;
         break;
      case 3:
         for(int i=0; i<KSINGLETAPESIZE; i++) {
            cell->tape[i] = '<';
         }
         break;
   }

   [self copyBufferFrom:_tmpCellsBuffer fromOffset:offset to:_cellsBuffer1 toOffset:offset size:sizeof(struct Cell)];
}

- (struct Cell*)getCellX:(int)x Y:(int)y {
   struct Cell* cells = _tmpCellsBuffer.contents;
   struct Cell* cell = &cells[y*WORLD_WIDTH+x];
   return cell;
}

- (void)syncGpuCells {
   [self copyBufferFrom:_cellsBuffer1 to:_tmpCellsBuffer size:_cellsBuffer1.length];
}

- (NSString*)cellTapeToString:(struct Cell*)cell {
   NSMutableString *hexStr =
      [NSMutableString stringWithCapacity:KSINGLETAPESIZE*2];
   int i;
   for (i = 0; i < KSINGLETAPESIZE; i++) {
       [hexStr appendFormat:@"%02x", cell->tape[i]];
   }
   return hexStr;
}

- (NSError*)save:(NSURL*)pathURL{
   [self copyBufferFrom:_cellsBuffer1 to:_tmpCellsBuffer size:_cellsBuffer1.length];
   NSMutableDictionary* dict = [[NSMutableDictionary alloc]init];
   dict[@"max_steps"] = [NSNumber numberWithInt:_worldParams->max_steps];
   dict[@"max_dist"] = [NSNumber numberWithInt:_worldParams->max_dist];
   dict[@"background_mutation_rate"] = [NSNumber numberWithFloat:_worldParams->background_mutation_rate];
   dict[@"fixed_shuffle"] = [NSNumber numberWithBool:_worldParams->fixed_shuffle];
   dict[@"width"] = [NSNumber numberWithInt:WORLD_WIDTH];
   dict[@"height"] = [NSNumber numberWithInt:WORLD_HEIGHT];
   struct Cell* cell = [self getCellX:0 Y:0];
   dict[@"seed"] = [NSNumber numberWithUnsignedLong:cell->randstate];
   //struct Cell* cell = (struct Cell*)_cellsBuffer1.contents;
   NSMutableArray *cells = [[NSMutableArray alloc]init];
   for(int y=0; y<WORLD_HEIGHT; y++) {
      NSMutableArray *row = [[NSMutableArray alloc]init];
      for(int x=0; x<WORLD_WIDTH; x++) {
         [row addObject:[self cellTapeToString:[self getCellX:x Y:y]]];
      }
      [cells addObject:row];
   }
   dict[@"cells"] = cells;
   dict[@"epoch"] = [NSNumber numberWithInt:_epoch];
   NativeJsonSerializer* serializer = [[NativeJsonSerializer alloc] init];
   NSData * data = [serializer serializeObjectToData:dict];
   NSError *error;
   [data writeToURL:pathURL options:0 error:&error];
   return error;
}

- (int)getInt:(NSDictionary *)dict key:(NSString *)key default:(int)value {
   NSNumber *n = [dict objectForKey:key];
   if (n != nil) {
      return [n intValue];
   } else {
      return value;
   }
}

- (int)getFloat:(NSDictionary *)dict key:(NSString *)key default:(float)value {
   NSNumber *n = [dict objectForKey:key];
   if (n != nil) {
      return [n floatValue];
   } else {
      return value;
   }
}

- (long)getLong:(NSDictionary *)dict key:(NSString *)key default:(long)value {
   NSNumber *n = [dict objectForKey:key];
   if (n != nil) {
      return [n longValue];
   } else {
      return value;
   }
}

- (void)hexStringToBytes:(NSString*)s bytes:(uint8_t*)bytes {
   
}


- (void)load:(NSURL*)pathURL {
   NativeJsonSerializer* serializer = [[NativeJsonSerializer alloc] init];
   NSError* error = nil;
   NSData* data = [NSData dataWithContentsOfURL:pathURL options:0 error:&error];
   if (error != nil) {
      NSLog(error);
      return;
   }
   NSDictionary *dict = [serializer deserializeDataToObject:data];
   int width = [self getInt:dict key:@"width" default:0];
   int height = [self getInt:dict key:@"height" default:0];
   
   NSLog(@"width: %d, height: %d", width, height);
   if ((width != WORLD_WIDTH) || (height != WORLD_HEIGHT)) {
      NSLog(@"Can't load as world width or height differs");
      return;
   }
   
   _worldParams->max_steps = [self getInt:dict key:@"max_steps" default:512];
   _worldParams->max_dist = [self getInt:dict key:@"max_dist" default:2];
   _worldParams->background_mutation_rate = [self getFloat:dict key:@"background_mutation_rate" default:0];
   _worldParams->fixed_shuffle = [self getInt:dict key:@"fixed_shuffle" default:0];

   _epoch = [self getInt:dict key:@"epoch" default:0];
   struct Cell *cells = (struct Cell*)_tmpCellsBuffer.contents;
   NSArray *incells = [dict objectForKey:@"cells"];
   for(int j=0; j<height; j++) {
      NSArray *row = incells[j];
      for(int i=0; i<width; i++) {
         NSString *hextape = row[i];
         struct Cell *cell = &cells[j*WORLD_WIDTH+i];
         for(int k=0; k<KSINGLETAPESIZE; k++) {
            NSString *v = [hextape substringWithRange:NSMakeRange(k*2,2)];
            unsigned int w;
            sscanf([v UTF8String], "%x", &w);
            cell->tape[k] = w;
         }
      }
   }
   long seed = [self getLong:dict key:@"seed" default:123456789];
   [self initRandomValues:cells seed:seed];
   [self copyBufferFrom:_tmpCellsBuffer to:_cellsBuffer1 size:_tmpCellsBuffer.length];
}

- (void)draw {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:_cpsDraw];
   [computeEncoder setBuffer:_cellsBuffer1 offset:0 atIndex:0];
   [computeEncoder setBuffer:_worldParamsBuffer offset:0 atIndex:1];
   [computeEncoder setTexture:_texture atIndex:2];
   MTLSize gridSize = MTLSizeMake(WORLD_WIDTH, WORLD_HEIGHT, 1);
   //unsigned long threadGroupSize = _cpsDraw.maxTotalThreadsPerThreadgroup;
   MTLSize threadgroupSize = MTLSizeMake(16,16,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
   
   // Generate mip maps
   id <MTLBlitCommandEncoder> encoder = [commandBuffer blitCommandEncoder];
   [encoder generateMipmapsForTexture: _texture];
   [encoder endEncoding];
}

- (void)step {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:_cpsStep];
   [computeEncoder setBuffer:_cellsBuffer1 offset:0 atIndex:0];
   [computeEncoder setBuffer:_worldParamsBuffer offset:0 atIndex:1];
   [computeEncoder setBuffer:_orderBuffer offset:0 atIndex:2];
   MTLSize gridSize = MTLSizeMake(WORLD_WIDTH, WORLD_HEIGHT, 1);
   MTLSize threadgroupSize = MTLSizeMake(32,32,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
}

- (void)mutate {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:_cpsMutate];
   [computeEncoder setBuffer:_cellsBuffer1 offset:0 atIndex:0];
   [computeEncoder setBuffer:_worldParamsBuffer offset:0 atIndex:1];
   MTLSize gridSize = MTLSizeMake(WORLD_WIDTH, WORLD_HEIGHT, 1);
   MTLSize threadgroupSize = MTLSizeMake(32,32,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
}

- (void)reset:(int)seed {
   _worldParams->seed = seed;
   // Reset random values
   [self initRandomValues:(struct Cell*)_tmpCellsBuffer.contents seed:_worldParams->seed];
   [self copyBufferFrom:_tmpCellsBuffer to:_cellsBuffer1 size:_tmpCellsBuffer.length];
   
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:_cpsRandomize];
   [computeEncoder setBuffer:_cellsBuffer1 offset:0 atIndex:0];
   [computeEncoder setBuffer:_worldParamsBuffer offset:0 atIndex:1];
   MTLSize gridSize = MTLSizeMake(WORLD_WIDTH, WORLD_HEIGHT, 1);
   MTLSize threadgroupSize = MTLSizeMake(32,32,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
   _epoch = 0;
}

- (void)shuffle_order {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:_cpsShuffleOrder];
   [computeEncoder setBuffer:_cellsBuffer1 offset:0 atIndex:0];
   [computeEncoder setBuffer:_worldParamsBuffer offset:0 atIndex:1];
   [computeEncoder setBuffer:_orderBuffer offset:0 atIndex:2];
   MTLSize gridSize = MTLSizeMake(1, 1, 1);
   MTLSize threadgroupSize = MTLSizeMake(1,1,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
}

- (void)unlock {
   id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
   id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
   [computeEncoder setComputePipelineState:_cpsUnlock];
   [computeEncoder setBuffer:_cellsBuffer1 offset:0 atIndex:0];
   [computeEncoder setBuffer:_worldParamsBuffer offset:0 atIndex:1];
   MTLSize gridSize = MTLSizeMake(WORLD_WIDTH, WORLD_HEIGHT, 1);
   MTLSize threadgroupSize = MTLSizeMake(32,32,1);
   [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup: threadgroupSize];
   [computeEncoder endEncoding];
   [commandBuffer commit];
}

@end
