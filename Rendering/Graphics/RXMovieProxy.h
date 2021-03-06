//
//  RXMovieProxy.h
//  rivenx
//
//  Created by Jean-Francois Roy on 26/03/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <MHKKit/MHKArchive.h>

#import "Rendering/Graphics/RXMovie.h"

@interface RXMovieProxy : NSObject {
  id _owner;

  MHKArchive* _archive;
  uint16_t _ID;

  float _volume;
  BOOL _loop;
  CGPoint _origin;

  RXMovie* _movie;
}

- (id)initWithArchive:(MHKArchive*)archive ID:(uint16_t)ID origin:(CGPoint)origin volume:(float)volume loop:(BOOL)loop owner:(id)owner;

- (MHKArchive*)archive;
- (uint16_t)ID;

- (RXMovie*)proxiedMovie;
- (void)restoreMovieVolume;

- (void)deleteMovie;

@end
