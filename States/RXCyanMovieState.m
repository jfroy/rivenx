//
//	RXCyanMovieState.m
//	rivenx
//
//	Created by Jean-Francois Roy on 11/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXCyanMovieState.h"
#import "RXWorldProtocol.h"


@implementation RXCyanMovieState

static rx_render_dispatch_t _movie_render_dispatch;

static rx_render_dispatch_t _clear_and_render_dispatch;
static rx_render_dispatch_t _render_dispatch;
static rx_render_dispatch_t _clear_dispatch;

+ (void)initialize {
	_movie_render_dispatch = RXGetRenderImplementation([RXMovie class], RXRenderingRenderSelector);
	
	_clear_and_render_dispatch = RXGetRenderImplementation([self class], @selector(_clearAndRender:inContext:));
	_render_dispatch = RXGetRenderImplementation([self class], @selector(_render:inContext:));
	_clear_dispatch = RXGetRenderImplementation([self class], @selector(_clear:inContext:));
}

- (id)init {
	self = [super init];
	if(!self) return self;
	
	id <RXWorldViewProtocol> view = RXGetWorldView();
	
	// allocate the Cyan movie
	_cyanMovie = [[RXMovie alloc] initWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Cyan Worlds" ofType:@"mp4"]]];
	[_cyanMovie setWorkingColorSpace:[view workingColorSpace]];
	[_cyanMovie setOutputColorSpace:[view displayColorSpace]];
	[_cyanMovie setExpectedReadAheadFromDisplayLink:[view displayLink]];
	
	// we need to know when the movie ends
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_cyanMovieIsDone:) name:QTMovieDidEndNotification object:[_cyanMovie movie]];
	
	// compute where to render the cyan logo
	CGRect cyanMovieRect;
	CGSize currentSize = [_cyanMovie currentSize];
	float aspectRatio = currentSize.width / currentSize.height;
	rx_size_t glSize = RXGetGLViewportSize();
	
	if (aspectRatio >= 1.0F) {
		cyanMovieRect.origin.x = 0.0F;
		cyanMovieRect.size.width = glSize.width;
		cyanMovieRect.size.height = glSize.width / aspectRatio;
		cyanMovieRect.origin.y = (glSize.height / 2.0F) - (cyanMovieRect.size.height / 2.0F);
	} else {
		cyanMovieRect.origin.y = 0.0F;
		cyanMovieRect.size.height = glSize.height;
		cyanMovieRect.size.width = glSize.height * aspectRatio;
		cyanMovieRect.origin.x = (glSize.width / 2.0F) - (cyanMovieRect.size.width / 2.0F);
	}
	[self setRenderRect:cyanMovieRect];
	
	return self;
}

- (void)dealloc {
	[_cyanMovie release];
	[super dealloc];
}

- (void)arm {
	[super arm];
	
	RXOLog(@"starting movie");
	[[_cyanMovie movie] gotoBeginning];
	[[_cyanMovie movie] play];
	_dispatch = _render_dispatch;
}

- (void)_updateCardStateAnimation:(NSTimer *)timer {

}

- (void)diffuse {	 
	[[_cyanMovie movie] stop];
	_dispatch = _clear_dispatch;
	
	[super diffuse];
}

- (void)_cyanMovieIsDone:(NSNotification *)notification {
	[self diffuse];
}

- (void)setRenderRect:(CGRect)rect {
	[super setRenderRect:rect];
	[_cyanMovie setRenderRect:rect];
//	_dispatch = _clear_and_render_dispatch;
}

- (void)_clearAndRender:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
//	_dispatch = _render_dispatch;
//	_clear_dispatch.imp(self, _clear_dispatch.sel, outputTime, cgl_ctx);
//	_render_dispatch.imp(self, _render_dispatch.sel, outputTime, cgl_ctx);
}

- (void)_render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
	_movie_render_dispatch.imp(_cyanMovie, _dispatch.sel, outputTime, cgl_ctx, parent);
}

- (void)_clear:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
//	glScissor(_renderRect.origin.x, _renderRect.origin.y, _renderRect.size.width, _renderRect.size.height);
//	glEnable(GL_SCISSOR_TEST);
//	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	_dispatch.imp(self, _dispatch.sel, outputTime, cgl_ctx, parent);
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime parent:(id)parent {
	// WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
	[_cyanMovie performPostFlushTasks:outputTime parent:parent];
}

@end
