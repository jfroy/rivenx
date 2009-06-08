//
//  RXCreditsState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 13/12/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <mach/mach.h>
#import <mach/mach_time.h>

#import <OpenGL/CGLMacro.h>
#import <MHKKit/MHKKit.h>

#import "Engine/RXWorldProtocol.h"
#import "RXCreditsState.h"

static const uint16_t kFirstCreditsTextureID = 302;
static const GLuint kCreditsTextureCount = 19;


@implementation RXCreditsState

- (id)init {
    self = [super init];
    if (!self) return nil;
    
    // initialize a few things for animations
    CVTime displayLinkRP = CVDisplayLinkGetNominalOutputVideoRefreshPeriod([RXGetWorldView() displayLink]);
    _animationPeriod = displayLinkRP.timeValue / (CFTimeInterval)(displayLinkRP.timeScale);
    
    MHKArchive* archive = [g_world extraBitmapsArchive];
    
    // precompute the total storage we'll need because it will yield a far more efficient texture upload
    const size_t textureStorageOffsetStep = kRXCardViewportSize.width * kRXCardViewportSize.height * 4;
    size_t textureStorageSize = kCreditsTextureCount * textureStorageOffsetStep;
    
    // allocate one big chunk of memory for all the textures
    _textureStorage = malloc(textureStorageSize);
    
    // don't need to lock the context since this runs in the main thread
    CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
    
    // create the texture ID array and the textures themselves
    glGenTextures(kCreditsTextureCount, _creditsTextureObjects);
    
    // actually load the textures
    size_t textureStorageOffset = 0;
    GLuint currentTextureIndex = 0;
    for(; currentTextureIndex < kCreditsTextureCount; currentTextureIndex++) {
        [archive loadBitmapWithID:kFirstCreditsTextureID + currentTextureIndex 
                           buffer:BUFFER_OFFSET(_textureStorage, textureStorageOffset) 
                           format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED 
                            error:NULL];
        
        // bind the corresponding texture object, configure it and upload the picture
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[currentTextureIndex]);
        
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 
                     0, 
                     GL_RGBA, 
                     kRXCardViewportSize.width, 
                     kRXCardViewportSize.height, 
                     0, 
                     GL_BGRA, 
                     GL_UNSIGNED_INT_8_8_8_8_REV, 
                     BUFFER_OFFSET(_textureStorage, textureStorageOffset));
        
        // move along
        textureStorageOffset += textureStorageOffsetStep;
    }
    
    // all the textures are the same size, so we need one set of texture coordinates
    _textureCoordinates[0][0] = 0.0f;
    _textureCoordinates[0][1] = kRXCardViewportSize.height;
    
    _textureCoordinates[0][2] = kRXCardViewportSize.width;
    _textureCoordinates[0][3] = kRXCardViewportSize.height;
    
    _textureCoordinates[0][4] = kRXCardViewportSize.width;
    _textureCoordinates[0][5] = 0.0f;
    
    _textureCoordinates[0][6] = 0.0f;
    _textureCoordinates[0][7] = 0.0f;
    
    memcpy(_textureCoordinates[1], _textureCoordinates[0], sizeof(GLfloat) * 8);
    memcpy(_textureCoordinates[2], _textureCoordinates[0], sizeof(GLfloat) * 8);
    
    // precompute the total height of the "scroll box" (kCreditsTextureCount - 2 + 2)
    _scrollBoxHeight = kRXCardViewportSize.height * 19.0f;
    
    return self;
}

- (void)dealloc {
    // delete the OpenGL texture objects
    CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];

    // delete the texture objects
    glDeleteTextures(kCreditsTextureCount, _creditsTextureObjects);
    
    // delete the shaders and the program
    //glDeleteObjectARB(_splitTexturingProgram);
    
    // don't bother with OpenGL anymore
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // now  that the texture objects are gone, we can delete the texture storage area
    free(_textureStorage);
    
    [super dealloc];
}

