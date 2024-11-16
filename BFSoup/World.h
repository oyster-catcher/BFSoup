//
//  World.h
//  PlantSoup
//
//  Created by Adrian Skilling on 08/07/2024.
//

#ifndef World_h
#define World_h

#import "ShaderDefinitions.h"
#import <Metal/Metal.h>

@interface World : NSObject

- (id)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library worldParamsBuffer:(id<MTLBuffer>)worldParamsBuffer;

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
         renderPipelineState:(id<MTLRenderPipelineState>)renderPipelineState
                        centX:(float)centX centY:(float)centY
                       scaleX:(float)scaleX scaleY:(float)scaleY;

- (void)setCellX:(int)x Y:(int)y program:(int)program;

- (void)compute:(int)speed;

- (void)reset:(int)seed;

//- (NSMutableDictionary*)cellToDict:(struct Cell*)cell;

- (NSError*)save:(NSURL*)pathURL;

- (void)load:(NSURL*)pathURL;

- (struct Cell*)getCellX:(int)x Y:(int)y;

- (int)epoch;

- (void)syncGpuCells;

@end

#endif /* World_h */
