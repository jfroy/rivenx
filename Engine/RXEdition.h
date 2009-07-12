//
//  RXEdition.h
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>

@class RXEditionProxy;


@interface RXEdition : NSObject {
    // should not be modified through KVC
    NSString* key;
    NSString* name;
    
    NSArray* discs;
    NSArray* installDirectives;
    NSDictionary* directories;
    
    NSDictionary* stackSwitchTables;
    NSDictionary* journalCardIDMap;
    NSDictionary* cardLUT;
    NSDictionary* bitmapLUT;
    NSDictionary* soundLUT;
    
    NSDictionary* patchArchives;
    
    NSString* userBase;
    NSString* userDataBase;
    
    NSArray* stackDescriptors;
    
    NSMutableArray* openArchives;
    
@private
    NSMutableDictionary* _userData;
    NSDictionary* _descriptor;
    BOOL _mustInstall;
}

- (id)initWithDescriptor:(NSDictionary*)descriptor;

- (RXEditionProxy*)proxy;

- (NSMutableDictionary*)userData;
- (BOOL)writeUserData:(NSError**)error;

- (BOOL)mustBeInstalled;
- (BOOL)isInstalled;

- (BOOL)canBecomeCurrent;

- (BOOL)isValidMountPath:(NSString*)path;

@end
