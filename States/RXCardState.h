//
//	RXCardState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 24/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <pthread.h>

#import <mach/semaphore.h>
#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import "RXRenderState.h"
#import "RXAtomic.h"

#import "RXCard.h"
#import "RXStack.h"
#import "RXTransition.h"

struct rx_sfxe_render_state {
	rx_card_sfxe* sfxe;
	id owner;
	uint32_t current_frame;
	uint64_t frame_timestamp;
};

struct rx_card_state_render_state {
	RXCard* card;
	BOOL new_card;
	
	BOOL refresh_static;
	NSMutableArray* pictures;
	NSMutableArray* volatile movies;
	struct rx_sfxe_render_state water_fx;
	
	RXTransition* transition;
};

struct rx_transition_program {
	GLuint program;
	GLint t_uniform;
	GLint margin_uniform;
	GLint card_size_uniform;
};

@interface RXCardState : RXRenderState <RXCardRendererProtocol> {
	// render state
	void* _render_states_buffer;
	struct rx_card_state_render_state* volatile _front_render_state;
	struct rx_card_state_render_state* volatile _back_render_state;
	OSSpinLock _renderLock;
	OSSpinLock _state_swap_lock;
	
	// mouse and hotspots handling
	NSRect _mouseVector;
	OSSpinLock _mouseVectorLock;
	RXHotspot* _currentHotspot;
	RXHotspot* _mouse_down_hotspot;
	int32_t volatile _hotspot_handling_disable_counter;
	NSCursor* _hidden_cursor;
	int32_t volatile _cursor_hide_counter;
	
	// sounds
	NSMutableSet* _activeSounds;
	NSMutableSet* _activeDataSounds;
	
	CFMutableArrayRef volatile _activeSources;
	CFMutableArrayRef _sourcesToDelete;
	
	NSTimer* _activeSourceUpdateTimer;
	OSSpinLock _audioTaskThreadStatusLock;
	semaphore_t _audioTaskThreadExitSemaphore;
	
	BOOL _forceFadeInOnNextSoundGroup;
	
	// transitions
	semaphore_t _transitionSemaphore;
	NSMutableArray* _transitionQueue;
	
	struct rx_transition_program _dissolve;
	struct rx_transition_program _push[4];
	struct rx_transition_program _slide_out[4];
	struct rx_transition_program _slide_in[4];
	struct rx_transition_program _swipe[4];
	
	// rendering
	GLuint _cardRenderVAO;
	GLuint _cardRenderVBO;
	
	GLuint _cardCompositeVAO;
	GLuint _cardCompositeVBO;
	
	GLuint _fbos[2];
	GLuint _textures[3];
	
	GLuint _waterProgram;
	GLuint _single_rect_texture_program;
	
	GLuint _hotspotDebugRenderVAO;
	GLuint _hotspotDebugRenderVBO;
	GLint* _hotspotDebugRenderFirstElementArray;
	GLint* _hotspotDebugRenderElementCountArray;
	
	// inventory
	CGRect _inventoryRegions[3];
	NSRect _inventoryHotspotRegions[3];
	uint16_t _inventoryDestinationCardID[3];
	GLuint _inventoryTextures[3];
	GLuint _inventoryTextureBuffer;
	
	uint32_t _inventoryItemCount;
	float _inventoryAlphaFactor;
}

- (void)setActiveCardWithStack:(NSString*)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
- (void)clearActiveCardWaitingUntilDone:(BOOL)wait;

@end
