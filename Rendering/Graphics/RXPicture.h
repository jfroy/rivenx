//
//  RXPicture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 10/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXRendering.h"


@interface RXPicture : NSObject <RXRenderingProtocol> {
	GLuint _tex;
	GLuint _vao;
	GLuint _index;
}

- (id)initWithTexture:(GLuint)texid vao:(GLuint)vao index:(GLuint)index;

@end
