/*

File: GLPBOFrameReader.h

Abstract: Declares the interface for the GLPBOFrameReader class which
allows to grab frames from an OpenGL context using PBOs.
The GLPBOFrameReader is initialized with an OpenGL context to read from and
the dimensions of the frames to grab. GLPBOFrameReader will use asynchronous 
texture fetching to grab the frames from the OpenGL context, which introduces 
a one frame latency but provides additional performance. Frame grabbing 
is performed by calling -readFrame which returns a CVPixelBuffer containing 
the frame pixels (which have been vertically flipped to compensate for OpenGL 
bottom-left referential origin).

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

#import <Foundation/Foundation.h>
#import <OpenGL/OpenGL.h>
#import <QuartzCore/CoreVideo.h>

@interface GLPBOFrameReader : NSObject {
	CGLContextObj cgl_ctx;
	
	unsigned _width;
	unsigned _height;
	
	unsigned _bufferRowBytes;
	CVPixelBufferPoolRef _bufferPool;
	GLuint _pixelBuffer;
	
	BOOL _firstRead;
}

- (id)initWithOpenGLContext:(CGLContextObj)context pixelsWide:(unsigned)width pixelsHigh:(unsigned)height;
- (CVPixelBufferRef)copyFrame;

@end
