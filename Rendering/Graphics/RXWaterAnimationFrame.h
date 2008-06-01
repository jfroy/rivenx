//
//  RXWaterAnimationFrame.h
//  rivenx
//
//  Created by Jean-Francois Roy on 28/03/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "llvm/ModuleProvider.h"
#import "llvm/Function.h"

#import "RXRendering.h"


@interface RXWaterAnimationFrame : NSObject {
	llvm::ExistingModuleProvider* _MP;
	llvm::Function* _f;
}

- (id)initWithSFXEProgram:(uint16_t*)sfxeProgram roi:(NSRect)roi;

- (void)renderInContext:(CGLContextObj)cgl_ctx;

@end
