//
//	RXTextureBroker.h
//	rivenx
//
//	Created by Jean-Francois Roy on 8/11/07.
//	Copyright 2007 MacStorm All rights reserved.
//

#import "RXRendering.h"


struct _rx_texture_bucket {
	GLuint tex_ids[32];
	GLsizei width;
	GLsizei height;
	uint32_t allocated;
	uint32_t in_use;
};

struct _rx_texture {
	GLuint texture;
	GLenum target;
	rx_size_t size;
	
	// private
	int32_t _bucket;
};
typedef struct _rx_texture rx_texture_t;

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

- (rx_texture_t)textureWithSize:(rx_size_t)size;
- (rx_texture_t)textureWithWidth:(GLsizei)width height:(GLsizei)height;

- (void)releaseTexture:(rx_texture_t)texture;

@end
