//
//  RXTextureManager.m
//  rivenx
//
//  Created by Jean-Francois Roy on 8/11/07.
//  Copyright 2007 MacStorm All rights reserved.
//

#import "Rendering/Graphics/RXTextureBroker.h"
#import "Utilities/GTMObjectSingleton.h"


@interface RXBrokeredTexture : RXTexture {
@public
    int32_t _bucket;
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
    bzero(bucket->tex_ids, RX_TEXTURE_BUCKET_LENGTH * sizeof(GLuint));
    bucket->width = width;
    bucket->height = height;
    bucket->in_use = 0;
}

static inline void free_texture_bucket(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket) {
    assert(bucket);
    
    CGLLockContext(cgl_ctx);
    for (uint32_t tex_index = 0; tex_index < RX_TEXTURE_BUCKET_LENGTH; tex_index++) {
        if (bucket->tex_ids[tex_index])
            glDeleteTextures(1, bucket->tex_ids + tex_index);
    }
    CGLUnlockContext(cgl_ctx);
    
    bzero(bucket->tex_ids, RX_TEXTURE_BUCKET_LENGTH * sizeof(GLuint));
    bucket->in_use = 0;
}

static inline GLuint find_texture(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket) {
    assert(bucket);
    
    // return 0 if there are no free textures
    if (bucket->in_use == UINT32_MAX)
        return 0;
    
    // find the first available texture
    uint32_t tex_index = 0;
    for (; tex_index < RX_TEXTURE_BUCKET_LENGTH; tex_index++) {
        if (!(bucket->in_use & (1U << tex_index)))
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
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE); glReportError();
        
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, bucket->width, bucket->height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL); glReportError();
        
        // restore the rect texture binding and client storage
        glBindTexture(GL_TEXTURE_BINDING_RECTANGLE_ARB, rect_tex); glReportError();
        glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); glReportError();
        
        // create a new texture object, so flush
        glFlush();
        
        CGLUnlockContext(cgl_ctx);
        
#if defined(DEBUG)
        RXLog(kRXLoggingRendering, kRXLoggingLevelDebug, @"allocated texture %u (%ux%u)", bucket->tex_ids[tex_index], bucket->width, bucket->height);
#endif
    }
    
    bucket->in_use |= (1U << tex_index);
    return bucket->tex_ids[tex_index];
}

static inline void free_texture(CGLContextObj cgl_ctx, struct _rx_texture_bucket* bucket, GLuint texture_id) {
    assert(bucket);
    assert(texture_id != 0);
    
    for (uint32_t tex_index = 0; tex_index < RX_TEXTURE_BUCKET_LENGTH; tex_index++) {
        if (bucket->tex_ids[tex_index] == texture_id) {
            bucket->in_use &= ~(1U << tex_index);
            return;
        }
    }
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
    free_texture(cgl_ctx, _buckets + texture->_bucket, texture->texture);
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
    int32_t bucket = 0;
    for (; bucket < (int32_t)_bucket_count; bucket++) {
        if (_buckets[bucket].width == size.width && _buckets[bucket].height == size.height)
            break;
    }
    
    // maybe we don't have a bucket for that size?
    if (bucket == (int32_t)_bucket_count)
        [self _createBucketWithSize:size];
    
    // try to allocate a texture out of the bucket
    GLuint texid = find_texture(cgl_ctx, _buckets + bucket);
    if (texid == 0) {
        if ((_buckets + bucket)->in_use == UINT32_MAX) {
            // bucket is full, create another
            [self _createBucketWithSize:size];
            
            bucket = _bucket_count - 1;
            texid = find_texture(cgl_ctx, _buckets + bucket);
        } else {
            // texture allocation failed, return nil
            return nil;
        }
    }
    
    RXBrokeredTexture* texture = [[RXBrokeredTexture alloc] initWithID:texid target:GL_TEXTURE_RECTANGLE_ARB size:size deleteWhenDone:NO];
    
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
    RXOLog2(kRXLoggingRendering, kRXLoggingLevelDebug, @"reserved texture: %u (%ux%u)", texid, size.width, size.height);
#endif
    return texture;
}

- (RXTexture*)newTextureWithWidth:(GLsizei)width height:(GLsizei)height {
    return [self newTextureWithSize:RXSizeMake(width, height)];
}

@end
