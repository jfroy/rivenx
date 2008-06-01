//
//	RXSoundGroup.h
//	rivenx
//
//	Created by Jean-Francois Roy on 11/03/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <MHKKit/MHKAudioDecompression.h>

#import "RXStack.h"
#import "RXCardAudioSource.h"


@interface RXSound : NSObject {
@public
	RXStack* parent;
	uint16_t ID;
	
	float gain;
	float pan;
	
	// RXTiming timestamp
	uint64_t rampStartTimestamp;
	
	// flags below are mutually exclusive
	BOOL fadeInTimestampValid;
	BOOL detachTimestampValid;
	
	RX::CardAudioSource* source;
}

- (id <MHKAudioDecompression>)audioDecompressor;

@end

@interface RXDataSound : RXSound {}
@end

@interface RXSoundGroup : NSObject {
	BOOL _fadeOutActiveGroupBeforeActivating;
	BOOL _fadeInOnActivation;
	BOOL _loop;
	float _gain;
	
	NSMutableSet* _sounds;
}

- (void)addSoundWithStack:(RXStack*)parent ID:(uint16_t)ID gain:(float)gain pan:(float)pan;

@end
