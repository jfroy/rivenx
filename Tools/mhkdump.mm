// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <cstdio>
#import <cstdlib>

#import <vector>

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>

#import "Base/RXBase.h"

#import "Rendering/Audio/PublicUtility/AUOutputBL.h"
#import "Rendering/Audio/PublicUtility/CAAudioBufferList.h"
#import "Rendering/Audio/PublicUtility/CAAudioChannelLayout.h"
#import "Rendering/Audio/PublicUtility/CAExtAudioFile.h"
#import "Rendering/Audio/PublicUtility/CAStreamBasicDescription.h"

static void ExportSound(MHKArchive* archive, NSString* filename, MHKResourceDescriptor* rdesc) {
    NSError* error;
  id<MHKAudioDecompression> decompressor = [archive decompressorWithSoundID:rdesc.ID error:&error];
  if (!decompressor) {
    fprintf(stderr, "... %s: failed to get decompressor\n    %s",
            [filename UTF8String],
            [[error localizedDescription] UTF8String]);
    return;
  }

  const AudioStreamBasicDescription* output_asbd = decompressor.outputFormat;

  CAStreamBasicDescription sbd(output_asbd->mSampleRate, output_asbd->mChannelsPerFrame, CAStreamBasicDescription::kPCMFormatInt16, true);
  CAAudioChannelLayout acl(kAudioChannelLayoutTag_Stereo);

  CAExtAudioFile eaf;
  eaf.Create([[filename stringByAppendingPathExtension:@"caf"] UTF8String], kAudioFileCAFType, sbd, acl, kAudioFileFlags_EraseFile);
  eaf.SetClientFormat(*output_asbd);

  AUOutputBL abl(*output_asbd);
  abl.Allocate(decompressor.framesPerPacket);
  abl.Prepare();

  int loops = 2;

  while (true) {
    uint32_t frames = [decompressor fillAudioBufferList:abl.ABL()];
    if (frames <= 0) {
      if (--loops == 0) {
        break;
      }
      [decompressor reset];
      continue;
    }
    eaf.Write(frames, abl.ABL());
  }

  eaf.Close();
}

static void DumpSounds(MHKArchive* archive) {
  printf("dumping sounds\n");
  NSArray* resources = [archive resourceDescriptorsForType:@"tWAV"];
  for (MHKResourceDescriptor* rdesc in resources) {
    NSMutableString* filename = [NSMutableString new];
    [filename appendFormat:@"%u", rdesc.ID];
    if (rdesc.name) {
      [filename appendFormat:@" - %@", rdesc.name];
    }

    NSError* error;
    MHKSoundDescriptor* sdesc = [archive soundDescriptorWithID:rdesc.ID error:&error];
    if (!sdesc) {
      fprintf(stderr, "... %s: failed to get sound descriptor\n    %s",
              [filename UTF8String],
              [[error localizedDescription] UTF8String]);
      continue;
    }

    int compression_type = sdesc.compressionType;
    NSString* extension = @"";
    if (compression_type == MHK_WAVE_ADPCM) {
      extension = @"adpcm";
    } else if (compression_type ==  MHK_WAVE_MP2) {
      extension = @"mp2";
    }

    printf("... %s.%s ->\n"
           "    sample rate: %u\n"
           "    frame count: %llu\n"
           "    channel count: %u\n",
          [filename UTF8String],
          [extension UTF8String],
          sdesc.sampleRate,
          sdesc.frameCount,
          sdesc.channelCount);

    MHKFileHandle* fh = [archive openSoundWithID:rdesc.ID error:nullptr];
    NSData* data = [fh readDataToEndOfFile:nullptr];
    [data writeToFile:[filename stringByAppendingPathExtension:extension] options:0 error:nullptr];

    ExportSound(archive, filename, rdesc);
  }
  printf("\n");
}

int main(int argc, const char* argv[]) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <archive>\n", argv[0]);
    exit(1);
  }

  NSString* path = [[[NSFileManager new] stringWithFileSystemRepresentation:argv[1] length:strlen(argv[1])] stringByStandardizingPath];
  NSError* error;
  MHKArchive* archive = [[MHKArchive alloc] initWithPath:path error:&error];
  if (!archive) {
    fprintf(stderr, "failed to open archive: %s\n", [[error description] UTF8String]);
    exit(1);
  }

  DumpSounds(archive);
}
