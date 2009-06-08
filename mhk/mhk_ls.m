//
//  mhk_ls.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 25/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>


int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    
    if(argc < 2) {
        printf("usage: %s archive\n", argv[1]);
        return 1;
    }
    
    NSError *error = nil;
    MHKArchive *archive = [[MHKArchive alloc] initWithPath:[NSString stringWithUTF8String:argv[1]] error:&error];
    if(!archive) {
        printf("FAILED TO OPEN THE PROVIDED FILE AS AN MHK ARCHIVE: %s\n\n", [[error description] UTF8String]);
        exit(1);
    }
    
    NSArray *types = [[archive resourceTypes] sortedArrayUsingSelector:@selector(compare:)];
    printf("total: %u resource types\n\n", [types count]);
    
    NSEnumerator *typesEnum = [types objectEnumerator];
    id aType = nil;
    while(aType = [typesEnum nextObject]) {
        NSArray *resources = [archive valueForKey:aType];
        printf("%s: %u resources\n", [aType UTF8String], [resources count]);
    }
    
    printf("\n");
    
    [archive release];
    [p release];
    return 0;
}
