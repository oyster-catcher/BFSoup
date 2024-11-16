//
//  Objects.m
//  PeaSoup
//
//  Created by Adrian Skilling on 19/04/2024.
//

#import <Foundation/Foundation.h>

#import <MetalKit/MetalKit.h>

#import "ShaderDefinitions.h"
#import "Objects.h"

@implementation Objects
{
   int numRingVertices;
   struct Vertex *vertices;
   id<MTLBuffer> vertexBuffer;
   uint32 *indices;
   id<MTLBuffer> indicesBuffer;
   // quad
   int numQuadIndices;
   int quadIndexOffset;
   int quadVertexOffset;
}

- (id)initWithDevice:(id<MTLDevice>)device {
   self = [super init];
   int numVertices = 300; // max size
   int numIndices = 300; // max size
   numQuadIndices = 0;
   quadIndexOffset = 0;
   quadVertexOffset = 0;
   
   vertices = calloc(numVertices, sizeof(struct Vertex));
   NSAssert(vertices!=nil, @"Failed to allocate memory for vertices");
   
   // Create ring
   indices = calloc(numIndices, sizeof(uint32));
   NSAssert(indices!=nil, @"Failed to allocate memory for indices");
   int iid = 0;
   int vid = 0;

   // quad
   vertices[vid].pos.x = -1;
   vertices[vid].pos.y = 1;
   vertices[vid+1].pos.x = 1;
   vertices[vid+1].pos.y = 1;
   vertices[vid+2].pos.x = -1;
   vertices[vid+2].pos.y = -1;
   vertices[vid+3].pos.x = 1;
   vertices[vid+3].pos.y = -1;
   
   quadIndexOffset = iid;
   numQuadIndices = 4;
   indices[iid] = vid;
   indices[iid+1] = vid+1;
   indices[iid+2] = vid+2;
   indices[iid+3] = vid+3;
   
   vid = vid + 4;
   iid = iid + 4;
   

   if (iid > numVertices-1) {
      NSLog(@"ERROR! Created %d vertices but only space for %d", iid+1, numVertices);
   }

   indicesBuffer = [device newBufferWithBytes:indices length:(iid+1)*sizeof(uint32) options:MTLResourceStorageModeShared];
   vertexBuffer = [device newBufferWithBytes:vertices length:(vid+1)*sizeof(struct Vertex) options:MTLResourceStorageModeShared];
   return self;
}

- (void)quadWithVertexBuffer: (id<MTLBuffer>*)vertexBuffer vertexOffset:(int*)vertexOffset
indicesBuffer:(id<MTLBuffer>*)indicesBuffer numIndices:(int*)numIndices indicesOffset:(int*)indicesOffset {
   *vertexBuffer = self->vertexBuffer;
   *vertexOffset = quadVertexOffset * sizeof(struct Vertex);
   *indicesBuffer = self->indicesBuffer;
   *numIndices = numQuadIndices;
   *indicesOffset = quadIndexOffset*4;
}

@end
