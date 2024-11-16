//
//  NativeJSONSerializer.m
//  PeaSoup
//
//  Created by Adrian Skilling on 01/06/2024.
//

#import <Foundation/Foundation.h>

#import "NativeJSONSerializer.h"


@implementation NativeJsonSerializer

- (id)deserializeStringToObject:(NSString *)string
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    id result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    if (!result) {
        NSLog(@"xxx: %@", error.description);
    }

    return result;
}

- (id)deserializeDataToObject:(NSData *)data
{
    NSError *error = nil;
    id result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    if (!result) {
        NSLog(@"yyy: %@", error.description);
    }
    return result;
}

- (NSString *)serializeObjectToString:(id)data
{
    NSError *error;
    NSData *result = [NSJSONSerialization dataWithJSONObject:data options:NSJSONReadingAllowFragments|NSJSONWritingPrettyPrinted error:&error];
    if (!result) {
        NSLog(@"zzz: %@", error.description);
    }
    return [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
}

- (NSData *)serializeObjectToData:(id)data
{
    NSError *error;
    NSData *result = [NSJSONSerialization dataWithJSONObject:data options:NSJSONReadingAllowFragments|NSJSONWritingPrettyPrinted error:&error];
    if (!result) {
        NSLog(@"000: %@", error.description);
    }
    return result;
}

@end
