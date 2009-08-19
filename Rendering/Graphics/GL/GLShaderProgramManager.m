//
//  GLShaderProgramManager.m
//  rivenx
//
//  Created by Jean-François Roy on 31/12/2006.
//  Copyright 2006 MacStorm. All rights reserved.
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
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"initializing");
#endif
    
    // get the load context and lock it
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    CGLLockContext(cgl_ctx);
    
    // cache the URL to the shaders directory
    _shaders_root = (NSURL*)CFURLCreateWithFileSystemPath(NULL, (CFStringRef)[[NSBundle mainBundle] pathForResource:@"Shaders" ofType:nil], kCFURLPOSIXPathStyle, true);
    
    // get the source of the standard one texture coordinates vertex shader
    NSURL* source_url = [NSURL URLWithString:[@"1texcoord" stringByAppendingPathExtension:@"vs"] relativeToURL:_shaders_root];
    NSString* source = [NSString stringWithContentsOfURL:source_url encoding:NSASCIIStringEncoding error:NULL];
    if (!source)
        @throw [NSException exceptionWithName:@"RXShaderException" reason:@"Riven X was unable to load the standard texturing vertex shader's source." userInfo:nil];
    
    // convert the source to an ASCII C string
    GLchar* source_cstr = (GLchar*)[source cStringUsingEncoding:NSASCIIStringEncoding];
    if (!source_cstr)
        @throw [NSException exceptionWithName:@"RXShaderException" reason:@"Riven X was unable to convert the encoding of the standard texturing vertex shader's source." userInfo:nil];
    
    // create the vertex shader
    _1texcoord_vs = glCreateShader(GL_VERTEX_SHADER); glReportError();
    if (_1texcoord_vs == 0)
        @throw [NSException exceptionWithName:@"RXShaderException" reason:@"Riven X was unable to create the standard texturing vertex shader." userInfo:nil];
    
    // source it
    glShaderSource(_1texcoord_vs, 1, (const GLchar**)&source_cstr, NULL); glReportError();
    
    // compile it
    glCompileShader(_1texcoord_vs); glReportError();
    
    // check if it compiler or not
    GLint status;
    glGetShaderiv(_1texcoord_vs, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE) {
        NSError* error;
        GLint length;
        
        glGetShaderiv(_1texcoord_vs, GL_INFO_LOG_LENGTH, &length);
        GLchar* log = malloc(length);
        glGetShaderInfoLog(_1texcoord_vs, length, NULL, log);
        
        glGetShaderiv(_1texcoord_vs, GL_SHADER_SOURCE_LENGTH, &length);
        source_cstr = malloc(length);
        glGetShaderSource(_1texcoord_vs, length, NULL, source_cstr);
        
        NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithCString:log encoding:NSASCIIStringEncoding], @"GLCompileLog",
            [NSString stringWithCString:source_cstr encoding:NSASCIIStringEncoding], @"GLShaderSource",
            @"vertex", @"GLShaderType",
            nil];
        error = [NSError errorWithDomain:GLShaderCompileErrorDomain code:status userInfo:userInfo];
        
        free(source_cstr);
        free(log);
        
        @throw [NSException exceptionWithName:@"RXShaderCompileException"
                                       reason:@"Riven X was unable to compile the standard texturing vertex shader."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    CGLUnlockContext(cgl_ctx);
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

- (GLuint)standardProgramWithFragmentShaderName:(NSString*)name
                                   extraSources:(NSArray*)extraSources
                                  epilogueIndex:(NSUInteger)epilogueIndex
                                        context:(CGLContextObj)cgl_ctx
                                          error:(NSError**)error
{
    // WARNING: ASSUMES THE CALLER HAS LOCKED THE CONTEXT
    
    // argument validation
    if (name == nil || cgl_ctx == NULL)
        return 0;
    
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
    GLchar** shader_sources = malloc(sizeof(GLchar*) * (1 + [extraSources count]));
    
    // load up extra shader source
    size_t shaderSourceIndex = 0;
    if (shaderSourceIndex == epilogueIndex - 1)
        shaderSourceIndex++;
    
    NSEnumerator* sourceEnum = [extraSources objectEnumerator];
    NSString* source;
    while ((source = [sourceEnum nextObject])) {
        *(shader_sources + shaderSourceIndex) = (GLchar*)[source cStringUsingEncoding:NSASCIIStringEncoding];
        if (*(shader_sources + shaderSourceIndex) == NULL)
            goto failure_delete_shader_sources;
        
        // need to skip over the slot for the main shader source
        shaderSourceIndex++;
        if (shaderSourceIndex == epilogueIndex - 1)
            shaderSourceIndex++;
    }
    
    // fragment shader source
    fs = glCreateShader(GL_FRAGMENT_SHADER); glReportError();
    if (fs == 0)
        goto failure_delete_fs;
    
    shader_sources[epilogueIndex - 1] = (GLchar*)[fshader_source cStringUsingEncoding:NSASCIIStringEncoding];
    if (!shader_sources[epilogueIndex - 1])
        goto failure_delete_fs;
    glShaderSource(fs, (1 + [extraSources count]), (const GLchar**)shader_sources, NULL); glReportError();
    
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
    glAttachShader(program, _1texcoord_vs); glReportError();
    glAttachShader(program, fs); glReportError();
    
    // bind the attribute positions
    glBindAttribLocation(program, RX_ATTRIB_POSITION, "position"); glReportError();
    glBindAttribLocation(program, RX_ATTRIB_TEXCOORD0, "tex_coord0"); glReportError();
    
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
    glDeleteShader(fs); glReportError();
    
    free(shader_sources);
    return program;
    
failure_delete_program:
    glDeleteProgram(program); glReportError();
    
failure_delete_fs:
    glDeleteShader(fs); glReportError();
    
failure_delete_shader_sources:
    free(shader_sources);
    
    return 0;
}

@end
