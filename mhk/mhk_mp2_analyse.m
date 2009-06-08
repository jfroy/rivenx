//
//  mhk_mp2_analyse.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 09/04/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ValueCount : NSObject {
@public
    uint32_t value;
    uint32_t count;
}
@end

@implementation ValueCount

- (NSString *)description {
    return [NSString stringWithFormat:@"%@: {value=%u, count=%u}", [super description], value, count];
}

- (BOOL)isEqual:(id)anObject {
    if (anObject == nil) return NO;
    if (![anObject isKindOfClass:[ValueCount class]]) return NO;
    
    return value == ((ValueCount *)anObject)->value;
}

- (unsigned)hash {
    return value;
}

@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    
    if(argc < 2) {
        printf("usage: %s [file 1] [file 2] [...]\n", argv[1]);
        return 1;
    }
    
    NSMutableDictionary *values = [[NSMutableDictionary alloc] initWithCapacity:20];
    NSMutableDictionary *offsets = [[NSMutableDictionary alloc] initWithCapacity:20];
    
    int file_index = 1;
    for(; file_index < argc; file_index++) {
        NSData *file_data = [[NSData alloc] initWithContentsOfMappedFile:[NSString stringWithCString:argv[file_index] encoding:NSUTF8StringEncoding]];
        const uint8_t *file_data_ptr = [file_data bytes] + 44; // WAVE header is 44 bytes when decoder the mp2 sound resources with ffmpeg
        const uint8_t *file_data_ptr_begin = file_data_ptr;
        const uint8_t *file_data_ptr_end = file_data_ptr + [file_data length];
        
        while(file_data_ptr < file_data_ptr_end) {
            // scan until we find not zero
            if (*file_data_ptr != 0x0) {
                // bump the count for the value and offset
                NSNumber *valueKey = [NSNumber numberWithUnsignedChar:*file_data_ptr];
                ValueCount *valueObject = [values objectForKey:valueKey];
                if (!valueObject) {
                    valueObject = [[ValueCount alloc] init];
                    valueObject->value = *file_data_ptr;
                    [values setObject:valueObject forKey:valueKey];
                    [valueObject release];
                }
                
                valueObject->count++;
                
                NSNumber *offsetKey = [NSNumber numberWithUnsignedLong:file_data_ptr - file_data_ptr_begin];
                valueObject = [offsets objectForKey:offsetKey];
                if (!valueObject) {
                    valueObject = [[ValueCount alloc] init];
                    valueObject->value = file_data_ptr - file_data_ptr_begin;
                    [offsets setObject:valueObject forKey:offsetKey];
                    [valueObject release];
                }
                
                valueObject->count++;
                
                break;
            }
            
            file_data_ptr++;
        }
        
        [file_data release];
    }
    
    NSLog(@"Values: %@", values);
    NSLog(@"Offsets: %@", offsets);
    
    [values release];
    [offsets release];

    [p release];
    return 0;
}
