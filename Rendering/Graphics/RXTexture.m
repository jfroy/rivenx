//
//  RXTexture.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/08/2009.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Rendering/Graphics/RXTexture.h"
#import "Rendering/Graphics/RXDynamicPicture.h"

@implementation RXTexture

+ (RXTexture*)newStandardTextureWithTarget:(GLenum)target size:(rx_size_t)s context:(CGLContextObj)cgl_ctx lock:(BOOL)lock
{
  if (lock)
    CGLLockContext(cgl_ctx);

  GLuint texid;
  glGenTextures(1, &texid);

  RXTexture* texture = [[RXTexture alloc] initWithID:texid target:target size:s deleteWhenDone:YES];
  if (!texture) {
    if (lock)
      CGLUnlockContext(cgl_ctx);
    return nil;
  }

  [texture bindWithContext:cgl_ctx lock:NO];

  // texture parameters
  glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glReportError();

  GLenum client_storage = [RXGetContextState(cgl_ctx) setUnpackClientStorage:GL_FALSE];

  glTexImage2D(target, 0, GL_RGBA8, s.width, s.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);

  [RXGetContextState(cgl_ctx) setUnpackClientStorage:client_storage];

  // flush to synchronize the new texture object with the rendering context
  glFlush();

  if (lock)
    CGLUnlockContext(cgl_ctx);

  return texture;
}

- (id)init
{
  [self doesNotRecognizeSelector:_cmd];
  [self release];
  return nil;
}

- (id)initWithID:(GLuint)texid target:(GLenum)t size:(rx_size_t)s deleteWhenDone:(BOOL)dwd
{
  self = [super init];
  if (!self)
    return nil;

  texture = texid;
  target = t;
  size = s;

  _delete_when_done = dwd;

  return self;
}

- (NSString*)description { return [NSString stringWithFormat:@"%@ {texture=%u, delete_when_done=%d}", [super description], texture, _delete_when_done]; }

- (void)dealloc
{
#if defined(DEBUG)
  RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"deallocating");
#endif

  if (_delete_when_done) {
    CGLContextObj cgl_ctx = [g_worldView loadContext];
    CGLLockContext(cgl_ctx);
    glDeleteTextures(1, &texture);
    CGLUnlockContext(cgl_ctx);
  }

  [super dealloc];
}

- (void)bindWithContext:(CGLContextObj)cgl_ctx lock:(BOOL)lock
{
  if (lock)
    CGLLockContext(cgl_ctx);
  glBindTexture(target, texture);
  glReportError();
  if (lock)
    CGLUnlockContext(cgl_ctx);
}

- (void)updateWithBitmap:(uint16_t)tbmp_id archive:(MHKArchive*)archive
{
  // get the resource descriptor for the tBMP resource
  NSError* error;
  NSDictionary* picture_descriptor = [archive bitmapDescriptorWithID:tbmp_id error:&error];
  if (!picture_descriptor)
    @throw [NSException exceptionWithName:@"RXPictureLoadException"
                                   reason:@"Could not get a picture resource's picture descriptor."
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];

  GLsizei picture_width = [[picture_descriptor objectForKey:@"Width"] intValue];
  GLsizei picture_height = [[picture_descriptor objectForKey:@"Height"] intValue];

  // compute the size of the buffer needed to store the texture; we'll be using
  // MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED as the texture format, which is 4 bytes per pixel
  GLsizeiptr picture_size = picture_width * picture_height * 4;

#if defined(DEBUG)
  NSString* archive_key = [[[[archive url] path] lastPathComponent] stringByDeletingPathExtension];
  RXLog(kRXLoggingGraphics, kRXLoggingLevelDebug, @"updating %@ with picture %@:%hu", self, archive_key, tbmp_id);
#endif

  // get the load context and lock it
  CGLContextObj cgl_ctx = [g_worldView loadContext];
  CGLLockContext(cgl_ctx);

  // bind and map the dynamic picture unpack buffer
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, [RXDynamicPicture sharedDynamicPictureUnpackBuffer]);
  glReportError();
  GLvoid* picture_buffer = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY);
  glReportError();

  // load the picture
  if (![archive loadBitmapWithID:tbmp_id buffer:picture_buffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error])
    @throw [NSException exceptionWithName:@"RXPictureLoadException"
                                   reason:@"Could not load a picture resource."
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];

  // unmap the unpack buffer
  glFlushMappedBufferRangeAPPLE(GL_PIXEL_UNPACK_BUFFER, 0, picture_size);
  glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
  glReportError();

  // create a texture object and bind it
  [self bindWithContext:cgl_ctx lock:NO];

  // texture parameters
  glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glReportError();

  // client storage is not compatible with PBO texture unpacking
  GLenum client_storage = [RXGetContextState(cgl_ctx) setUnpackClientStorage:GL_FALSE];

  // unpack the texture
  glTexSubImage2D(target, 0, 0, 0, picture_width, picture_height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, BUFFER_OFFSET((void*)NULL, 0));
  glReportError();

  // reset the unpack buffer binding and restore unpack client storage
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  glReportError();
  [RXGetContextState(cgl_ctx) setUnpackClientStorage:client_storage];

  // flush the update to synchronize it with the render context
  glFlush();

  // unlock the load context
  CGLUnlockContext(cgl_ctx);
}

- (void)updateWithBitmap:(uint16_t)tbmp_id stack:(RXStack*)stack
{
  MHKArchive* archive = [[stack fileWithResourceType:@"tBMP" ID:tbmp_id] archive];
  [self updateWithBitmap:tbmp_id archive:archive];
}

@end
