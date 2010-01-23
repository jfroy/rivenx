//
//  RXDynamicPicture.m
//  rivenx
//
//  Created by Jean-Francois Roy on 14/12/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <libkern/OSAtomic.h>

#import "Rendering/Graphics/RXDynamicPicture.h"
#import "Base/RXDynamicBitfield.h"


static BOOL dynamic_picture_system_initialized = NO;

static int32_t dynamic_picture_vertex_bo_picture_capacity = 0;
static int32_t volatile active_dynamic_pictures = 0;
static RXDynamicBitfield* dynamic_picture_allocation_bitmap;

static GLuint dynamic_picture_vao = UINT32_MAX;
static GLuint dynamic_picture_vertex_bo = UINT32_MAX;

static OSSpinLock dynamic_picture_lock = OS_SPINLOCK_INIT;


static void initialize_dynamic_picture_system() {
    if (dynamic_picture_system_initialized)
        return;
    
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    dynamic_picture_vertex_bo_picture_capacity = 20;
    
    glGenBuffers(1, &dynamic_picture_vertex_bo);
    glGenVertexArraysAPPLE(1, &dynamic_picture_vao);
    
    [gl_state bindVertexArrayObject:dynamic_picture_vao];
    
    glBindBuffer(GL_ARRAY_BUFFER, dynamic_picture_vertex_bo); glReportError();
    if (GLEW_APPLE_flush_buffer_range)
        glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
    glBufferData(GL_ARRAY_BUFFER, dynamic_picture_vertex_bo_picture_capacity * 16 * sizeof(GLfloat), NULL, GL_DYNAMIC_DRAW); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_POSITION); glReportError();
    glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (GLvoid*)0); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0); glReportError();
    glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (GLvoid*)(2 * sizeof(GLfloat))); glReportError();
    
    [gl_state bindVertexArrayObject:0];
    
    // we created a new buffer object, so flush
    glFlush();
    
    active_dynamic_pictures = 0;
    dynamic_picture_allocation_bitmap = [RXDynamicBitfield new];
    
    dynamic_picture_system_initialized = YES;
}

static void grow_dynamic_picture_vertex_bo() {
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    // bump capacity by 20
    dynamic_picture_vertex_bo_picture_capacity += 20;
    
    GLuint alternate_bo;
    glGenBuffers(1, &alternate_bo);
    
    // bind the dynamic picture VAO and reconfigure it to use the alternate buffer object
    [gl_state bindVertexArrayObject:dynamic_picture_vao];
    
    // bind the vertex buffer in the alternate slot and re-allocate it to the new capacity
    glBindBuffer(GL_ARRAY_BUFFER, alternate_bo); glReportError();
    if (GLEW_APPLE_flush_buffer_range)
        glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
    glBufferData(GL_ARRAY_BUFFER, dynamic_picture_vertex_bo_picture_capacity * 16 * sizeof(GLfloat), NULL, GL_DYNAMIC_DRAW); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_POSITION); glReportError();
    glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (GLvoid*)0); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0); glReportError();
    glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (GLvoid*)(2 * sizeof(GLfloat))); glReportError();
    
    // map the alternate buffer object write-only
    GLfloat* destination = (GLfloat*)glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY); glReportError();
    
    // bind the primary buffer object and map it read-only
    glBindBuffer(GL_ARRAY_BUFFER, dynamic_picture_vertex_bo); glReportError();
    GLfloat* source = (GLfloat*)glMapBuffer(GL_ARRAY_BUFFER, GL_READ_ONLY); glReportError();
    
    // copy the content of the primary buffer object into the alternate buffer object
    memcpy(destination, source, active_dynamic_pictures * 16 * sizeof(GLfloat));
    
    // unmap the primary buffer object
    glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
    
    // bind the alternate buffer object again, then flush and unmap it
    glBindBuffer(GL_ARRAY_BUFFER, alternate_bo); glReportError();
    if (GLEW_APPLE_flush_buffer_range)
        glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, active_dynamic_pictures * 16 * sizeof(GLfloat));
    glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
    
    // reset the current vao to 0 (Riven X assumption)
    [gl_state bindVertexArrayObject:0];
    
    // scrap the primary buffer object
    glDeleteBuffers(1, &dynamic_picture_vertex_bo);
    
    // we created a new buffer object, so flush
    glFlush();
    
    // the alternate buffer object is now the primary buffer object
    dynamic_picture_vertex_bo = alternate_bo;
}

