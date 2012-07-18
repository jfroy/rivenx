//
//  RXTextureBroker.h
//  rivenx
//
//  Created by Jean-Francois Roy on 8/11/07.
//  Copyright 2005-2012 MacStorm All rights reserved.
//

#import "Base/RXBase.h"

#import "Rendering/RXRendering.h"
#import "Rendering/Graphics/RXTexture.h"
#import "Base/RXDynamicBitfield.h"


struct _rx_texture_bucket {
    GLsizei width;
    GLsizei height;
    GLuint* tex_ids;
    RXDynamicBitfield* in_use;
};

#if defined(DEBUG)
struct _bucket_stat {
    GLsizei width;
    GLsizei height;
    GLuint count;
};
#endif


@interface RXTextureBroker : NSObject {
    CGLContextObj cgl_ctx;
    BOOL _toreDown;
    
    struct _rx_texture_bucket* _buckets;
    uint32_t _bucket_capacity;
    uint32_t _bucket_count;
    
#if defined(DEBUG)
    struct _bucket_stat* _bucket_stats;
    uint32_t _bucket_stat_count;
#endif
}

+ (RXTextureBroker*)sharedTextureBroker;

- (RXTexture*)newTextureWithSize:(rx_size_t)size;
- (RXTexture*)newTextureWithWidth:(GLsizei)width height:(GLsizei)height;

- (void)_printDebugStats;

@end
