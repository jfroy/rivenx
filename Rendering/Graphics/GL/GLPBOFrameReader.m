/*

File: GLPBOFrameReader.m

Abstract: Implements the GLPBOFrameReader class.

Version: 1.1

Version 1.1 Disclaimer:

Original FrameReader class modified to used PBOs by Jean-Francois Roy.

Copyright © 2006 Jean-Francois Roy. Released under the 1.0 terms, with
the following additional clause.

This software is provided by Jean-Francois Roy on an "AS IS" basis.	 
JEAN-FRANCOIS ROY MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING 
WITHOUT LIMITATION THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, 
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, REGARDING THE 
SOFTWARE OR ITS USE AND OPERATION ALONE OR IN COMBINATION WITH 
YOUR PRODUCTS.

IN NO EVENT SHALL JEAN-FRANCOIS ROY BE LIABLE FOR ANY SPECIAL, INDIRECT, 
INCIDENTAL OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
OR BUSINESS INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF JEAN-FRANCOIS ROY HAS BEEN ADVISED OF 
THE POSSIBILITY OF SUCH DAMAGE.

Version 1.0 Disclaimer:

IMPORTANT:	This Apple software is supplied to you by Apple
Computer, Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.	If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software. 
Neither the name, trademarks, service marks or logos of Apple Computer,
Inc. may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.	Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright © 2005 Apple Computer, Inc., All Rights Reserved

*/

#import <OpenGL/CGLMacro.h>

#import "GLPBOFrameReader.h"


@implementation GLPBOFrameReader

- (id)init {
	// Make sure client goes through designated initializer
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithOpenGLContext:(CGLContextObj)context pixelsWide:(unsigned)width pixelsHigh:(unsigned)height {
	// Check parameters
	if (context == nil || width == 0 || height == 0) {
		[self release];
		return nil;
	}
	
	self = [super init];
	if (!self) return nil;
	
	// This will allow using CGMacro anywhere in the class
	cgl_ctx = context;
	
	// Keep essential parameters around
	_width = width;
	_height = height;
	
	// Create a pixel buffer - Make sure the buffer is is a multiple of 64 for performance reasons
	_bufferRowBytes = _width * 4;
	glGenBuffers(1, &_pixelBuffer);
	glBindBuffer(GL_PIXEL_PACK_BUFFER_ARB, _pixelBuffer);
	glBufferData(GL_PIXEL_PACK_BUFFER_ARB, _height * ((_bufferRowBytes + 63) & ~63), NULL, GL_STREAM_READ);
	
	// Check for OpenGL errors
	CVReturn err = glGetError();
	if (err) {
		NSLog(@"OpenGL buffer creation failed (error 0x%04X)", err);
		[self release];
		return nil;
	}
	
	// Determine the format based on the architecture's native byte order
#if defined(__BIG_ENDIAN__)
	int pixel_format = k32ARGBPixelFormat;
#else
	int pixel_format = k32BGRAPixelFormat;
#endif
	
	// Create buffer pool
	NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
	[attributes setObject:[NSNumber numberWithUnsignedInt:pixel_format] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
	[attributes setObject:[NSNumber numberWithUnsignedInt:width] forKey:(NSString*)kCVPixelBufferWidthKey];
	[attributes setObject:[NSNumber numberWithUnsignedInt:height] forKey:(NSString*)kCVPixelBufferHeightKey];
	err = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (CFDictionaryRef)attributes, &_bufferPool);
	if (err) {
		NSLog(@"CVPixelBufferPoolCreate() failed with error %i", err);
		[self release];
		return nil;
	}
	
	_firstRead = YES;
	
	return self;
}

- (void)dealloc {
	// Destroy resources
	if (_bufferPool) CVPixelBufferPoolRelease(_bufferPool);
	if (_pixelBuffer) glDeleteBuffers(1, &_pixelBuffer);
	
	[super dealloc];
}

- (CVPixelBufferRef)copyFrame {
	CVPixelBufferRef pixelBufferRef = NULL;
	
	// Bind the GL pixel buffer and FBO 0
	glBindBuffer(GL_PIXEL_PACK_BUFFER_ARB, _pixelBuffer);
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
	
	// If it's our first read, skip frame processing and go to readback
	if(_firstRead) {
		_firstRead = NO;
		goto readback;
	}
	
	// Get pixel buffer from pool
	CVReturn err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _bufferPool, &pixelBufferRef);
	if(err) {
		NSLog(@"CVPixelBufferPoolCreatePixelBuffer() failed with error %i", err);
		return NULL;
	}
	
	// Lock pixel buffer bits
	err = CVPixelBufferLockBaseAddress(pixelBufferRef, 0);
	if(err) {
		NSLog(@"CVPixelBufferLockBaseAddress() failed with error %i", err);
		return NULL;
	}
	
	// Map the CV pixel buffer
	unsigned char* baseCVAddress = CVPixelBufferGetBaseAddress(pixelBufferRef);
	unsigned rowbytes = CVPixelBufferGetBytesPerRow(pixelBufferRef);
	
	// Map the GL pixel buffer
	unsigned char* baseGLAddress = glMapBuffer(GL_PIXEL_PACK_BUFFER_ARB, GL_READ_ONLY);
	
	// Copy image to pixel buffer vertically flipped - OpenGL copies pixels upside-down
	unsigned i;
	for (i = 0; i < _height; ++i) {
		unsigned char* src = baseGLAddress + _bufferRowBytes * i;
		unsigned char* dst = baseCVAddress + rowbytes * (_height - 1 - i);
		bcopy(src, dst, _width * 4);
	}
	
	// Unmap the GL pixel buffer
	glUnmapBuffer(GL_PIXEL_PACK_BUFFER_ARB);
	
	// Unlock the CV pixel buffer
	CVPixelBufferUnlockBaseAddress(pixelBufferRef, 0);
	
readback:
	// Initiate async readback for the next round
	glReadPixels(0, 0, _width, _height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, BUFFER_OFFSET(0));
	
	return pixelBufferRef;
}

@end
