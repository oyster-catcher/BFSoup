//
//  NativeJSONSerializer.h
//  PeaSoup
//
//  Created by Adrian Skilling on 01/06/2024.
//

#ifndef NativeJSONSerializer_h
#define NativeJSONSerializer_h

#import <Foundation/Foundation.h>

@protocol ObjectSerializer <NSObject>

- (id)deserializeStringToObject:(NSString *)string;
- (id)deserializeDataToObject:(NSData *)data;
- (NSString *)serializeObjectToString:(id)object;
- (NSData *)serializeObjectToData:(id)object;

@end

@interface NativeJsonSerializer : NSObject<ObjectSerializer>

@end

#endif /* NativeJSONSerializer_h */
