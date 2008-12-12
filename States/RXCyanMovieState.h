//
//	RXCyanMovieState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 11/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRenderState.h"
#import "Rendering/Graphics/RXMovie.h"


@interface RXCyanMovieState : RXRenderState {
	RXMovie* _cyanMovie;
	rx_render_dispatch_t _dispatch;
}

@end
