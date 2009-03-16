//
//	RXMovie.h
//	rivenx
//
//	Created by Jean-Francois Roy on 08/09/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <QuickTime/QuickTime.h>
#import <QTKit/QTKit.h>

#import "Rendering/RXRendering.h"


extern NSString* const RXMoviePlaybackDidEndNotification;

@interface RXMovie : NSObject <RXRenderingProtocol> {
	__weak id _owner;
	
	QTMovie* _movie;
	QTVisualContextRef _vc;
	
	long _hints;
	CGSize _current_size;
	QTTime _original_duration;
	
	BOOL _seamless_looping_hacked;
	
	GLuint _vao;
	GLfloat _coordinates[16];
	CGRect _render_rect;
	
	GLuint _glTexture;
	void* _texture_storage;
	
	CVImageBufferRef _image_buffer;
}

- (id)initWithMovie:(Movie)movie disposeWhenDone:(BOOL)disposeWhenDone owner:(id)owner;
- (id)initWithURL:(NSURL*)movieURL owner:(id)owner;

- (id)owner;

- (CGSize)currentSize;
- (QTTime)duration;

- (BOOL)looping;
- (void)setLooping:(BOOL)flag;

- (float)volume;
- (void)setVolume:(float)volume;

- (BOOL)isPlayingSelection;
- (void)setPlaybackSelection:(QTTimeRange)selection;
- (void)clearPlaybackSelection;

- (void)setExpectedReadAheadFromDisplayLink:(CVDisplayLinkRef)displayLink;

- (void)setWorkingColorSpace:(CGColorSpaceRef)colorspace;
- (void)setOutputColorSpace:(CGColorSpaceRef)colorspace;

- (CGRect)renderRect;
- (void)setRenderRect:(CGRect)rect;

- (void)play;
- (void)stop;
- (float)rate;

- (void)reset;

@end
