//
//  QTCompressionSession.h
//  rivenx
//
//  Created by Jean-François Roy on 20/08/2006.

/*
Copyright (c) 2006 Jean-François Roy
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. The name of the author may not be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <QuartzCore/CoreVideo.h>
#import <QuickTime/QuickTime.h>

@interface QTCompressionSession : NSObject {
  int width;                  // video width
  int height;                 // video height
  CodecType codecType;        // video codec
  SInt32 averageDataRate;     // video data rate
  TimeScale timeScale;        // video time scale
  int desiredFramesPerSecond; // video frames per second
  long frameCount;            // video frame count

  Movie outputMovie;                  // movie file for storing compressed frames
  DataHandler outputMovieDataHandler; // storage for movie header

  Media outputVideoMedia; // media for the video track in the movie
  BOOL didBeginVideoMediaEdits;

  ICMCompressionSessionRef compressionSession; // compresses video frames
  BOOL sessionFinalized;
}

+ (Movie)quicktimeMovieFromTempFile:(DataHandler*)outDataHandler error:(NSError**)error;

- (id)initToTempMovieWithWidth:(int)w height:(int)h timeScale:(TimeScale)ts error:(NSError**)error;

- (OSStatus)compressFrame:(CVPixelBufferRef)frame timeStamp:(NSTimeInterval)timestamp duration:(NSTimeInterval)duration;
- (void)finishOutputMovieToPath:(NSString*)path;

@end
