//
//  RXPicture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import "Rendering/RXRendering.h"
#import "Rendering/Graphics/RXTexture.h"


@interface RXPicture : NSObject <RXRenderingProtocol> {
    id _owner;
    
    RXTexture* _texture;
    GLuint _vao;
    GLuint _index;
}

- (id)initWithTexture:(RXTexture*)texture vao:(GLuint)vao index:(GLuint)index owner:(id)owner;

- (id)owner;

@end
