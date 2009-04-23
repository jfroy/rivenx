//
//	RXEditionManager.h
//	rivenx
//
//	Created by Jean-Francois Roy on 02/02/2008.
//	Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>

#import "Engine/RXEdition.h"
#import "Engine/RXEditionManagerWindowController.h"
#import "Engine/RXCardDescriptor.h"
#import "Engine/RXStack.h"


@interface RXEditionManager : NSObject {
	NSMutableDictionary* editions;
	NSMutableArray* editionProxies;
	NSString* _patches_directory;
	
	RXEdition* currentEdition;
	NSMutableDictionary* activeStacks;
	
	RXEditionManagerWindowController* _windowController;
	BOOL _tornDown;
	
	NSMutableArray* _validMountPaths;
	NSString* _waitingForThisDisc;
	
	NSString* _localDataStore;
	
	NSMutableDictionary* _editionManagerSettings;
}

+ (RXEditionManager*)sharedEditionManager;

- (void)tearDown;

- (void)showEditionManagerWindow;

- (RXEdition*)editionForKey:(NSString*)editionKey;

- (RXEdition*)currentEdition;
- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error;

- (RXEdition*)defaultEdition;
- (void)setDefaultEdition:(RXEdition*)edition;
- (void)resetDefaultEdition;

- (NSString*)mountPathForDisc:(NSString*)disc;
- (NSString*)mountPathForDisc:(NSString*)disc waitingInModalSession:(NSModalSession)session;

- (void)ejectMountPath:(NSString*)mountPath;

- (RXSimpleCardDescriptor*)lookupCardWithKey:(NSString*)lookup_key;
- (uint16_t)lookupBitmapWithKey:(NSString*)lookup_key;
- (uint16_t)lookupSoundWithKey:(NSString*)lookup_key;

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stackKey error:(NSError**)error;

- (MHKArchive*)dataArchiveWithFilename:(NSString*)filename stackKey:(NSString*)stackKey error:(NSError**)error;
- (MHKArchive*)soundArchiveWithFilename:(NSString*)filename stackKey:(NSString*)stackKey error:(NSError**)error;

- (RXStack*)activeStackWithKey:(NSString*)stackKey;
- (RXStack*)loadStackWithKey:(NSString*)stackKey;

@end
