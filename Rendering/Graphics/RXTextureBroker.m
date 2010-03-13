//
//  RXTextureManager.m
//  rivenx
//
//  Created by Jean-Francois Roy on 8/11/07.
//  Copyright 2005-2010 MacStorm All rights reserved.
//

#import "Rendering/Graphics/RXTextureBroker.h"
#import "Utilities/GTMObjectSingleton.h"


@interface RXBrokeredTexture : RXTexture {
@public
    struct _rx_texture_bucket* _bucket;
    uint32_t _bucket_index;
}
@end


@interface RXTextureBroker (RXTextureBroker_Private)
- (void)_createBucketWithSize:(rx_size_t)size;
- (void)_recycleTexture:(RXBrokeredTexture*)texture;
@end


@implementation RXBrokeredTexture

- (void)dealloc {
    [[RXTextureBroker sharedTextureBroker] _recycleTexture:self];
    [super dealloc];
}

@end


@implementation RXTextureBroker

static void allocate_texture_bucket(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket, GLsizei width, GLsizei height) {
    assert(bucket);
    
    // initial bucket state
    bucket->in_use = [RXDynamicBitfield new];
    bucket->tex_ids = calloc([bucket->in_use segmentCount] * [bucket->in_use segmentBits], sizeof(GLuint));
    bucket->width = width;
    bucket->height = height;
}

static void grow_texture_bucket(struct _rx_texture_bucket* bucket) {
    size_t old_size = [bucket->in_use segmentCount] * [bucket->in_use segmentBits] * sizeof(GLuint);
    size_t new_size = ([bucket->in_use segmentCount] + 1) * [bucket->in_use segmentBits] * sizeof(GLuint);
    bucket->tex_ids = realloc(bucket->tex_ids, new_size);
    bzero(BUFFER_OFFSET(bucket->tex_ids, old_size), new_size - old_size);

#if defined(DEBUG)
    RXLog(kRXLoggingGraphics, kRXLoggingLevelDebug, @"grew texture bucket (%ux%u)", bucket->width, bucket->height);
#endif
}

static inline void free_texture_bucket(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket) {
    assert(bucket);
    
    CGLLockContext(cgl_ctx);
    size_t max_tex = [bucket->in_use segmentCount] * [bucket->in_use segmentBits];
    for (uintptr_t tex_index = 0; tex_index < max_tex; tex_index++) {
        if (bucket->tex_ids[tex_index])
            glDeleteTextures(1, bucket->tex_ids + tex_index);
    }
    CGLUnlockContext(cgl_ctx);
    
    free(bucket->tex_ids);
    [bucket->in_use release];
}

static inline GLuint find_texture(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket, uint32_t *out_index) {
    assert(bucket);
    
    // if all the bits are set, we need to grow the bucket
    if ([bucket->in_use isAllSet])
        grow_texture_bucket(bucket);
    
    // find the first available texture
    size_t max_tex = [bucket->in_use segmentCount] * [bucket->in_use segmentBits];
    uint32_t tex_index = 0;
    for (; tex_index < max_tex; tex_index++) {
        if (![bucket->in_use isSet:tex_index])
            break;
    }
    
    if (!bucket->tex_ids[tex_index]) {
        CGLLockContext(cgl_ctx);
        
        // allocate the texture
        glGenTextures(1, bucket->tex_ids + tex_index); glReportError();
        if (!bucket->tex_ids[tex_index]) {
            CGLUnlockContext(cgl_ctx);
            return 0;
        }
        
        // get the current TEXTURE_RECTANGLE_ARB texture
        GLuint rect_tex;
        glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE_ARB, (GLint*)&rect_tex); glReportError();
        
        // bind it to texture rectangle
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, bucket->tex_ids[tex_index]); glReportError();
        
        // texture parameters
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glReportError();
        
        // disable client storage
        GLenum client_storage = [RXGetContextState(cgl_ctx) setUnpackClientStorage:GL_FALSE];
        
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, bucket->width, bucket->height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL); glReportError();
        
        // restore the texture binding and unpack client storage
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, rect_tex); glReportError();
        [RXGetContextState(cgl_ctx) setUnpackClientStorage:client_storage];
        
        // flush to synchronize the new texture object with the render context
        glFlush();
        
        CGLUnlockContext(cgl_ctx);
        
#if defined(DEBUG)
        RXLog(kRXLoggingGraphics, kRXLoggingLevelDebug, @"allocated brokered texture %u (%ux%u)", bucket->tex_ids[tex_index], bucket->width, bucket->height);
#endif
    }
    
    [bucket->in_use set:tex_index];
    if (out_index)
        *out_index = tex_index;
    return bucket->tex_ids[tex_index];
}

GTMOBJECT_SINGLETON_BOILERPLATE(RXTextureBroker, sharedTextureBroker)

