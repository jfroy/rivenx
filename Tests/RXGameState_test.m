//
//  RXGameState_test.m
//  rivenx
//
//  Created by Jean-Francois Roy on 14/06/08.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXGameState_test.h"

#import "BZFSUtilities.h"

#import "RXEditionManager.h"


@implementation RXGameState_test

- (void)setUp {
	// tickle the world; including RXWorld.h brings in a world of hurt, so do this dynamically
	[NSClassFromString(@"RXWorld") performSelector:@selector(sharedWorld)];
	
	// hopefully we have at least one edition object...
	RXEdition* someEdition = [[[[RXEditionManager sharedEditionManager] valueForKey:@"editions"] allValues] objectAtIndex:0];
	gameState = [[RXGameState alloc] initWithEdition:someEdition];
}

- (void)tearDown {
	[gameState release];
}

- (void)testSerializingWithNullActiveCard {
	[gameState setUnsignedShort:10 forKey:@"durr"];
	
	// get a random destination URL and serialize to it
	NSURL* tempFileURL;
	NSFileHandle* tempFile = BZFSCreateTemporaryFileInDirectory(nil, nil, &tempFileURL, NULL);
	STAssertNotNil(tempFile, @"tempFile should not be nil");
	
	// close it and delete it now since we're just interested in the location
	[tempFile closeFile];
	BZFSRemoveItemAtURL(tempFileURL, NULL);
	STAssertFalse(BZFSFileURLExists(tempFileURL), @"tempFile should not exists after deleting the dummy temp file");
	
	// serialize the game state
	BOOL success = [gameState writeToURL:tempFileURL error:NULL];
	STAssertTrue(success, @"success should be YES");
	STAssertTrue(BZFSFileURLExists(tempFileURL), @"tempFile should exists after serializing");
	
	// let's unserialize
	RXGameState* steamedState = [RXGameState gameStateWithURL:tempFileURL error:NULL];
	STAssertNotNil(steamedState, @"steamedState should not be nil");
	
	// check if got frozen and unfrozen properly
	STAssertTrue([steamedState isKeySet:@"durr"], @"steamedState should have key \"durr\" set");
	STAssertEquals((uint16_t)10, [steamedState unsignedShortForKey:@"durr"], @"steamedState should have a value of 10 for ke\"durr\"");
}

@end
