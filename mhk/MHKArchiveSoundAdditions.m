// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "Base/RXBase.h"
#import "Base/RXErrorMacros.h"

#import "mhk/mohawk_sound.h"

#import "mhk/MHKArchive_Internal.h"
#import "mhk/MHKArchiveMediaInterface.h"
#import "mhk/MHKErrors.h"
#import "mhk/MHKFileHandle_Internal.h"

#import "mhk/MHKLibAVAudioDecompressor.h"

@implementation MHKSoundDescriptor {
 @package
  off_t _samplesOffset;
  off_t _samplesLength;
  uint64_t _frameCount;
  uint16_t _sampleRate;
  uint16_t _compressionType;
  uint8_t _sampleDepth;
  uint8_t _channelCount;
}
@end

@implementation MHKArchive (MHKArchiveSoundAdditions)

- (MHKSoundDescriptor*)soundDescriptorWithID:(uint16_t)soundID error:(NSError**)outError {
  // check for a cached descriptor
  MHKSoundDescriptor* sdesc = _sdescs[@(soundID)];
  if (sdesc) {
    return sdesc;
  }

  // get the sound resource descriptor
  MHKResourceDescriptor* rdesc = [self resourceDescriptorWithResourceType:@"tWAV" ID:soundID];
  if (!rdesc) {
    ReturnValueWithError(nil, MHKErrorDomain, errResourceNotFound, nil, outError);
  }

  // seek to the sound resource then seek to the data chunk
  const off_t resource_offset = rdesc.offset;
  off_t file_offset = resource_offset;
  ssize_t bytes_read;

  // cache the end-of-file for the sound resource
  off_t resource_eof = resource_offset + rdesc.length;

  // standard chunk header
  MHK_chunk_header mhk_chunk_header;

  // we need to have a standard MHWK chunk first
  bytes_read = pread(_fd, &mhk_chunk_header, sizeof(MHK_chunk_header), file_offset);
  if (bytes_read < (ssize_t)sizeof(MHK_chunk_header)) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }
  file_offset += bytes_read;

  // handle byte order and check header
  MHK_chunk_header_fton(&mhk_chunk_header);
  if (mhk_chunk_header.signature != MHK_MHWK_signature_integer) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }

  // consistency check
  if (mhk_chunk_header.content_length + sizeof(MHK_chunk_header) > (size_t)rdesc.length) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }

  // must have the WAVE signature next
  uint32_t wave_signature;
  bytes_read = pread(_fd, &wave_signature, sizeof(uint32_t), file_offset);
  if (bytes_read < (ssize_t)sizeof(uint32_t)) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }
  file_offset += bytes_read;
  if (wave_signature != MHK_WAVE_signature_integer) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }

  // loop until we find the Data chunk or we exceed the limits of this resource
  MHK_chunk_header wav_chunk_header;
  do {
    // read a chunk header structure
    bytes_read = pread(_fd, &wav_chunk_header, sizeof(MHK_chunk_header), file_offset);
    if (bytes_read < (ssize_t)sizeof(MHK_chunk_header)) {
      ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
    }
    MHK_chunk_header_fton(&wav_chunk_header);

    // if this is the Data chunk, bail out
    if (wav_chunk_header.signature == MHK_Data_signature_integer) {
      break;
    }

    // advance the position to the next chunk
    file_offset += wav_chunk_header.content_length + sizeof(MHK_chunk_header);
  } while (file_offset < resource_eof);

  // if we didn't find the Data chunk, bail out
  if (wav_chunk_header.signature != MHK_Data_signature_integer) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }

  // move past the Data chunk header
  file_offset += sizeof(MHK_chunk_header);

  // read the Data chunk content header
  MHK_WAVE_Data_header data_header;
  bytes_read = pread(_fd, &data_header, sizeof(MHK_WAVE_Data_header), file_offset);
  if (bytes_read < (ssize_t)sizeof(MHK_WAVE_Data_header)) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }
  file_offset += bytes_read;
  MHK_WAVE_Data_header_fton(&data_header);

  // file_offset is now at the beginning of the sample data
  off_t samples_offset = file_offset;

  // sample data takes the rest of the Data chunk
  // NOTE: for whatever reason, the Data chunk's content_length *includes* the chunk header size
  ssize_t samples_length =
      wav_chunk_header.content_length - (sizeof(MHK_chunk_header) + sizeof(MHK_WAVE_Data_header));

  // consistency checks
  if (samples_offset + samples_length > resource_eof) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }
  if (data_header.compression_type == MHK_WAVE_ADPCM &&
      samples_length != data_header.frame_count * data_header.channel_count / 2) {
    ReturnValueWithError(nil, MHKErrorDomain, errDamagedResource, nil, outError);
  }

#if defined(DEBUG) && DEBUG > 2
  fprintf(stderr, "samples offset: 0x%qx\n", samples_offset);
  fprintf(stderr, "sample rate: %u, frames: %u, bit depth: %d, channels: %d, compression: %u\n",
          data_header.sampling_rate, data_header.frame_count, data_header.bit_depth,
          data_header.channel_count, data_header.compression_type);
#endif

  // create, cache and return the sound descriptor
  sdesc = [MHKSoundDescriptor new];
  sdesc->_samplesOffset = samples_offset;
  sdesc->_samplesLength = samples_length;
  sdesc->_sampleRate = data_header.sampling_rate;
  sdesc->_sampleDepth = data_header.bit_depth;
  sdesc->_frameCount = data_header.frame_count;
  sdesc->_channelCount = data_header.channel_count;
  sdesc->_compressionType = data_header.compression_type;

  _sdescs[@(soundID)] = sdesc;

  return [sdesc autorelease];
}

- (MHKFileHandle*)openSoundWithID:(uint16_t)soundID error:(NSError**)outError {
  MHKSoundDescriptor* sdesc = [self soundDescriptorWithID:soundID error:outError];
  if (!sdesc) {
    return nil;
  }
  return [[[MHKFileHandle alloc] initWithArchive:self
                                          length:sdesc.samplesLength
                                   archiveOffset:sdesc.samplesOffset
                                        ioOffset:sdesc.samplesOffset] autorelease];
}

- (id<MHKAudioDecompression>)decompressorWithSoundID:(uint16_t)soundID error:(NSError**)outError {
  MHKSoundDescriptor* sdesc = [self soundDescriptorWithID:soundID error:outError];
  if (!sdesc) {
    return nil;
  }

  // open a MHK file handle for the decompressor
  MHKFileHandle* fh = [self openSoundWithID:soundID error:outError];
  if (!fh) {
    return nil;
  }

  // create and return a decompressor
  return [[[MHKLibAVAudioDecompressor alloc] initWithSoundDescriptor:sdesc
                                                          fileHandle:fh
                                                               error:outError] autorelease];
}

@end
