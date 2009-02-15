//
//	MHKAudioDecompression.h
//	MHKKit
//
//	Created by Jean-Francois Roy on 07/11/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <CoreAudio/CoreAudioTypes.h>
#import <Foundation/NSObject.h>


@protocol MHKAudioDecompression <NSObject>
- (AudioStreamBasicDescription)outputFormat;
- (SInt64)frameCount;

- (void)reset;
- (void)fillAudioBufferList:(AudioBufferList*)abl;
@end