- (void)_animationThreadMain:(id)object {
    // we need the mach timebase information
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    
    // compute the period in mach time units
    uint64_t animation_period_nanoseconds = _animationPeriod * 1000000000ULL;
    uint64_t animation_period_mach = animation_period_nanoseconds * timebase.denom / timebase.numer;

    while(!_killAnimation) {
        // record the last fire time
        uint64_t now_mach = mach_absolute_time();
        
        // compute how many seconds have elapsed in the current animation state
        CFTimeInterval animation_elapased = ((now_mach - _animationStartTime) * timebase.numer / timebase.denom) / 1000000000.0;
        
        // 302 fade in / out, 303 fade in / out - over 1 second
        if(_animationState == 1 || _animationState == 3 || _animationState == 4 || _animationState == 6) {
            _animationProgress = (GLfloat)animation_elapased;
        }
        
        // 302 display, 303 display - over 5 seconds
        if(_animationState == 2 || _animationState == 5) {
            _animationProgress = (GLfloat)(animation_elapased / 5.0);
        }
        
        // rolling credits, over about 3 minutes (190 seconds)
        if(_animationState == 7) {
            _animationProgress = (GLfloat)(animation_elapased / 190.0);
        }
        
        // if we've reached the end of the current animation state, change state
        if(_animationProgress > 1.0) {
            _animationProgress = 0.0f;
            _animationStartTime = mach_absolute_time();
            _animationState++;
            RXOLog(@"%@: entering animation state %d", self, _animationState);
        }
        
        // if we're reached animation state 8, we're done
        if(_animationState == 8) _killAnimation = YES;
        
        // compute until when we need to sleep
        _lastFireTime = now_mach;
        now_mach = mach_absolute_time();
        uint64_t wake_mach = _lastFireTime + animation_period_mach;
        if(wake_mach > now_mach) mach_wait_until(wake_mach);
    }
}

