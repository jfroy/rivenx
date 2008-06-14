//
//	RXTextureManager.m
//	rivenx
//
//	Created by Jean-Francois Roy on 8/11/07.
//	Copyright 2007 MacStorm All rights reserved.
//

#import "RXTextureBroker.h"


@implementation RXTextureBroker

static void allocate_texture_bucket(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket, GLsizei width, GLsizei height) {
	assert(bucket);
	
	// generate texture IDs
	glGenTextures(32, bucket->tex_ids);
	glReportError();
	
	// initial bucket state
	bucket->width = width;
	bucket->height = height;
	bucket->in_use = 0;
	bucket->allocated = 0;
}


static inline void free_texture_bucket(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket) {
	assert(bucket);
	
	glDeleteTextures(32, bucket->tex_ids);
	bzero(bucket->tex_ids, 32 * sizeof(GLuint));
	bucket->in_use = 0;
	bucket->allocated = 0;
}

static inline GLuint find_texture(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket) {
	assert(bucket);
	
	// find the first available texture
	uint32_t texindex = 0;
	for (; texindex < 32; texindex++) {
		if ((bucket->in_use & (1U << texindex)) == 0) break;
	}
	if (texindex == 32) return 0;
	if (bucket->tex_ids[texindex] == 0) return 0;
	
	if ((bucket->allocated & (1U << texindex)) == 0) {
		// save GL texture state
		glPushAttrib(GL_TEXTURE_BIT);
		glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
		
		// allocate the texture
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, bucket->tex_ids[texindex]);
		glReportError();
		
		// texture parameters
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glReportError();
		
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, bucket->width, bucket->height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
		glReportError();
		
		// restore GL texture state
		glPopAttrib();
		glPopClientAttrib();
		
		bucket->allocated |= (1U << texindex);
	}
	
	bucket->in_use |= (1U << texindex);
	return bucket->tex_ids[texindex];
}

static inline void free_texture(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket, GLuint texture_id) {
	assert(bucket);
	assert(texture_id != 0);
	
	uint32_t texindex = 0;
	for (; texindex < 32; texindex++) {
		if (bucket->tex_ids[texindex] == texture_id) {
			bucket->in_use &= ~(1U << texindex);
			return;
		}
	}
}

- (id)init {
	self = [super init];
	if (!self) return nil;
	
	cgl_ctx = [RXGetWorldView() loadContext];
	
	_buckets = calloc(8, sizeof(struct _rx_texture_bucket));
	_bucket_capacity = 8;
	
	// don't need to lock the load context, this runs on the main thread
	
	// some standard buckets
//	allocate_texture_bucket(cgl_ctx, _buckets, 32);
//	allocate_texture_bucket(cgl_ctx, _buckets + 1, 64, 64);
//	allocate_texture_bucket(cgl_ctx, _buckets + 2, 128, 128);
//	allocate_texture_bucket(cgl_ctx, _buckets + 3, 256, 256);
//	allocate_texture_bucket(cgl_ctx, _buckets + 4, 512, 512);
//	allocate_texture_bucket(cgl_ctx, _buckets + 5, 1024, 1024);
	_bucket_count = 0;
	
	return self;
}

- (void)teardown {
	if (_toreDown) return;
	_toreDown = YES;
#if defined(DEBUG)
	RXOLog(@"tearing down");
#endif
	
	// don't need to lock the load context, this runs on the main thread
	
	for (uint32_t bucket_i = 0; bucket_i < _bucket_count; bucket_i++) free_texture_bucket(cgl_ctx, _buckets + bucket_i);
	_bucket_count = 0;
	
#if defined(DEBUG)
	NSMutableString* statsString = [NSMutableString new];
	for (GLuint i = 0; i < _bucket_stat_count; i++) [statsString appendFormat:@"\t%dx%d: %u\n", (int)_bucket_stats[i].width, (int)_bucket_stats[i].height, (unsigned int)_bucket_stats[i].count];
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"texture bucket statistics\n%@", statsString);
	[statsString release];
#endif
}

- (void)dealloc {
	[self teardown];
	
	free(_buckets);
#if defined(DEBUG)
	free(_bucket_stats);
#endif
	
	[super dealloc];
}

- (void)_createBucketWithSize:(rx_size_t)size {
	if (_bucket_count == _bucket_capacity) {
		_bucket_capacity += 0x10;
		_buckets = realloc(_buckets, _bucket_capacity * sizeof(struct _rx_texture_bucket));
	}
	
	allocate_texture_bucket(cgl_ctx, _buckets + _bucket_count, size.width, size.height);
	_bucket_count++;
}

- (rx_texture_t)textureWithSize:(rx_size_t)size {
	assert(size.width > 0);
	assert(size.height > 0);
	
	// canonical invalid texture object
	rx_texture_t texture = {0, -1};
	if (_toreDown) return texture;
	
	// find the bigger of the two
	__attribute__ ((unused)) GLsizei biggest = MAX(size.width, size.height);
	
	// find the right bucket
	// FIXME: need to sort buckets by width and height and perform 2 binary searches on them
	texture._bucket = 0;
	for (; texture._bucket < (int32_t)_bucket_count; texture._bucket++) {
		if (_buckets[texture._bucket].width == size.width && _buckets[texture._bucket].height == size.height) break;
	}
	
	// this may run on the main thread or stack thread
	CGLLockContext(cgl_ctx);
	
	// Maybe we don't have a bucket for that size?
	if (texture._bucket == (int32_t)_bucket_count) [self _createBucketWithSize:size];
	
	// try to allocate a texture out of the bucket
	texture.texture = find_texture(cgl_ctx, _buckets + texture._bucket);
	if (texture.texture == 0) {
		// bucket is full, create another
		[self _createBucketWithSize:size];
		texture._bucket = _bucket_count - 1;
		texture.texture = find_texture(cgl_ctx, _buckets + texture._bucket);
	}
	
	texture.target = GL_TEXTURE_RECTANGLE_ARB;
	texture.size = size;
	
	CGLUnlockContext(cgl_ctx);
	
#if defined(DEBUG)
	if (_bucket_stat_count == 0) {
		_bucket_stats = malloc(sizeof(struct _bucket_stat));
		_bucket_stat_count = 1;
		_bucket_stats[0].width = size.width;
		_bucket_stats[0].height = size.height;
		_bucket_stats[0].count = 0;
	}
	
	uint32_t i = 0;
	for (; i < _bucket_stat_count; i++) {
		if (_bucket_stats[i].width == size.width && _bucket_stats[i].height == size.height) {
			_bucket_stats[i].count++;
			break;
		}
	}
	
	if (i == _bucket_stat_count) {
		_bucket_stat_count++;
		_bucket_stats = realloc(_bucket_stats, _bucket_stat_count * sizeof(struct _bucket_stat));
		_bucket_stats[i].width = size.width;
		_bucket_stats[i].height = size.height;
		_bucket_stats[i].count = 1;
	}
#endif
	
#if defined(DEBUG)
	RXOLog(@"allocated texture: %u (%ux%u)", texture.texture, texture.size.width, texture.size.height);
#endif
	return texture;
}

- (rx_texture_t)textureWithWidth:(GLsizei)width height:(GLsizei)height {
	return [self textureWithSize:RXSizeMake(width, height)];
}

- (void)releaseTexture:(rx_texture_t)texture {
	free_texture(cgl_ctx, _buckets + texture._bucket, texture.texture);
}

@end
