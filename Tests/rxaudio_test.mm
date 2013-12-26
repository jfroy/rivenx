/*
 *  rxaudio_test.cpp
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 24/02/2006.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#include "Base/RXBase.h"

#include <sysexits.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>

#import <Foundation/NSAutoreleasePool.h>

#include "Base/RXThreadUtilities.h"
#include "Rendering/Audio/RXAudioRenderer.h"
#include "Rendering/Audio/RXAudioSourceBase.h"

const int PLAYBACK_SECONDS = 5;
const int RAMP_DURATION = 10;

const int VERSION = 3;

#define BASE_TESTS 1
#define RAMP_TESTS 0
#define ENABLED_TESTS 0

using namespace RX;

namespace RX {

class AudioFileSource : public AudioSourceBase {
public:
  AudioFileSource(const char* path) noexcept(false);
  virtual ~AudioFileSource() noexcept(false);

  inline Float64 GetDuration() const noexcept { return fileDuration; }

protected:
  virtual OSStatus Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) noexcept;

  virtual void HandleAttach() noexcept(false);
  virtual void HandleDetach() noexcept(false);

  virtual bool Enable() noexcept(false);
  virtual bool Disable() noexcept(false);

private:
  AudioFileID audioFile;
  CAStreamBasicDescription fileFormat;
  Float64 fileDuration;
  CAAudioUnit file_player_au;
};

AudioFileSource::AudioFileSource(const char* path) noexcept(false)
{
  CFURLRef fileURL = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)path, strlen(path) + 1, false);
  XThrowIfError(AudioFileOpenURL(fileURL, kAudioFileReadPermission, 0, &audioFile), "AudioFileOpenURL");
  CFRelease(fileURL);

  // get the format of the file
  UInt32 propsize = sizeof(CAStreamBasicDescription);
  XThrowIfError(AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &propsize, &fileFormat), "AudioFileGetProperty");

  printf("playing file: %s\n", path);
  fileFormat.Print();
  printf("\n");

  UInt64 nPackets;
  propsize = sizeof(nPackets);
  XThrowIfError(AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets), "kAudioFilePropertyAudioDataPacketCount");
  fileDuration = (nPackets * fileFormat.mFramesPerPacket) / fileFormat.mSampleRate;

  // set our output format as canonical
  format.mSampleRate = 44100.0;
  format.SetCanonical(fileFormat.NumberChannels(), false);
  printf("<AudioFileSource: 0x%p>: output format: ", this);
  format.Print();
  printf("\n");
}

AudioFileSource::~AudioFileSource() noexcept(false)
{
  printf("<AudioFileSource: 0x%p>: deallocating\n", this);
  Finalize();
}

OSStatus AudioFileSource::Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames,
                                 AudioBufferList* ioData) noexcept
{
  if (!Enabled()) {
    for (UInt32 bufferIndex = 0; bufferIndex < ioData->mNumberBuffers; bufferIndex++)
      bzero(ioData->mBuffers[bufferIndex].mData, ioData->mBuffers[bufferIndex].mDataByteSize);
    *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
  }

  return file_player_au.Render(ioActionFlags, inTimeStamp, 0, inNumberFrames, ioData);
}

void AudioFileSource::HandleAttach() noexcept(false)
{
  printf("<AudioFileSource: 0x%p>: HandleAttach()\n", this);

  CAComponentDescription cd;
  cd.componentType = kAudioUnitType_Generator;
  cd.componentSubType = kAudioUnitSubType_AudioFilePlayer;
  cd.componentManufacturer = kAudioUnitManufacturer_Apple;

  CAAudioUnit::Open(cd, file_player_au);

  // set the output format before we initialize the AU
  XThrowIfError(file_player_au.SetFormat(kAudioUnitScope_Output, 0, format), "file_player_au.SetFormat");

  // initialize
  XThrowIfError(file_player_au.Initialize(), "file_player_au.Initialize");

  // set the scheduled file IDs
  XThrowIfError(file_player_au.SetProperty(kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &audioFile, sizeof(audioFile)),
                "file_player_au.SetScheduleFile");

  // workaround a race condition in the file player AU
  usleep(10 * 1000);

  // schedule a file region covering the entire file
  UInt64 nPackets;
  UInt32 propsize = sizeof(nPackets);
  XThrowIfError(AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets),
                "AudioFileGetProperty(audioFile, ...) for kAudioFilePropertyAudioDataPacketCount");

  ScheduledAudioFileRegion rgn;
  memset(&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
  rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
  rgn.mTimeStamp.mSampleTime = 0;
  rgn.mCompletionProc = NULL;
  rgn.mCompletionProcUserData = NULL;
  rgn.mAudioFile = audioFile;
  rgn.mLoopCount = 1;
  rgn.mStartFrame = 0;
  rgn.mFramesToPlay = UInt32(nPackets * fileFormat.mFramesPerPacket);

  XThrowIfError(file_player_au.SetProperty(kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &rgn, sizeof(rgn)),
                "file_player_au.SetProperty for kAudioUnitProperty_ScheduledFileRegion");

  // prime the AU
  UInt32 defaultVal = 0;
  XThrowIfError(file_player_au.SetProperty(kAudioUnitProperty_ScheduledFilePrime, kAudioUnitScope_Global, 0, &defaultVal, sizeof(defaultVal)),
                "kAudioUnitProperty_ScheduledFilePrime");

  // set the start time to the next render cycle (sample time = -1)
  AudioTimeStamp startTime;
  memset(&startTime, 0, sizeof(startTime));
  startTime.mFlags = kAudioTimeStampSampleTimeValid;
  startTime.mSampleTime = -1;
  XThrowIfError(file_player_au.SetProperty(kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime)),
                "file_player_au.SetProperty for kAudioUnitProperty_ScheduleStartTimeStamp");
}

void AudioFileSource::HandleDetach() noexcept(false)
{
  printf("<AudioFileSource: 0x%p>: HandleDetach()\n", this);
  file_player_au.Uninitialize();
}

bool AudioFileSource::Enable() noexcept(false) { return true; }

bool AudioFileSource::Disable() noexcept(false) { return true; }
}

#if RAMP_TESTS
static const void* AudioFileSourceArrayRetain(CFAllocatorRef allocator, const void* value) { return value; }

static void AudioFileSourceArrayRelease(CFAllocatorRef allocator, const void* value) {}

static CFStringRef AudioFileSourceArrayDescription(const void* value)
{ return CFStringCreateWithFormat(NULL, NULL, CFSTR("<RX::AudioSourceBase: 0x%x>"), value); }

static Boolean AudioFileSourceArrayEqual(const void* value1, const void* value2) { return value1 == value2; }

static CFArrayCallBacks g_weakAudioFileSourceArrayCallbacks = {0,                               AudioFileSourceArrayRetain, AudioFileSourceArrayRelease,
                                                               AudioFileSourceArrayDescription, AudioFileSourceArrayEqual};
#endif

#pragma mark -

int main(int argc, char* const argv[])
{
  printf("rxaudio_test v%d\n", VERSION);
  if (argc < 3) {
    printf("usage: %s <audio file 1> <audio file 2>\n", argv[0]);
    exit(EX_USAGE);
  }

  NSAutoreleasePool* p = [NSAutoreleasePool new];

  pid_t pid = getpid();
  printf("pid: %d\nstarting in 5 seconds...\n", pid);
  sleep(5);

#if BASE_TESTS
#pragma mark BASE TESTS
  printf("\n-->  testing source detach and re-attach during playback\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Start();
    usleep(PLAYBACK_SECONDS * 1000000);

    printf("detaching...\n");
    renderer.DetachSource(source);
    usleep(2 * 1000000);

    printf("attaching source again...\n");
    renderer.AttachSource(source);

    usleep(PLAYBACK_SECONDS * 1000000);
    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing without a source\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    renderer.Start();
    usleep(5 * 1000000);
    renderer.Stop();
  }
  catch (CAXException c) { (void)c; }

  printf("\n-->  testing no explicit source detach\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Start();
    usleep(PLAYBACK_SECONDS * 1000000);
    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing source attach during playback\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);

    printf("starting renderer...\n");
    renderer.Start();
    usleep(2 * 1000000);

    printf("attaching...\n");
    renderer.AttachSource(source);

    usleep(PLAYBACK_SECONDS * 1000000);
    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing source detach after renderer stop\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Start();
    usleep(PLAYBACK_SECONDS * 1000000);

    renderer.Stop();
    renderer.DetachSource(source);
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing source attach and detach without playback\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);
    renderer.DetachSource(source);
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing source attach before renderer initialize\n");
  try
  {
    AudioRenderer renderer;

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Initialize();
    renderer.Start();
    usleep(PLAYBACK_SECONDS * 1000000);
    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing detach with no automatic graph updates\n");
  try
  {
    AudioRenderer renderer;

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Initialize();
    renderer.Start();
    usleep(PLAYBACK_SECONDS * 1000000);

    printf("detaching...\n");
    renderer.SetAutomaticGraphUpdates(false);
    renderer.DetachSource(source);
    usleep(PLAYBACK_SECONDS * 1000000);

    printf("stopping...\n");
    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }
#endif // BASE_TESTS

#if RAMP_TESTS
#pragma mark RAMP TESTS
  printf("\n-->  testing gain ramping\n");
  CFMutableArrayRef sources = CFArrayCreateMutable(NULL, 0, &g_weakAudioFileSourceArrayCallbacks);
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    AudioFileSource source2(argv[2]);
    renderer.AttachSource(source2);
    renderer.SetSourceGain(source2, 0.0f);

    std::vector<Float32> values_ramp1;
    values_ramp1.push_back(0.0f);
    values_ramp1.push_back(1.0f);

    std::vector<Float32> values_ramp2;
    values_ramp2.push_back(1.0f);
    values_ramp2.push_back(0.0f);

    std::vector<Float64> durations = std::vector<Float64>(2, RAMP_DURATION);

    CFArrayAppendValue(sources, &source);
    CFArrayAppendValue(sources, &source2);

    renderer.Start();
    usleep(PLAYBACK_SECONDS * 1000000);

    Float32 paramValue = renderer.SourceGain(source);
    printf("initial value for source is %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("initial value for source2 is %f\n", paramValue);

    printf("first ramp...\n");
    renderer.RampSourcesGain(sources, values_ramp1, durations);

    usleep((RAMP_DURATION + 1) * 1000000);

    paramValue = renderer.SourceGain(source);
    printf("ramped source to %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("ramped source2 to %f\n", paramValue);

    printf("second ramp...\n");
    renderer.RampSourcesGain(sources, values_ramp2, durations);

    usleep((RAMP_DURATION + 1) * 1000000);

    paramValue = renderer.SourceGain(source);
    printf("ramped source to %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("ramped source2 to %f\n", paramValue);

    printf("ramp done\n");
    usleep(PLAYBACK_SECONDS * 1000000);

    paramValue = renderer.SourceGain(source);
    printf("final value for source is %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("final value for source2 is %f\n", paramValue);

    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }
  CFRelease(sources);

  printf("\n-->  testing pan ramping\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Start();
    sleep(PLAYBACK_SECONDS);

    Float32 paramValue = renderer.SourcePan(source);
    printf("initial value is %f\n", paramValue);

    printf("panning left...\n");
    renderer.RampSourcePan(source, 0.0f, RAMP_DURATION);
    sleep(RAMP_DURATION + 1);

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("panning right...\n");
    renderer.RampSourcePan(source, 1.0f, RAMP_DURATION * 2);
    sleep((RAMP_DURATION * 2) + 1);

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("panning center...\n");
    renderer.RampSourcePan(source, 0.5f, RAMP_DURATION);
    sleep(RAMP_DURATION + 1);

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("ramp done\n");
    sleep(PLAYBACK_SECONDS);

    paramValue = renderer.SourcePan(source);
    printf("final value is %f\n", paramValue);

    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }

  printf("\n-->  testing ramp update\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    renderer.Start();
    sleep(PLAYBACK_SECONDS);

    Float32 paramValue = renderer.SourceGain(source);
    printf("initial value is %f\n", paramValue);

    printf("fading out...\n");
    renderer.RampSourceGain(source, 0.0f, RAMP_DURATION);
    sleep(RAMP_DURATION / 2);

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("fading in...\n");
    renderer.RampSourceGain(source, 1.0f, RAMP_DURATION);
    sleep(RAMP_DURATION + 1);

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("ramp done\n");
    sleep(PLAYBACK_SECONDS);

    paramValue = renderer.SourceGain(source);
    printf("final value is %f\n", paramValue);

    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }
#endif // RAMP_TESTS

#if ENABLED_TESTS
#pragma mark ENABLED TESTS
  printf("\n-->  testing source enabling and disabling\n");
  try
  {
    AudioRenderer renderer;
    renderer.Initialize();

    AudioFileSource source(argv[1]);
    renderer.AttachSource(source);

    printf("disabling source...\n");
    source.SetEnabled(false);

    renderer.Start();
    sleep(PLAYBACK_SECONDS);

    Float32 paramValue = 0.0f;

    printf("scheduling gain ramp while source is disabled...\n");
    renderer.RampSourceGain(source, 0.1f, RAMP_DURATION);
    sleep(RAMP_DURATION + 1);

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("enabling source...\n");
    source.SetEnabled(true);
    sleep(RAMP_DURATION);

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("scheduling gain ramp source...\n");
    renderer.RampSourceGain(source, 1.0f, RAMP_DURATION * 2);
    sleep(RAMP_DURATION);

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("disabling source before gain ramp is done...\n");
    source.SetEnabled(false);
    sleep(RAMP_DURATION);

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("enabling source at expected gain ramp completion...\n");
    source.SetEnabled(true);
    sleep(RAMP_DURATION + 1);

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    renderer.Stop();
  }
  catch (CAXException c)
  {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString), c.mOperation);
  }
#endif // ENABLED_TESTS

  [p release];
  return 0;
}
