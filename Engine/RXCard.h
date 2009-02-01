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
	
	// scripts
	NSDictionary* _cardEvents;
	
	// hotspots
	NSMutableArray* _hotspots;
	NSMapTable* _hotspotsIDMap;
	void* _blstData;
	void* _hotspotControlRecords;
	
	// pictures
	GLuint _pictureCount;
	GLuint _pictureVertexArrayBuffer;
	GLuint _pictureVAO;
	GLuint* _pictureTextures;
	void* _pictureTextureStorage;
	
	// movies
	NSMutableArray* _movies;
	uint16_t* _mlstCodes;
	
	// sound groups
	NSMutableArray* _soundGroups;
	
	// special effects
	uint16_t _sfxeCount;
	rx_card_sfxe* _sfxes;
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor;

- (RXCardDescriptor*)descriptor;
- (MHKArchive*)archive;

- (NSDictionary*)events;
- (NSArray*)hotspots;
- (NSMapTable*)hotspotsIDMap;

- (NSArray*)movies;
- (uint16_t*)movieCodes;
- (rx_card_sfxe*)sfxes;

- (RXSoundGroup*)createSoundGroupWithSLSTRecord:(const uint16_t*)slstRecord soundCount:(uint16_t)soundCount swapBytes:(BOOL)swapBytes;

@end
