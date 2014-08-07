// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Base/RXBase.h"
#import "Base/RXErrorMacros.h"

#import "mhk/mohawk_libav.h"

#import "mhk/MHKArchive_Internal.h"
#import "mhk/MHKErrors.h"
#import "mhk/MHKFileHandle_Internal.h"
#import "mhk/MHKLibAVIOContext.h"

@implementation MHKArchive (MHKArchiveMovieAdditions)

- (AVFormatContext*)createAVFormatContextWithMovieID:(uint16_t)movieID error:(NSError**)outError {
  // get the movie resource descriptor
  MHKResourceDescriptor* rdesc = [self resourceDescriptorWithResourceType:@"tMOV" ID:movieID];
  if (!rdesc) {
    ReturnValueWithError(NULL, MHKErrorDomain, errResourceNotFound, nil, outError);
  }

  // create a file handle for the embedded movie file; note that the IO offset is 0 because embedded movie files have
  // absolute references to sample data in the archive
  MHKFileHandle* fh =
      [[MHKFileHandle alloc] initWithArchive:self length:rdesc.length archiveOffset:rdesc.offset ioOffset:0];

  // wrap the file handle in a LibAV IO context
  MHKLibAVIOContext* ioc = [[MHKLibAVIOContext alloc] initWithFileHandle:fh error:outError];
  [fh release];
  if (!ioc) {
    return NULL;
  }

  // allocate and configure the format context
  AVFormatContext* avfc = g_libav.avformat_alloc_context();
  avfc->pb = ioc.avioc;

  // find the QuickTime movie format
  // TODO: cache this
  AVInputFormat* avif = g_libav.av_iformat_next(NULL);
  while (avif) {
    if (strstr(avif->name, "mov") != NULL) {
      break;
    }
    avif = g_libav.av_iformat_next(avif);
  }

  // seek to the beginning of the movie container; this is kind of a hack to allow libav to work with embedded movies
  g_libav.avio_seek(ioc.avioc, rdesc.offset, SEEK_SET);

  // open the movie
  g_libav.avformat_open_input(&avfc, "", avif, NULL);

  // populate the format context with media information
  AVDictionary** stream_options = calloc(avfc->nb_streams, sizeof(AVDictionary*));
  g_libav.avformat_find_stream_info(avfc, stream_options);

  // FIXME: need to keep the IO context alive without just leaking it

  return avfc;
}

@end
