//
//  RXDynamicPicture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 14/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXPicture.h"


@interface RXDynamicPicture : RXPicture {

}

+ (GLuint)sharedDynamicPictureUnpackBuffer;

- (id)initWithTexture:(GLuint)texid samplingRect:(NSRect)samplingRect renderRect:(NSRect)renderRect owner:(id)owner;

@end
