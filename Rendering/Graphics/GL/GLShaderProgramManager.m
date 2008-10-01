//
//	GLShaderProgramManager.m
//	rivenx
//
//	Created by Jean-François Roy on 31/12/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <OpenGL/CGLMacro.h>

#import "GL_debug.h"

#import "GLShaderProgramManager.h"

NSString* const GLShaderCompileErrorDomain = @"GLShaderCompileErrorDomain";
NSString* const GLShaderLinkErrorDomain = @"GLShaderLinkErrorDomain";

@implementation GLShaderProgramManager

+ (GLShaderProgramManager*)sharedManager {
	// WARNING: the first call to this method is not thread safe
	static GLShaderProgramManager* manager = nil;
	if (manager == nil)
		manager = [GLShaderProgramManager new];
	return manager;
}

- (id)init {
	self = [super init];
	if (!self)
		return nil;
	
	// if we're loaded before the world view has initialized OpenGL, bail out
	if (!g_worldView) {
		[self release];
		return nil;
	}
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"initializing");
#endif
	
	// get the load context and lock it
	CGLContextObj cgl_ctx = [g_worldView loadContext];
	CGLLockContext(cgl_ctx);
	
	// cache the URL to the shaders directory
	_shaders_root = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Shaders" ofType:nil] isDirectory:YES];
	
	// get the source of the standard one texture coordinates vertex shader
	NSURL* ff_tex0_vs_url = [NSURL URLWithString:[@"ff_tex0_pos" stringByAppendingPathExtension:@"vs"] relativeToURL:_shaders_root];
	NSString* ff_tex0_vs_source = [NSString stringWithContentsOfURL:ff_tex0_vs_url encoding:NSASCIIStringEncoding error:NULL];
	if (!ff_tex0_vs_source)
		@throw [NSException exceptionWithName:@"RXShaderException" reason:@"Riven X was unable to load the standard texturing vertex shader's source." userInfo:nil];
	
	// convert the source to an ASCII C string
	GLchar* ff_tex0_vs_csource = (GLchar*)[ff_tex0_vs_source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!ff_tex0_vs_source)
		@throw [NSException exceptionWithName:@"RXShaderException" reason:@"Riven X was unable to convert the encoding of the standard texturing vertex shader's source." userInfo:nil];
	
	// create the vertex shader
	_ff_tex0_pos_vs = glCreateShader(GL_VERTEX_SHADER); glReportError();
	if (_ff_tex0_pos_vs == 0)
		@throw [NSException exceptionWithName:@"RXShaderException" reason:@"Riven X was unable to create the standard texturing vertex shader." userInfo:nil];
	
	// source it
	glShaderSource(_ff_tex0_pos_vs, 1, (const GLchar**)&ff_tex0_vs_csource, NULL); glReportError();
	
	// compile it
	glCompileShader(_ff_tex0_pos_vs); glReportError();
	
	// check if it compiler or not
	GLint status;
	glGetShaderiv(_ff_tex0_pos_vs, GL_COMPILE_STATUS, &status);
	if (status != GL_TRUE) {
		NSError* error;
		GLint length;
		
		glGetShaderiv(_ff_tex0_pos_vs, GL_INFO_LOG_LENGTH, &length);
		GLchar* log = malloc(length);
		glGetShaderInfoLog(_ff_tex0_pos_vs, length, NULL, log);
		
		glGetShaderiv(_ff_tex0_pos_vs, GL_SHADER_SOURCE_LENGTH, &length);
		GLchar* source = malloc(length);
		glGetShaderSource(_ff_tex0_pos_vs, length, NULL, source);
		
		NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSString stringWithCString:log encoding:NSASCIIStringEncoding], @"GLCompileLog",
			[NSString stringWithCString:source encoding:NSASCIIStringEncoding], @"GLShaderSource",
			@"vertex", @"GLShaderType",
			nil];
		error = [NSError errorWithDomain:GLShaderCompileErrorDomain code:status userInfo:userInfo];
		
		free(source);
		free(log);
		
		@throw [NSException exceptionWithName:@"RXShaderCompileException" reason:@"Riven X was unable to compile the standard texturing vertex shader." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	}
	
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	return self;
}

- (NSUInteger)retainCount {
	return UINT_MAX;
}

- (id)retain {
	return self;
}

- (void)release {
	
}

- (id)autorelease {
	return self;
}

