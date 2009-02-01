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
#import "RXHotspot.h"
#import "RXCardProtocols.h"

#import "Rendering/RXRendering.h"


@interface RXCard : NSObject {
	RXCardDescriptor* _descriptor;
	MHKArchive* _archive;
	
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
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor;
- (RXCardDescriptor*)descriptor;

@end
