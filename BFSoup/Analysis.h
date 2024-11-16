//
//  Analysis.h
//  PeaSoup
//
//  Created by Adrian Skilling on 17/06/2024.
//

#ifndef Analysis_h
#define Analysis_h

#import "ShaderDefinitions.h"
#import "World.h"

@interface Analysis : NSObject

+ (void)runGui:(WorldParams*)worldParams world:(World*)world open:(bool*)open;

@end

#endif /* Analysis_h */
