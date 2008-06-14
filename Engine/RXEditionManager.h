//
//	RXEditionManager.h
//	rivenx
//
//	Created by Jean-Francois Roy on 02/02/2008.
//	Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>

#import "RXEdition.h"
#import "RXEditionManagerWindowController.h"


@interface RXEditionManager : NSObject {
	NSMutableDictionary* editions;
	NSMutableArray* editionProxies;
	
	RXEdition* currentEdition;
	
@private
	RXEditionManagerWindowController* _windowController;
	BOOL _tornDown;
	
	NSMutableSet* _validMountPaths;
	NSString* _waitingForThisDisc;
	
	NSString* _localDataStore;
	
	NSMutableDictionary* _editionManagerSettings;
}

+ (RXEditionManager*)sharedEditionManager;

- (void)tearDown;

- (RXEdition*)editionForKey:(NSString*)editionKey;

- (RXEdition*)currentEdition;
- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error;

- (NSString*)mountPathForDisc:(NSString*)disc;
- (NSString*)mountPathForDisc:(NSString*)disc waitingInModalSession:(NSModalSession)session;

- (void)ejectMountPath:(NSString*)mountPath;

- (MHKArchive*)dataArchiveWithFilename:(NSString*)filename stackID:(NSString*)stackID error:(NSError**)error;
- (MHKArchive*)soundArchiveWithFilename:(NSString*)filename stackID:(NSString*)stackID error:(NSError**)error;

@end