- (void)render:(const CVTimeStamp*)outputTime inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD    
    if (_kickOffAnimation) {
        _kickOffAnimation = NO;
        _animationProgress = 2.0f;
    }
    
    if (_animationState == 0) return;
    
    // for the centered stages, one common set of commands to set the coordinates
    if (_animationState < 7) {
        // centered on screen
        _textureBoxVertices[0][0] = _bottomLeft.x;
        _textureBoxVertices[0][1] = kRXCardViewportOriginOffset.x;
        
        _textureBoxVertices[0][2] = _bottomLeft.x + kRXCardViewportSize.width;
        _textureBoxVertices[0][3] = kRXCardViewportOriginOffset.y;
        
        _textureBoxVertices[0][4] = _textureBoxVertices[0][2];
        _textureBoxVertices[0][5] = kRXCardViewportOriginOffset.y + kRXCardViewportSize.height;
        
        _textureBoxVertices[0][6] = _bottomLeft.x;
        _textureBoxVertices[0][7] = _textureBoxVertices[0][5];
    }
    
    // 302 fade in, over 1 second
    if (_animationState == 1) {
        glColor4f(1.0f, 1.0f, 1.0f, _animationProgress);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[0]);
        glDrawArrays(GL_QUADS, 0, 4);
    }
    
    // 302 display, 5 seconds
    if (_animationState == 2) {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[0]);
        glDrawArrays(GL_QUADS, 0, 4);
    }
    
    // 302 fade out, over 1 second
    if (_animationState == 3) {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f - _animationProgress);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[0]);
        glDrawArrays(GL_QUADS, 0, 4);
    }
    
    // 303 fade in, over 1 second
    if (_animationState == 4) {
        glColor4f(1.0f, 1.0f, 1.0f, _animationProgress);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1]);
        glDrawArrays(GL_QUADS, 0, 4);
    }
    
    // 303 display, 5 seconds
    if (_animationState == 5) {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1]);
        glDrawArrays(GL_QUADS, 0, 4);
    }
    
    // 303 fade out, over 1 second
    if (_animationState == 6) {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f - _animationProgress);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1]);
        glDrawArrays(GL_QUADS, 0, 4);
    }
    
    // rolling credits, over about 3 minutes (190 seconds)
    if (_animationState == 7) {
        GLfloat _textureIndexProgress = 19.0f * _animationProgress;
        uint8_t _leadTextureIndex = (uint8_t)lrintf(_textureIndexProgress);
        
        if(_leadTextureIndex == 0) {
            _textureBoxVertices[0][0] = _bottomLeft.x;
            _textureBoxVertices[0][1] = kRXCardViewportOriginOffset.y - (kRXCardViewportSize.height * (1.0f - _textureIndexProgress));
            
            _textureBoxVertices[0][2] = _bottomLeft.x + kRXCardViewportSize.width;
            _textureBoxVertices[0][3] = _textureBoxVertices[0][1];
            
            _textureBoxVertices[0][4] = _textureBoxVertices[0][2];
            _textureBoxVertices[0][5] = _textureBoxVertices[0][1] + kRXCardViewportSize.height;
            
            _textureBoxVertices[0][6] = _bottomLeft.x;
            _textureBoxVertices[0][7] = _textureBoxVertices[0][5];
            
            glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[2 + _leadTextureIndex]);
            glDrawArrays(GL_QUADS, 0, 4);
        }
        
        if (_leadTextureIndex > 0 && _leadTextureIndex < 17) {
            _textureBoxVertices[1][0] = _bottomLeft.x;
            _textureBoxVertices[1][1] = kRXCardViewportOriginOffset.y - (kRXCardViewportSize.height * (1.0f - _textureIndexProgress + _leadTextureIndex));
            
            _textureBoxVertices[1][2] = _bottomLeft.x + kRXCardViewportSize.width;
            _textureBoxVertices[1][3] = _textureBoxVertices[1][1];
            
            _textureBoxVertices[1][4] = _textureBoxVertices[1][2];
            _textureBoxVertices[1][5] = _textureBoxVertices[1][1] + kRXCardViewportSize.height;
            
            _textureBoxVertices[1][6] = _bottomLeft.x;
            _textureBoxVertices[1][7] = _textureBoxVertices[1][5];
            
            _textureBoxVertices[0][0] = _bottomLeft.x;
            _textureBoxVertices[0][1] = _textureBoxVertices[1][5];
            
            _textureBoxVertices[0][2] = _bottomLeft.x + kRXCardViewportSize.width;
            _textureBoxVertices[0][3] = _textureBoxVertices[0][1];
            
            _textureBoxVertices[0][4] = _textureBoxVertices[0][2];
            _textureBoxVertices[0][5] = _textureBoxVertices[0][1] + kRXCardViewportSize.height;
            
            _textureBoxVertices[0][6] = _bottomLeft.x;
            _textureBoxVertices[0][7] = _textureBoxVertices[0][5];
            
            glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
            
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1 + _leadTextureIndex]);
            glDrawArrays(GL_QUADS, 0, 4);
            
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[2 + _leadTextureIndex]);
            glDrawArrays(GL_QUADS, 4, 4);
        }
        
        if (_leadTextureIndex == 17) {
            _textureBoxVertices[0][0] = _bottomLeft.x;
            _textureBoxVertices[0][1] = kRXCardViewportOriginOffset.y - (kRXCardViewportSize.height * (1.0f - _textureIndexProgress + _leadTextureIndex - 1));
            
            _textureBoxVertices[0][2] = _bottomLeft.x + kRXCardViewportSize.width;
            _textureBoxVertices[0][3] = _textureBoxVertices[0][1];
            
            _textureBoxVertices[0][4] = _textureBoxVertices[0][2];
            _textureBoxVertices[0][5] = _textureBoxVertices[0][1] + kRXCardViewportSize.height;
            
            _textureBoxVertices[0][6] = _bottomLeft.x;
            _textureBoxVertices[0][7] = _textureBoxVertices[0][5];
            
            glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _creditsTextureObjects[1 + _leadTextureIndex]);
            glDrawArrays(GL_QUADS, 0, 4);
        }
    }
}

- (void)performPostFlushTasks:(const CVTimeStamp*)outputTime {
    // WARNING: MUST RUN IN THE CORE VIDEO RENDER THREAD
}

@end
