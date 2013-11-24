/*
 *  RXCardAudioSource_test.m
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 27/03/2006.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#import <sysexits.h>
#import <fcntl.h>
#import <unistd.h>

#import <AudioToolbox/ExtendedAudioFile.h>
#import <Foundation/NSAutoreleasePool.h>

#import <MHKKit/MHKAudioDecompression.h>

#import "Base/RXBase.h"

#import "Base/RXThreadUtilities.h"
#import "Base/RXLogging.h"

#import "Rendering/Audio/PublicUtility/CAPThread.h"
#import "Rendering/Audio/PublicUtility/CAGuard.h"

#import "Rendering/Audio/RXAudioRenderer.h"
#import "Rendering/Audio/RXCardAudioSource.h"

using namespace RX;

@interface EAFDecompressor : NSObject <MHKAudioDecompression> {
  ExtAudioFileRef audioFile;
  UInt32 clientBytesPerFrame;
}

- (id)initWithSystemPath:(const char*)syspath;

@end

@implementation EAFDecompressor

- (id)initWithSystemPath:(const char*)syspath
{
  self = [super init];
  if (!self)
    return nil;

  if (!syspath) {
    [self release];
    return nil;
  }

  RXOLog(@"opening %s", syspath);
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8*)syspath, strlen(syspath), false);
  assert(ExtAudioFileOpenURL(url, &audioFile) == noErr);
  CFRelease(url);

  AudioStreamBasicDescription file_asbd;
  UInt32 prop_size = sizeof(AudioStreamBasicDescription);
  assert(ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &prop_size, &file_asbd) == noErr);

  // set client format to canonical + interleaved
  CAStreamBasicDescription clientFormat;
  clientFormat.mSampleRate = 44100.0;
  clientFormat.SetCanonical(file_asbd.mChannelsPerFrame, true);
  assert(ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &clientFormat) == noErr);

  clientBytesPerFrame = [self outputFormat].mBytesPerFrame;
  assert(clientBytesPerFrame > 0);

  RXOLog(@"%u bpf, %lld frames", (unsigned int)clientBytesPerFrame, [self frameCount]);
  return self;
}

- (void)dealloc
{
  if (audioFile)
    ExtAudioFileDispose(audioFile);

  [super dealloc];
}

- (AudioStreamBasicDescription)outputFormat
{
  AudioStreamBasicDescription asbd;
  UInt32 size = sizeof(AudioStreamBasicDescription);
  ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, &size, &asbd);
  return asbd;
}

- (SInt64)frameCount
{
  SInt64 frames;
  UInt32 size = sizeof(SInt64);
  ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &size, &frames);
  return frames;
}

- (void)reset { ExtAudioFileSeek(audioFile, 0); }

- (void)fillAudioBufferList:(AudioBufferList*)abl
{
  UInt32 frames = abl->mBuffers[0].mDataByteSize / clientBytesPerFrame;
  ExtAudioFileRead(audioFile, &frames, abl);
}

@end

void* source_task_thread(void* context)
{
  CardAudioSource* source = reinterpret_cast<CardAudioSource*>(context);
  CAGuard taskGuard("task guard");

  taskGuard.Lock();
  while (true) {
    source->RenderTask();
    taskGuard.WaitFor(100000000ULL);
  }
}

int main(int argc, char* const argv[])
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  srandom(time(NULL));

  if (argc < 2) {
    printf("usage: %s [audio file]\n", argv[0]);
    [pool release];
    exit(EX_USAGE);
  }

  RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Allocating decompressor");
  EAFDecompressor* decompressor = [[[EAFDecompressor alloc] initWithSystemPath:argv[1]] autorelease];
  //  Float64 duration = [decompressor frameCount] / [decompressor outputFormat].mSampleRate * 1.2;
  //
  //  if (duration < 60.0 * 3.0) {
  //      RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Source is less than 3 minutes in length (with looping), cannot run test.");
  //      [pool release];
  //      exit(EX_DATAERR);
  //  }

  try
  {
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Allocating and initializing renderer");
    AudioRenderer renderer;
    renderer.Initialize();

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Allocating source");
    // full gain, centered, looping
    CardAudioSource source(decompressor, 1.0f, 0.5f, true);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Attaching source");
    renderer.AttachSource(source);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Running...");
    renderer.Start();

    // task loop
    CAPThread taskThread(&source_task_thread, &source, CAPThread::kMaxThreadPriority, true);
    taskThread.Start();

    // wait 10 seconds
    sleep(10);

    /******/

    // disable the source for 5 seconds
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Disabling source for 5 seconds...");
    source.SetEnabled(false);

    sleep(5);
    source.SetEnabled(true);

    // take 5
    sleep(5);

    /******/

    // schedule a 10 seconds fade out
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Scheduling a 10 seconds fade out");
    renderer.RampSourceGain(source, 0.0f, 10.0);

    sleep(11);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Fade out should now be complete, fading in over 3 seconds...");
    renderer.RampSourceGain(source, 1.0f, 3.0);

    sleep(5);

    /******/

    // schedule a 10 seconds L/R pan
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Scheduling a 10 second L/R pan");
    renderer.RampSourcePan(source, 0.0f, 10.0 / 3.0);
    usleep(10.0 / 3.0 * 1.0e6);

    renderer.RampSourcePan(source, 1.0f, 2.0 * 10.0 / 3.0);
    usleep(2.0 * 10.0 / 3.0 * 1.0e6);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Panning should now be complete, centering in over 3 seconds...");
    renderer.RampSourcePan(source, 0.5f, 3.0);

    sleep(5);

    /******/

    // schedule a 10 seconds fade out
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Scheduling a 10 seconds fade out");
    renderer.RampSourceGain(source, 0.0f, 10.0);

    // disbable the source 5 seconds after the beginning of the ramp for 5 seconds
    sleep(5);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Disabling source for 5 seconds...");
    source.SetEnabled(false);

    // the ramp should resume where it left off when we enable the source
    sleep(5);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Enabling source");
    source.SetEnabled(true);

    // wait for the rest of the fade out, plus a second
    sleep(6);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Fade out should now be complete, fading in over 3 seconds...");
    renderer.RampSourceGain(source, 1.0f, 3.0);

    // And log a nice little message about the rest of the program
    sleep(5);

    /******/

    // schedule a 10 seconds fade out with quick panning
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Scheduling a 10 seconds fade out with rapid panning");
    renderer.RampSourceGain(source, 0.0f, 10.0);

    for (int i = 0; i < 10; i++) {
      renderer.RampSourcePan(source, 0.0f, 0.5);
      usleep(500000);

      renderer.RampSourcePan(source, 1.0f, 0.5);
      usleep(500000);
    }

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Fade out should now be complete, fading in and centering over 3 seconds...");
    renderer.RampSourceGain(source, 1.0f, 3.0);
    renderer.RampSourcePan(source, 0.5f, 3.0);

    sleep(5);

    /******/

    // schedule a flurry of ramps
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Applyig a flurry of ramps");

    for (int i = 0; i < 1000; i++) {
      renderer.RampSourceGain(source, (float)random() / INT32_MAX, 1.0);
      renderer.RampSourcePan(source, (float)random() / INT32_MAX, 1.0);
      usleep(10000);
    }

    // apply a final ramp to 0.0 over 2.0 seconds
    renderer.RampSourceGain(source, 0.0f, 2.0);
    renderer.RampSourcePan(source, 0.5f, 2.0);
    sleep(2);

    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Flurry should now be complete, fading in over 3 seconds...");
    renderer.RampSourceGain(source, 1.0f, 3.0);

    // And log a nice little message about the rest of the program
    sleep(5);

    /******/

    // schedule a flurry of ramps
    RXLog(kRXLoggingBase, kRXLoggingLevelDebug, @"Applying volume and pan ramps then detaching source");

    // apply a final ramp to 0.0 over 2.0 seconds
    renderer.RampSourceGain(source, 0.0f, 5.0);
    renderer.RampSourcePan(source, 0.0f, 5.0);
    sleep(2);

    renderer.DetachSource(source);
    sleep(5);
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  [pool release];
  return 0;
}
