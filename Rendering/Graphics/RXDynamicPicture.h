//
//  RXDynamicPicture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 14/12/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import "Rendering/Graphics/RXPicture.h"


@interface RXDynamicPicture : RXPicture {

}

+ (GLuint)sharedDynamicPictureUnpackBuffer;

- (id)initWithTexture:(RXTexture*)texture samplingRect:(NSRect)sampling_rect renderRect:(NSRect)render_rect owner:(id)owner;

@end
