//
//  MHKArchiveQuicktimeAdditions.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 06/23/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "MHKArchive.h"
#import "MHKErrors.h"


@implementation MHKArchive (MHKArchiveQuickTimeAdditions)

- (Movie)movieWithID:(uint16_t)movieID error:(NSError **)errorPtr {
    OSStatus err = noErr;
    
    // get the movie resource descriptor
    NSDictionary *descriptor = [self resourceDescriptorWithResourceType:@"tMOV" ID:movieID];
    if (!descriptor)
        ReturnNULLWithError(MHKErrorDomain, errResourceNotFound, nil, errorPtr);
        
    // store the movie offset in a variable
    SInt64 qt_offset = [[descriptor objectForKey:@"Offset"] longLongValue];
    
    // prepare a property structure
    Boolean active = true;
    Boolean dontAskUnresolved = true;
    Boolean dontInteract = true;
    Boolean async = true;
    Boolean idleImport = true;
//  Boolean optimizations = YES;
    QTVisualContextRef visualContext = NULL;
    QTNewMoviePropertyElement newMovieProperties[] = {
        {kQTPropertyClass_DataLocation, kQTDataLocationPropertyID_DataFork, sizeof(forkRef), &forkRef, 0},
        {kQTPropertyClass_MovieResourceLocator, kQTMovieResourceLocatorPropertyID_FileOffset, sizeof(qt_offset), &qt_offset, 0},
        {kQTPropertyClass_Context, kQTContextPropertyID_VisualContext, sizeof(QTVisualContextRef), &visualContext, 0},
        {kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_Active, sizeof(Boolean), &active, 0}, 
        {kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_DontInteractWithUser, sizeof(Boolean), &dontInteract, 0}, 
        {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_DontAskUnresolvedDataRefs, sizeof(Boolean), &dontAskUnresolved, 0},
        {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_AsyncOK, sizeof(Boolean), &async, 0},
        {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_IdleImportOK, sizeof(Boolean), &idleImport, 0},
//      {kQTPropertyClass_MovieInstantiation, kQTMovieInstantiationPropertyID_AllowMediaOptimization, sizeof(Boolean), &optimizations, 0}, LEOPARD ONLY
    };
    
    // make the movie
    Movie aMovie = NULL;
    err = NewMovieFromProperties(sizeof(newMovieProperties) / sizeof(newMovieProperties[0]), newMovieProperties, 0, NULL, &aMovie);
    if (err != noErr)
        ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr);
    return aMovie;
}

@end
