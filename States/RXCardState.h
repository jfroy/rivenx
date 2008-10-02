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

struct _rx_card_state_render_state {
	RXCard* card;
	BOOL newCard;
	RXTransition* transition;
};

struct _rx_transition_program {
	GLuint program;
	GLint t_uniform;
	GLint margin_uniform;
	GLint card_size_uniform;
};

@interface RXCardState : RXRenderState <RXRivenScriptProtocol> {
	// render state
	struct _rx_card_state_render_state* volatile _front_render_state;
	struct _rx_card_state_render_state* _back_render_state;
	OSSpinLock _renderLock;
	
	// event handling
	int32_t _ignoreUIEventsCounter;
	int32_t _scriptExecutionBlockedCounter;
	NSCursor* _cursorBackup;
	
	// hotspot state handling
	BOOL _resetHotspotState;
	RXHotspot* _currentHotspot;
	
	// sounds
	NSMutableSet* _activeSounds;
	NSMutableSet* _activeDataSounds;
	
	CFMutableArrayRef volatile _activeSources;
	CFMutableArrayRef _sourcesToDelete;
	
	NSTimer* _activeSourceUpdateTimer;
	OSSpinLock _audioTaskThreadStatusLock;
	semaphore_t _audioTaskThreadExitSemaphore;
	
	// transitions
	semaphore_t _transitionSemaphore;
	NSMutableArray* _transitionQueue;
	
	struct _rx_transition_program _dissolve;
	struct _rx_transition_program _push[4];
	struct _rx_transition_program _slide_out[4];
	struct _rx_transition_program _slide_in[4];
	struct _rx_transition_program _swipe[4];
	
	// rendering
	GLuint _cardRenderVAO;
	GLuint _cardRenderVBO;
	
	GLuint _cardCompositeVAO;
	GLuint _cardCompositeVBO;
	
	GLuint _fbos[2];
	GLuint _textures[3];
	
	GLuint _waterProgram;
	GLuint _cardProgram;
	
	GLuint _hotspotDebugRenderVAO;
	
	// journals bar
	GLuint _journalTextures[3];
	GLuint _journalTextureBuffer;
}

- (void)setActiveCardWithStack:(NSString *)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
- (void)clearActiveCardWaitingUntilDone:(BOOL)wait;

@end