- (void)_createBucketWithSize:(rx_size_t)size {
    if (_bucket_count == _bucket_capacity) {
        _bucket_capacity += 0x10;
        _buckets = realloc(_buckets, _bucket_capacity * sizeof(struct _rx_texture_bucket));
    }
    
    allocate_texture_bucket(cgl_ctx, _buckets + _bucket_count, size.width, size.height);
    _bucket_count++;
}

- (void)_recycleTexture:(RXBrokeredTexture*)texture {
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"recycled texture: %u", texture->texture);
#endif
    [texture->_bucket->in_use clear:texture->_bucket_index];
}

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    cgl_ctx = [g_worldView loadContext];
    
    _buckets = calloc(8, sizeof(struct _rx_texture_bucket));
    _bucket_capacity = 8;
    
    // create a few standard buckets
    for (int i = 5; i < 10; i++)
        for (int j = 5; j < 10; j++)
            [self _createBucketWithSize:RXSizeMake(1 << i, 1 << j)];
    
    [self _createBucketWithSize:kRXCardViewportSize];
    
    return self;
}

- (void)teardown {
    if (_toreDown)
        return;
    _toreDown = YES;
#if defined(DEBUG)
    RXOLog(@"tearing down");
#endif
    
    for (uint32_t bucket_i = 0; bucket_i < _bucket_count; bucket_i++)
        free_texture_bucket(cgl_ctx, _buckets + bucket_i);
    _bucket_count = 0;
    
    [self _printDebugStats];
}

- (void)dealloc {
    [self teardown];
    
    free(_buckets);
#if defined(DEBUG)
    free(_bucket_stats);
#endif
    
    [super dealloc];
}

- (void)_printDebugStats {
#if defined(DEBUG)
    NSMutableString* statsString = [NSMutableString new];
    for (GLuint i = 0; i < _bucket_stat_count; i++)
        [statsString appendFormat:@"\t%dx%d: %u\n", (int)_bucket_stats[i].width, (int)_bucket_stats[i].height, (unsigned int)_bucket_stats[i].count];
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"texture bucket statistics\n%@", statsString);
    [statsString release];
#endif
}

- (RXTexture*)newTextureWithSize:(rx_size_t)size {
    assert(size.width > 0);
    assert(size.height > 0);
    if (_toreDown)
        return nil;
    
    // find the right bucket
    struct _rx_texture_bucket* bucket = NULL;
    
    // this quick index calculation if possbile because of the way the buckets
    // were created in the initializer
    int i = MAX(0, (int)ceilf(log2f(size.width)) - 5);
    int j = MAX(0, (int)ceilf(log2f(size.height)) - 5);
    int32_t bucket_i = MIN((i * 5) + j, 5 * 5);
    
    for (; bucket_i < (int32_t)_bucket_count; bucket_i++) {
        bucket = _buckets + bucket_i;
        if (bucket->width >= size.width && bucket->height >= size.height)
            break;
    }
    
    // if we don't have a bucket for that size, create a custom-fit one
    if (bucket_i == (int32_t)_bucket_count) {
        [self _createBucketWithSize:size];
        bucket = &_buckets[_bucket_count - 1];
    }
    
    // if we don't have a bucket at this point, give up
    if (!bucket)
        return nil;
    
    // try to allocate a texture out of the bucket
    uint32_t bucket_index;
    GLuint texid = find_texture(cgl_ctx, bucket, &bucket_index);
    if (texid == 0) {
        // texture allocation failed, return nil
        return nil;
    }
    
    RXBrokeredTexture* texture = [[RXBrokeredTexture alloc] initWithID:texid target:GL_TEXTURE_RECTANGLE_ARB size:size deleteWhenDone:NO];
    texture->_bucket = bucket;
    texture->_bucket_index = bucket_index;
    
#if defined(DEBUG)
    if (_bucket_stat_count == 0) {
        _bucket_stats = malloc(sizeof(struct _bucket_stat));
        _bucket_stat_count = 1;
        _bucket_stats[0].width = bucket->width;
        _bucket_stats[0].height = bucket->height;
        _bucket_stats[0].count = 0;
    }
    
    uint32_t stat_i = 0;
    for (; stat_i < _bucket_stat_count; stat_i++) {
        if (_bucket_stats[stat_i].width == bucket->width && _bucket_stats[stat_i].height == bucket->height) {
            _bucket_stats[stat_i].count++;
            break;
        }
    }
    
    if (stat_i == _bucket_stat_count) {
        _bucket_stat_count++;
        _bucket_stats = realloc(_bucket_stats, _bucket_stat_count * sizeof(struct _bucket_stat));
        _bucket_stats[stat_i].width = bucket->width;
        _bucket_stats[stat_i].height = bucket->height;
        _bucket_stats[stat_i].count = 1;
    }
#endif
    
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"reserved texture: %u [size=%ux%u] from <%ux%u> bucket [index=%u]",
        texid, size.width, size.height, bucket->width, bucket->height, bucket_index);
#endif
    return texture;
}

- (RXTexture*)newTextureWithWidth:(GLsizei)width height:(GLsizei)height {
    return [self newTextureWithSize:RXSizeMake(width, height)];
}

@end
