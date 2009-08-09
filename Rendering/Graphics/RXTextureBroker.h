//
//  RXTextureBroker.h
//  rivenx
//
//  Created by Jean-Francois Roy on 8/11/07.
//  Copyright 2007 MacStorm All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Rendering/RXRendering.h"
#import "Rendering/Graphics/RXTexture.h"


#define RX_TEXTURE_BUCKET_LENGTH 32

struct _rx_texture_bucket {
    GLuint tex_ids[RX_TEXTURE_BUCKET_LENGTH];
    GLsizei width;
    GLsizei height;
    uint32_t in_use;
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
