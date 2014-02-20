//
//  MHKArchiveMovieAdditions.m
//  rivenx
//
//  Created by Jean-Francois Roy on 19/2/14.
//  Copyright (c) 2014 MacStorm. All rights reserved.
//

#import "MHKArchive.h"
#import "MHKErrors.h"
#import "mohawk_libav.h"
#import "Base/RXErrorMacros.h"

@implementation MHKArchive (MHKArchiveMovieAdditions)

struct ArchiveAVIOContext
{
  MHKArchive* archive;
  int64_t position;
  int64_t size;
};

static int ArchiveAVIOContextRead(struct ArchiveAVIOContext* ioc, uint8_t *buf, int buf_size)
{
  ByteCount bytes_read;
  OSErr err = FSReadFork(ioc->archive->forkRef, fsFromStart, ioc->position, buf_size, buf, &bytes_read);
  if (err == eofErr)
    return 0;
  else if (err != noErr)
    return -1;
  ioc->position += bytes_read;
  return bytes_read;
}

static int64_t ArchiveAVIOContextSeek(struct ArchiveAVIOContext* ioc, int64_t offset, int whence)
{
  switch (whence) {
    case SEEK_SET:
      ioc->position = offset;
      break;
    case SEEK_CUR:
      ioc->position += offset;
      break;
    case AVSEEK_SIZE:
      return ioc->size;
    default:
      abort();
  }
  return ioc->position;
}

- (AVFormatContext*)createAVFormatContextWithMovieID:(uint16_t)movieID error:(NSError**)error
{
  mhk_load_libav();

  // get the movie resource descriptor
  NSDictionary* descriptor = [self resourceDescriptorWithResourceType:@"tMOV" ID:movieID];
  if (!descriptor)
    ReturnValueWithError(NULL, MHKErrorDomain, errResourceNotFound, nil, error);

  size_t iobuf_size = 0x1000;
  void* iobuf = g_libav.av_malloc(iobuf_size);

  struct ArchiveAVIOContext* mioc = malloc(sizeof(struct ArchiveAVIOContext));
  mioc->archive = self;
  mioc->position = 0;
  mioc->size = [[descriptor objectForKey:@"Length"] longLongValue];

  AVIOContext* ioc = g_libav.avio_alloc_context(iobuf, iobuf_size, 0, mioc,
    (int (*)(void*, uint8_t*, int))ArchiveAVIOContextRead,
    NULL,
    (int64_t (*)(void*, int64_t, int))ArchiveAVIOContextSeek);

  AVFormatContext* avfc = g_libav.avformat_alloc_context();
  avfc->pb = ioc;

  AVInputFormat* avif = g_libav.av_iformat_next(NULL);
  while (avif) {
    if (strstr(avif->name, "mov") != NULL)
      break;
    avif = g_libav.av_iformat_next(avif);
  }

  g_libav.avio_seek(ioc, [[descriptor objectForKey:@"Offset"] longLongValue], SEEK_SET);
  g_libav.avformat_open_input(&avfc, "", avif, NULL);

  AVDictionary** stream_options = calloc(avfc->nb_streams, sizeof(AVDictionary*));
  g_libav.avformat_find_stream_info(avfc, stream_options);

  return avfc;
}

@end
