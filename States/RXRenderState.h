//
//	RXState.h
//	rivenx
//
//	Created by Jean-Francois Roy on 11/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRendering.h"


typedef struct __RXStateDelegateFlags {

} _RXStateDelegateFlags;


@interface RXRenderState : NSResponder <RXRenderingProtocol> {
	id _delegate;
	_RXStateDelegateFlags _delegateFlags;
}

- (id)delegate;
- (void)setDelegate:(id)delegate;

@end
