//
//	GLShaderObject.m
//	rivenx
//
//	Created by Jean-François Roy on 31/12/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import "GLShaderObject.h"
#import <OpenGL/CGLMacro.h>


@implementation GLShaderObject

+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithShaderType:(GLenum)type {
	self = [super init];
	if (!self) return nil;
	
	cgl_ctx = CGLGetCurrentContext();
	_type = type;
	
	_shader = glCreateShaderObjectARB(_type);
	
	return self;
}

- (void)_invalidateShader {
	if (_shader != 0) {
		glDeleteObjectARB(_shader);
		_shader = 0;
	}
}

- (void)dealloc {
	[self _invalidateShader];
	
	[super dealloc];
}

- (GLenum)type {
	return _type;
}

- (NSString *)source {
	if (_shader == 0) return nil;
	
	GLint sourceLength;
	glGetObjectParameterivARB(_shader, GL_OBJECT_SHADER_SOURCE_LENGTH_ARB, &sourceLength);
	if (sourceLength == 0) return nil;
	
	GLcharARB* source = malloc(sourceLength);
	glGetShaderSourceARB(_shader, sourceLength, NULL, source);
	
	return [[[NSString alloc] initWithBytesNoCopy:source length:sourceLength encoding:NSASCIIStringEncoding freeWhenDone:YES] autorelease];
}

- (void)setSource:(NSString *)source {
	// WARNING: NOT THREAD SAFE
	if (!_shader) return;
	
	// Get the source as an ASCII C string
	const GLcharARB* cSource = [source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!cSource) return;
	
	// Copy the source to OpenGL
	glShaderSourceARB(_shader, 1, &cSource, NULL);
}

- (void)compile {
	if (_shader == 0) return;
	glCompileShaderARB(_shader);
}

- (BOOL)isCompiled {
	if (_shader == 0) return NO;
	
	GLint result;
	glGetObjectParameterivARB(_shader, GL_OBJECT_COMPILE_STATUS_ARB, &result);
	return (BOOL)result;
}

@end
