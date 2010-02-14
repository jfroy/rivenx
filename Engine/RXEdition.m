//
//  RXEdition.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "Engine/RXEdition.h"
#import "Engine/RXWorld.h"
#import "Engine/RXEditionProxy.h"

#import "Utilities/BZFSUtilities.h"


@implementation RXEdition

+ (BOOL)_saneDescriptor:(NSDictionary*)descriptor {
    // check that all the required root keys are present
    if (![descriptor objectForKey:@"Edition"])
        return NO;
    if (![descriptor objectForKey:@"Stacks"])
        return NO;
    if (![descriptor objectForKey:@"Journals"])
        return NO;
    
    // check that the Edition dictionary has all the required keys
    id edition = [descriptor objectForKey:@"Edition"];
    if (![edition isKindOfClass:[NSDictionary class]])
        return NO;
    if (![edition objectForKey:@"Key"])
        return NO;
    if (![edition objectForKey:@"Discs"])
        return NO;
    if (![edition objectForKey:@"Install Directives"])
        return NO;
    if (![edition objectForKey:@"Directories"])
        return NO;
    
    // must have at least one disc
    id discs = [edition objectForKey:@"Discs"];
    if (![discs isKindOfClass:[NSArray class]])
        return NO;
    if ([discs count] == 0)
        return NO;
    
    // Directories must be a dictionary and contain at least a Data, Sound and All key
    id directories = [edition objectForKey:@"Directories"];
    if (![directories isKindOfClass:[NSDictionary class]])
        return NO;
    if (![directories objectForKey:@"Data"])
        return NO;
    if (![directories objectForKey:@"Sound"])
        return NO;
    if (![directories objectForKey:@"All"])
        return NO;
    
    // Journals must be a dictionary and contain at least a "Card ID Map" key
    id journals = [descriptor objectForKey:@"Journals"];
    if (![journals isKindOfClass:[NSDictionary class]])
        return NO;
    if (![journals objectForKey:@"Card ID Map"])
        return NO;
    
    // good enough
    return YES;
}

- (void)_determineMustInstall {
    _mustInstall = NO;
    
    NSArray* directives = [[_descriptor objectForKey:@"Edition"] objectForKey:@"Install Directives"];
    NSEnumerator* e = [directives objectEnumerator];
    NSDictionary* directive;
    while ((directive = [e nextObject])) {
        NSNumber* required = [directive objectForKey:@"Required"];
        if (required && [required boolValue]) {
            _mustInstall = YES;
            return;
        }
    }
}

