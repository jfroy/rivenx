//
//  RXTexture.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/08/2009.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"


#import "Rendering/RXRendering.h"
#import "Engine/RXStack.h"


@interface RXTexture : NSObject {
@public
    GLuint texture;
    GLenum target;
    rx_size_t size;
    
@protected
    BOOL _delete_when_done;
}

+ (RXTexture*)newStandardTextureWithTarget:(GLenum)target size:(rx_size_t)s context:(CGLContextObj)cgl_ctx lock:(BOOL)lock;

- (id)initWithID:(GLuint)texid target:(GLenum)t size:(rx_size_t)s deleteWhenDone:(BOOL)dwd;

- (void)bindWithContext:(CGLContextObj)cgl_ctx lock:(BOOL)lock;

- (void)updateWithBitmap:(uint16_t)tbmp_id archive:(MHKArchive*)archive;
- (void)updateWithBitmap:(uint16_t)tbmp_id stack:(RXStack*)stack;

@end
