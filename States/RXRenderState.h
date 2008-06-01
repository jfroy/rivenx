//
//	RXState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 11/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRendering.h"


typedef struct __RXStateDelegateFlags {
#ifdef __BIG_ENDIAN__
	unsigned int	stateDidDiffuse:1;
#else
	unsigned int	stateDidDiffuse:1;
#endif
} _RXStateDelegateFlags;


@interface RXRenderState : NSResponder <RXRenderingProtocol> {
	id _delegate;
	_RXStateDelegateFlags _delegateFlags;
	
	BOOL _armed;
	CGRect _renderRect;
}

- (id)delegate;
- (void)setDelegate:(id)delegate;

- (void)arm;
- (void)diffuse;

- (BOOL)isArmed;

@end

@interface NSObject (RXStateDelegate)
- (void)stateDidDiffuse:(RXRenderState *)state;
@end
