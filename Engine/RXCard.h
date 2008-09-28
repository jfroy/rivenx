//
//	RXCard.h
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/semaphore.h>
#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import <Foundation/Foundation.h>

#import "RXAtomic.h"
#import "RXTiming.h"

#import "RXCardDescriptor.h"

#import "RXHotspot.h"
#import "RXSoundGroup.h"

#import "RXRendering.h"
#import "RXRivenScriptProtocol.h"
#import "RXCardExecutionProtocol.h"

#if defined(LLVM_WATER)
#import "RXWaterAnimationFrame.h"
#endif

struct _rx_card_sfxe {
#if defined(LLVM_WATER)
	NSMutableArray* frames;
#elif defined(GPU_WATER)
	GLsizei nframes;
	GLuint* frames;
	void* frame_storage;
#endif
	NSRect roi;
	double fps;
};

struct _rx_card_sfxe_render_state {
	struct _rx_card_sfxe* sfxe;
	uint32_t current_frame;
	uint64_t frame_timestamp;
};

struct _rx_card_render_state {
	NSMutableArray* pictures;
	NSMutableArray* movies;
	struct _rx_card_sfxe_render_state water_fx;
	BOOL refresh_static;
};


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
	NSTimer* _insideHotspotEventTimer;
	
	// pictures
	GLuint _pictureCount;
	GLuint _pictureVertexArrayBuffer;
	void* _pictureTextureStorage;
	
	GLuint _dynamicPictureCount;
	NSMapTable* _dynamicPictureMap;
	
	// special effects
	uint16_t _sfxeCount;
	struct _rx_card_sfxe* _sfxes;
	
	// movies
	NSMutableArray* _movies;
	uint16_t* _mlstCodes;
	NSMapTable* _codeToMovieMap;
	semaphore_t _movieLoadSemaphore;
	semaphore_t _moviePlaybackSemaphore;
	
	// sounds
	NSMutableArray* _soundGroups;
	RXSoundGroup* _synthesizedSoundGroup;
	
	// rendering
	BOOL _renderStateSwapsEnabled;
	struct _rx_card_render_state _renderState1;
	struct _rx_card_render_state _renderState2;
	
	BOOL _didActivatePLST;
	BOOL _didActivateSLST;
	
	// program execution
	uint32_t _programExecutionDepth;
	uint16_t _lastExecutedProgramOpcode;
	BOOL _queuedAPushTransition;
	
	// external commands
	NSMapTable* _externalCommandLookup;
	
@public
	// this is public ONLY for RXCardState
	
	// render states
	struct _rx_card_render_state* volatile _frontRenderStatePtr;
	struct _rx_card_render_state* _backRenderStatePtr;
	
	// pictures
	GLuint _pictureVAO;
	GLuint* _pictureTextures;
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor;
- (RXCardDescriptor*)descriptor;
- (NSString*)description;

- (NSArray*)activeHotspots;
- (void)mouseEnteredHotspot:(RXHotspot*)hotspot;
- (void)mouseExitedHotspot:(RXHotspot*)hotspot;
- (void)mouseDownInHotspot:(RXHotspot*)hotspot;
- (void)mouseUpInHotspot:(RXHotspot*)hotspot;

@end
