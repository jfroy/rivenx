//
//  GLShaderProgramManager.h
//  rivenx
//
//  Created by Jean-François Roy on 31/12/2006.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>

#import "Rendering/RXRendering.h"

extern NSString* const GLShaderCompileErrorDomain;
extern NSString* const GLShaderLinkErrorDomain;


@interface GLShaderProgramManager : NSObject {
    NSURL* _shaders_root;
    GLuint _1texcoord_vs;
}

+ (GLShaderProgramManager*)sharedManager;

- (GLuint)standardProgramWithFragmentShaderName:(NSString*)name
                                   extraSources:(NSArray*)extraSources
                                  epilogueIndex:(NSUInteger)epilogueIndex
                                        context:(CGLContextObj)cgl_ctx
                                          error:(NSError**)error;

- (GLuint)programWithName:(NSString*)name
        attributeBindings:(NSDictionary*)bindings
                  context:(CGLContextObj)cgl_ctx
                    error:(NSError**)error;

@end
