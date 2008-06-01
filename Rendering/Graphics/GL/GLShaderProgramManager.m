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

+ (GLuint)shaderProgramWithName:(NSString*)name root:(NSURL*)root extraSources:(NSArray*)extraSources epilogueIndex:(NSUInteger)epilogueIndex context:(CGLContextObj)cgl_ctx error:(NSError**)error {
	// argument validation
	if (root == nil || name == nil || cgl_ctx == NULL) return 0;
	
	GLuint vs;
	GLuint fs;
	GLint status;
	GLuint program;
	
	// epilogueIndex needs to be increased by one in order to represent the epilogue index in the overall shader source array
	epilogueIndex++;
	
	// shader source URLs
	NSURL* vs_url = [NSURL URLWithString:[name stringByAppendingPathExtension:@"vs"] relativeToURL:root];
	NSURL* fs_url = [NSURL URLWithString:[name stringByAppendingPathExtension:@"fs"] relativeToURL:root];
	
	// read the shader sources
	NSString* vshader_source = [NSString stringWithContentsOfURL:vs_url encoding:NSASCIIStringEncoding error:error];
	NSString* fshader_source = [NSString stringWithContentsOfURL:fs_url encoding:NSASCIIStringEncoding error:error];
	if (!vshader_source || !fshader_source) return 0;
	
	// shader source array
	GLchar** shaderSources = malloc(sizeof(GLchar*) * (1 + [extraSources count]));
	
	// load up extra shader source
	size_t shaderSourceIndex = 0;
	if (shaderSourceIndex == epilogueIndex - 1) shaderSourceIndex++;
	
	NSEnumerator* sourceEnum = [extraSources objectEnumerator];
	NSString* source;
	while ((source = [sourceEnum nextObject])) {
		*(shaderSources + shaderSourceIndex) = (GLchar*)[source cStringUsingEncoding:NSASCIIStringEncoding];
		if (*(shaderSources + shaderSourceIndex) == NULL) goto failure_delete_shader_sources;
		
		// need to skip over the slot for the main shader source
		shaderSourceIndex++;
		if (shaderSourceIndex == epilogueIndex - 1) shaderSourceIndex++;
	}
	
	// vertex shader source
	vs = glCreateShader(GL_VERTEX_SHADER); glReportError();
	if (vs == 0) goto failure_delete_vs;
	
	shaderSources[epilogueIndex - 1] = (GLchar*)[vshader_source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!shaderSources[epilogueIndex - 1]) goto failure_delete_vs;
	glShaderSource(vs, (1 + [extraSources count]), (const GLchar**)shaderSources, NULL); glReportError();
	
	// fragment shader source
	fs = glCreateShader(GL_FRAGMENT_SHADER); glReportError();
	if (fs == 0) goto failure_delete_fs;
	
	shaderSources[epilogueIndex - 1] = (GLchar*)[fshader_source cStringUsingEncoding:NSASCIIStringEncoding];
	if (!shaderSources[epilogueIndex - 1]) goto failure_delete_fs;
	glShaderSource(fs, (1 + [extraSources count]), (const GLchar**)shaderSources, NULL); glReportError();
	
	// compile the vertex shader
	glCompileShader(vs); glReportError();
	glGetShaderiv(vs, GL_COMPILE_STATUS, &status);
	if (status != GL_TRUE) {
		if (error) {
			GLint length;
			
			glGetShaderiv(vs, GL_INFO_LOG_LENGTH, &length);
			GLchar* log = malloc(length);
			glGetShaderInfoLog(vs, length, NULL, log);
			
			glGetShaderiv(vs, GL_SHADER_SOURCE_LENGTH, &length);
			GLchar* source = malloc(length);
			glGetShaderSource(vs, length, NULL, source);
			
			NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithCString:log encoding:NSASCIIStringEncoding], @"GLCompileLog",
				[NSString stringWithCString:source encoding:NSASCIIStringEncoding], @"GLShaderSource",
				@"vertex", @"GLShaderType",
				nil];
			*error = [NSError errorWithDomain:GLShaderCompileErrorDomain code:status userInfo:userInfo];
			
			free(source);
			free(log);
		}
		
		goto failure_delete_fs;
	}
	
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
	glAttachShader(program, vs); glReportError();
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
	
failure_delete_vs:
	glDeleteShader(vs); glReportError();
	
failure_delete_shader_sources:
	free(shaderSources);
	
	return 0;
}

+ (id)allocWithZone:(NSZone *)zone {
	return nil;
}

@end
