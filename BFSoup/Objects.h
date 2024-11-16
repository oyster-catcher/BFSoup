//
//  Objects.h
//  PeaSoup
//
//  Created by Adrian Skilling on 19/04/2024.
//

#ifndef Objects_h
#define Objects_h

#import <MetalKit/MetalKit.h>

@interface Objects : NSObject
- (id)initWithDevice:(id<MTLDevice>)device;

- (void)quadWithVertexBuffer: (id<MTLBuffer>*)vertexBuffer vertexOffset:(int*)vertexOffset
               indicesBuffer:(id<MTLBuffer>*)indicesBuffer numIndices:(int*)numIndices indicesOffset:(int*)indicesOffset;

@end

#endif /* Objects_h */
