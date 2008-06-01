//
//	GLShaderObject.h
//	rivenx
//
//	Created by Jean-François Roy on 31/12/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>


@interface GLShaderObject : NSObject {
	CGLContextObj cgl_ctx;
	
	GLenum _type;
	GLhandleARB _shader;
}

- (id)initWithShaderType:(GLenum)type;
- (GLenum)type;

- (NSString *)source;
- (void)setSource:(NSString *)source;

- (void)compile;
- (BOOL)isCompiled;

@end