- (GLuint)standardProgramWithFragmentShaderName:(NSString*)name extraSources:(NSArray*)extraSources epilogueIndex:(NSUInteger)epilogueIndex context:(CGLContextObj)cgl_ctx error:(NSError**)error {
	// WARNING: ASSUMES THE CALLER HAS LOCKED THE CONTEXT
	
	// argument validation
	if (name == nil || cgl_ctx == NULL)
		return 0;
	
	GLuint vs;
	GLuint fs;
	GLint status;
	GLuint program;
	
	// epilogueIndex needs to be increased by one in order to represent the epilogue index in the overall shader source array
	epilogueIndex++;
	
	// shader source URLs
	NSURL* fs_url = [NSURL URLWithString:[name stringByAppendingPathExtension:@"fs"] relativeToURL:_shaders_root];
	
	// read the shader sources
	NSString* fshader_source = [NSString stringWithContentsOfURL:fs_url encoding:NSASCIIStringEncoding error:error];
	if (!fshader_source)
		return 0;
	
	// shader source array
	GLchar** shaderSources = malloc(sizeof(GLchar*) * (1 + [extraSources count]));
	
	// load up extra shader source
	size_t shaderSourceIndex = 0;
	if (shaderSourceIndex == epilogueIndex - 1)
		shaderSourceIndex++;
	
	NSEnumerator* sourceEnum = [extraSources objectEnumerator];
	NSString* source;
	while ((source = [sourceEnum nextObject])) {
		*(shaderSources + shaderSourceIndex) = (GLchar*)[source cStringUsingEncoding:NSASCIIStringEncoding];
		if (*(shaderSources + shaderSourceIndex) == NULL)
			goto failure_delete_shader_sources;
		
		// need to skip over the slot for the main shader source
		shaderSourceIndex++;
		if (shaderSourceIndex == epilogueIndex - 1)
			shaderSourceIndex++;
	}
	
	// fragment shader source
	fs = glCreateShader(GL_FRAGMENT_SHADER); glReportError();
	if (fs == 0) goto failure_delete_fs;
	
	shaderSources[epilogueIndex - 1] = (GLchar*)[fshader_source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!shaderSources[epilogueIndex - 1])
		goto failure_delete_fs;
	glShaderSource(fs, (1 + [extraSources count]), (const GLchar**)shaderSources, NULL); glReportError();
	
	// compile the fragment shader
	glCompileShader(fs); glReportError();
	glGetShaderiv(fs, GL_COMPILE_STATUS, &status);
	if (status != GL_TRUE) {
		if (error) {
			GLint length;
			
			glGetShaderiv(fs, GL_INFO_LOG_LENGTH, &length);
			GLchar* log = malloc(length);
			glGetShaderInfoLog(fs, length, NULL, log);
			
			glGetShaderiv(fs, GL_SHADER_SOURCE_LENGTH, &length);
			GLchar* source = malloc(length);
			glGetShaderSource(fs, length, NULL, source);
			
			NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithCString:log encoding:NSASCIIStringEncoding], @"GLCompileLog",
				[NSString stringWithCString:source encoding:NSASCIIStringEncoding], @"GLShaderSource",
				@"fragment", @"GLShaderType",
				nil];
			*error = [NSError errorWithDomain:GLShaderCompileErrorDomain code:status userInfo:userInfo];
			
			free(source);
			free(log);
		}
		
		goto failure_delete_fs;
	}
	
	// create the program
	program = glCreateProgram(); glReportError();
	
	// attach the vertex and fragment shaders
	glAttachShader(program, _ff_tex0_pos_vs); glReportError();
	glAttachShader(program, fs); glReportError();
	
	// link
	glLinkProgram(program); glReportError();
	glGetProgramiv(program, GL_LINK_STATUS, &status);
	if (status != GL_TRUE) {
		if (error) {
			GLint length;
			
			glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
			GLchar* log = malloc(length);
			glGetProgramInfoLog(program, length, NULL, log);
			
			NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithCString:log encoding:NSASCIIStringEncoding], @"GLLinkLog",
				nil];
			*error = [NSError errorWithDomain:GLShaderLinkErrorDomain code:status userInfo:userInfo];
			
			free(log);
		}
		
		goto failure_delete_program;
	}
	
	// we don't need the shader objects anymore
	glDeleteShader(vs); glReportError();
	glDeleteShader(fs); glReportError();
	
	return program;
	
failure_delete_program:
	glDeleteProgram(program); glReportError();
	
failure_delete_fs:
	glDeleteShader(fs); glReportError();
	
failure_delete_shader_sources:
	free(shaderSources);
	
	return 0;
}

@end
