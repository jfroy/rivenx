//
//	RXCard.h
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>

#import <Foundation/Foundation.h>

#import "Base/RXAtomic.h"
#import "Base/RXTiming.h"

#import "RXCardDescriptor.h"
#import "RXCardExecutionProtocol.h"
#import "RXHotspot.h"
#import "RXRivenScriptProtocol.h"

#import "Rendering/RXRendering.h"
#import "Rendering/Audio/RXSoundGroup.h"


@interface RXCard : NSObject <RXCardExecutionProtocol> {
	RXCardDescriptor* _descriptor;
	MHKArchive* _archive;
	
	id <RXRivenScriptProtocol> _scriptHandler;
	
	NSDictionary* _cardEvents;
	BOOL _disableScriptLogging;
	
	// hotspots
	NSMutableArray* _hotspots;
	NSMapTable* _hotspotsIDMap;
	void* _blstData;
	void* _hotspotControlRecords;
	NSMutableArray* _activeHotspots;
	OSSpinLock _activeHotspotsLock;
	
	// pictures
	GLuint _pictureCount;
	GLuint _pictureVertexArrayBuffer;
	GLuint _pictureVAO;
	GLuint* _pictureTextures;
	void* _pictureTextureStorage;
	NSMapTable* _dynamicPictureMap;
	
	// special effects
	uint16_t _sfxeCount;
	rx_card_sfxe* _sfxes;
	
	// movies
	NSMutableArray* _movies;
	uint16_t* _mlstCodes;
	semaphore_t _movieLoadSemaphore;
	semaphore_t _moviePlaybackSemaphore;
	
	// sounds
	NSMutableArray* _soundGroups;
	RXSoundGroup* _synthesizedSoundGroup;
	
	// rendering
	BOOL _renderStateSwapsEnabled;
	
	BOOL _didActivatePLST;
	BOOL _didActivateSLST;
	
	// program execution
	uint32_t _programExecutionDepth;
	uint16_t _lastExecutedProgramOpcode;
	BOOL _queuedAPushTransition;
	BOOL _did_hide_mouse;
	
	// external commands
	NSMapTable* _externalCommandLookup;
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor;

- (RXCardDescriptor*)descriptor;

@end
