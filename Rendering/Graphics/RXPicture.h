//
//  RXPicture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Rendering/RXRendering.h"


@interface RXPicture : NSObject <RXRenderingProtocol> {
    __weak id _owner;
    
    GLuint _tex;
    GLuint _vao;
    GLuint _index;
}

- (id)initWithTexture:(GLuint)texid vao:(GLuint)vao index:(GLuint)index owner:(id)owner;

- (id)owner;

@end