- (void)_loadUserData {
    // user data is stored in a plist inside the edition user base
    NSError* error;
    NSString* userDataPath = [userBase stringByAppendingPathComponent:@"User Data.plist"];
    if (BZFSFileExists(userDataPath)) {
        NSData* userRawData = [NSData dataWithContentsOfFile:userDataPath options:0 error:&error];
        // FIXME: be nicer than blowing up, say by offering to create a new user data file and moving the old one aside
        if (!userRawData)
            @throw [NSException exceptionWithName:@"RXCorruptedEditionUserDataException"
                                           reason:[NSString stringWithFormat:@"Your data for the %@ is corrupted.", name]
                                         userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
        
        _userData = [[NSPropertyListSerialization propertyListFromData:userRawData
                                                      mutabilityOption:NSPropertyListMutableContainers
                                                                format:NULL
                                                      errorDescription:NULL] retain];
    } else
        // create a new user data directionary
        _userData = [NSMutableDictionary new];
}

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithDescriptor:(NSDictionary*)descriptor {
    self = [super init];
    if (!self)
        return nil;
    
    if (!descriptor || ![[self class] _saneDescriptor:descriptor]) {
        [self release];
        return nil;
    }
    
    NSError* error = nil;
    BOOL success;
    
    // keep the descriptor around
    _descriptor = [descriptor retain];
    
    // load edition information
    NSDictionary* edition = [_descriptor objectForKey:@"Edition"];
    key = [edition objectForKey:@"Key"];
    discs = [edition objectForKey:@"Discs"];
    name = [NSLocalizedStringFromTable(key, @"Editions", nil) retain];
    directories = [edition objectForKey:@"Directories"];
    installDirectives = [edition objectForKey:@"Install Directives"];
    
    // the journal card ID map
    journalCardIDMap = [[_descriptor objectForKey:@"Journals"] objectForKey:@"Card ID Map"];
    
    // patch archives directory
    patchArchives = [_descriptor objectForKey:@"Patch Archives"];
    
    // create the support directory for the edition
    // FIXME: we should offer system-wide editions as well
    userBase = [[[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:key] retain];
    if (!BZFSDirectoryExists(userBase)) {
        success = BZFSCreateDirectory(userBase, &error);
        if (!success)
            @throw [NSException exceptionWithName:@"RXFilesystemException"
                                           reason:[NSString stringWithFormat:@"Riven X was unable to create a support folder for the %@.", name]
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    // sub-directory in the edition user base for data files
    // FIXME: data files should ideally not be installed per-user...
    userDataBase = [[userBase stringByAppendingPathComponent:@"Data"] retain];
    if (!BZFSDirectoryExists(userDataBase)) {
        success = BZFSCreateDirectory(userDataBase, &error);
        if (!success)
            @throw [NSException exceptionWithName:@"RXFilesystemException"
                                           reason:[NSString stringWithFormat:@"Riven X was unable to create the Data folder for the %@.", name]
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    stackDescriptors = [_descriptor objectForKey:@"Stacks"];
    
    // determine if this edtion must be installed to play
    [self _determineMustInstall];
    
    // get the user's data for this edition
    [self _loadUserData];
    
    openArchives = [NSMutableArray new];
    
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelMessage, @"loaded (base=%@, installed=%d, must install=%d",
        userDataBase, [self isInstalled], [self mustBeInstalled]);
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat: @"%@ {name=%@}", [super description], name];
}

- (void)dealloc {
    // before dying, write our user data
    // FIXME: handle errors
    [self writeUserData:NULL];
    
    [_descriptor release];
    [_userData release];
    
    [name release];
    
    [userBase release];
    [userDataBase release];
    
    [openArchives release];
    
    [super dealloc];
}

- (NSUInteger)hash {
    return [key hash];
}

- (BOOL)isEqual:(id)object {
    if ([self class] != [object class])
        return NO;
    return [key isEqualToString:[(RXEdition*)object valueForKey:@"key"]];
}

- (RXEditionProxy*)proxy {
    return [[[RXEditionProxy alloc] initWithEdition:self] autorelease];
}

- (NSMutableDictionary*)userData {
    return [[_userData retain] autorelease];
}

- (BOOL)writeUserData:(NSError**)error {
    NSString* userDataPath = [userBase stringByAppendingPathComponent:@"User Data.plist"];
    NSData* userRawData = [NSPropertyListSerialization dataFromPropertyList:_userData format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL];
    if (!userRawData)
        ReturnValueWithError(NO, RXErrorDomain, 0, nil, error);
    return [userRawData writeToFile:userDataPath options:NSAtomicWrite error:error];
}

- (BOOL)mustBeInstalled {
    return _mustInstall;
}

- (BOOL)isInstalled {
    NSNumber* installed = [_userData objectForKey:@"Installed"];
    if (!installed)
        return NO;
    return [installed boolValue];
}

- (BOOL)canBecomeCurrent {
    return !([self mustBeInstalled] && ![self isInstalled]);
}

- (NSString*)searchForExtrasArchiveInMountPath:(NSString*)path {    
    NSArray* content = BZFSContentsOfDirectory(path, NULL);
    NSEnumerator* content_enum = [content objectEnumerator];
    NSString* item;
    while ((item = [content_enum nextObject])) {
        NSString* item_path = [path stringByAppendingPathComponent:item];
        
        NSString* extras_path = BZFSSearchDirectoryForItem(item_path, @"Extras.MHK", YES, NULL);
        if (extras_path)
            return extras_path;
    }
    
    return nil;
}

- (BOOL)isValidMountPath:(NSString*)path {
    NSString* path_disc = [[path lastPathComponent] lowercaseString];
    
    NSEnumerator* enumerator = [discs objectEnumerator];
    NSString* disc;
    while ((disc = [enumerator nextObject])) {
        if ([path_disc caseInsensitiveCompare:disc] == NSOrderedSame)
            break;
    }
    if (!disc)
        return NO;
    
    return (BZFSSearchDirectoryForItem(path, @"Data", YES, NULL)) ? YES : NO;
}

@end
