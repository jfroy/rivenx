//
//	GLShaderProgramManager.h
//	rivenx
//
//	Created by Jean-François Roy on 31/12/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "GL.h"

extern NSString* const GLShaderCompileErrorDomain;
extern NSString* const GLShaderLinkErrorDomain;


@interface GLShaderProgramManager : NSObject {
}

+ (GLuint)shaderProgramWithName:(NSString*)name root:(NSURL*)root extraSources:(NSArray*)extraSources epilogueIndex:(NSUInteger)epilogueIndex context:(CGLContextObj)cgl_ctx error:(NSError**)error;

@end
