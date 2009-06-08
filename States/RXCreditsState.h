//
//  RXCreditsState.h
//  rivenx
//
//  Created by Jean-Francois Roy on 13/12/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRenderState.h"


@interface RXCreditsState : RXRenderState {
    void* _textureStorage;
    
    GLuint _creditsTextureObjects[19];
    GLfloat _textureBoxVertices[3][8];
    GLfloat _textureCoordinates[3][8];
    
    GLhandleARB _splitTexturingVertexShader;
    GLhandleARB _splitTexturingFragmentShader;
    GLhandleARB _splitTexturingProgram;
    
    CGPoint _bottomLeft;
    rx_size_t _viewportSize;
    
    CFTimeInterval _animationPeriod;
    uint64_t _lastFireTime;
    
    uint8_t _animationState;
    uint64_t _animationStartTime;
    GLfloat _animationProgress;
    
    GLfloat _scrollBoxHeight;
    uint8_t _leadBoxIndex;
    GLfloat _lastRenderedHeight;
    
    BOOL _kickOffAnimation;
    BOOL _killAnimation;
}

@end
