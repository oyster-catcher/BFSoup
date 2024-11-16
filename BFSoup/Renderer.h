//
//  Renderer.h
//  PeaSoup
//
//  Created by Adrian Skilling on 18/04/2024.
//

#ifndef Renderer_h
#define Renderer_h

#import <MetalKit/MetalKit.h>

//#import "World.h"

// The platform-independent renderer class. Implements the MTKViewDelegate protocol, which
//   allows it to accept per-frame update and drawable resize callbacks.
@interface Renderer : NSObject <MTKViewDelegate>

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view size:(CGSize)size;
/*
- (void)swipe:(float)deltaY x:(float)x y:(float)y;
- (void)runGui:(id<MTLRenderCommandEncoder>)renderEncoder
renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor;
*/
- (void)swipe:(float)deltaY x:(float)x y:(float)y;

- (void)runGui:(id<MTLRenderCommandEncoder>)renderEncoder
renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor;

@end

#endif /* Renderer_h */