static GLuint allocate_dynamic_picture_index() {
    if ((active_dynamic_pictures + 1) == dynamic_picture_vertex_bo_picture_capacity)
        grow_dynamic_picture_vertex_bo();
    
    size_t max_picture = [dynamic_picture_allocation_bitmap segmentCount] * [dynamic_picture_allocation_bitmap segmentBits];
    for (uint32_t picture_index = 0; picture_index < max_picture; picture_index++) {
        if (![dynamic_picture_allocation_bitmap isSet:picture_index]) {
            [dynamic_picture_allocation_bitmap set:picture_index];
            active_dynamic_pictures++;
            return picture_index;
        }
    }
    
    // fell off the current end of the dynamic bitfield, so use max_picture
    // which is the next bit in line (this will grow the bitfield)
    [dynamic_picture_allocation_bitmap set:max_picture];
    active_dynamic_pictures++;
    return max_picture;
}

static void free_dynamic_picture_index(GLuint index) {
    [dynamic_picture_allocation_bitmap clear:index];
    active_dynamic_pictures--;
}

@implementation RXDynamicPicture

+ (GLuint)sharedDynamicPictureUnpackBuffer {
    static GLuint dynamic_picture_unpack_buffer = 0;
    if (dynamic_picture_unpack_buffer)
        return dynamic_picture_unpack_buffer;
    
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    CGLLockContext(cgl_ctx);
    
    // create a buffer object in which to decompress dynamic pictures, which at most can be the size of the card viewport
    glGenBuffers(1, &dynamic_picture_unpack_buffer); glReportError();
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, dynamic_picture_unpack_buffer); glReportError();
    if (GLEW_APPLE_flush_buffer_range)
        glBufferParameteriAPPLE(GL_PIXEL_UNPACK_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, 1024 * 1024 * 4, NULL, GL_DYNAMIC_DRAW); glReportError();
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    
    // we created a new buffer object, so flush
    glFlush();
    
    CGLUnlockContext(cgl_ctx);
    
    return dynamic_picture_unpack_buffer;
}

- (id)initWithTexture:(RXTexture*)texture samplingRect:(NSRect)sampling_rect renderRect:(NSRect)render_rect owner:(id)owner {
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    CGLLockContext(cgl_ctx);
    
    if (!dynamic_picture_system_initialized)
        initialize_dynamic_picture_system();
    
    OSSpinLockLock(&dynamic_picture_lock);
    
    GLuint index = allocate_dynamic_picture_index();
    
    glBindBuffer(GL_ARRAY_BUFFER, dynamic_picture_vertex_bo); glReportError();
    GLfloat* vertex_attributes = (GLfloat*)BUFFER_OFFSET(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY), index * 16 * sizeof(GLfloat)); glReportError();
    
    // 4 vertices per picture [<position.x position.y> <texcoord0.s texcoord0.t>], floats, triangle strip primitives
    // vertex 1
    vertex_attributes[0] = render_rect.origin.x;
    vertex_attributes[1] = render_rect.origin.y;
    
    vertex_attributes[2] = sampling_rect.origin.x;
    vertex_attributes[3] = sampling_rect.origin.y + sampling_rect.size.height;
    
    // vertex 2
    vertex_attributes[4] = render_rect.origin.x + render_rect.size.width;
    vertex_attributes[5] = render_rect.origin.y;
    
    vertex_attributes[6] = sampling_rect.origin.x + sampling_rect.size.width;
    vertex_attributes[7] = sampling_rect.origin.y + sampling_rect.size.height;
    
    // vertex 3
    vertex_attributes[8] = render_rect.origin.x;
    vertex_attributes[9] = render_rect.origin.y + render_rect.size.height;
    
    vertex_attributes[10] = sampling_rect.origin.x;
    vertex_attributes[11] = sampling_rect.origin.y;
    
    // vertex 4
    vertex_attributes[12] = render_rect.origin.x + render_rect.size.width;
    vertex_attributes[13] = render_rect.origin.y + render_rect.size.height;
    
    vertex_attributes[14] = sampling_rect.origin.x + sampling_rect.size.width;
    vertex_attributes[15] = sampling_rect.origin.y;
    
    if (GLEW_APPLE_flush_buffer_range)
        glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, index * 16 * sizeof(GLfloat), 16);
    glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    OSSpinLockUnlock(&dynamic_picture_lock);
    CGLUnlockContext(cgl_ctx);
    
    self = [super initWithTexture:texture vao:dynamic_picture_vao index:index << 2 owner:owner];
    if (!self)
        return nil;
    
    return self;
}

- (void)dealloc {
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"deallocating");
#endif
    
    if (_index != UINT32_MAX) {
        OSSpinLockLock(&dynamic_picture_lock);
        free_dynamic_picture_index(_index >> 2);
        OSSpinLockUnlock(&dynamic_picture_lock);
    }
    
    [super dealloc];
}

- (void)render:(const CVTimeStamp*)output_time inContext:(CGLContextObj)cgl_ctx framebuffer:(GLuint)fbo {
    OSSpinLockLock(&dynamic_picture_lock);
    [super render:output_time inContext:cgl_ctx framebuffer:fbo];
    OSSpinLockUnlock(&dynamic_picture_lock);
}

@end
