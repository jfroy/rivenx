// Copyright 2006 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import <sysexits.h>
#import <atomic>
#import <thread>
#import <Foundation/Foundation.h>

#import "Base/RXBase.h"
#import "Base/RXThreadUtilities.h"

#import "Rendering/Audio/RXAudioRenderer.h"
#import "Rendering/Audio/PublicUtility/CAExtAudioFile.h"
#import "Rendering/Audio/PublicUtility/CAXException.h"

#define BASE_TESTS 1
#define RAMP_TESTS 0
#define ENABLED_TESTS 0

using seconds = std::chrono::seconds;

static const seconds PLAYBACK_DURATION {5};
#if RAMP_TESTS
static const seconds RAMP_DURATION {10};
#endif

using namespace std;
using namespace rx;

class AudioFileSource {
 public:
  AudioFileSource(const char* path) noexcept;
  ~AudioFileSource() noexcept;

  double duration() const noexcept { return duration_; }

  void Bind(AudioRenderer* renderer) noexcept;
  void Start() noexcept;

 private:
  CAExtAudioFile audio_file_;
  CAStreamBasicDescription format_;
  double duration_;

  AudioRenderer* renderer_;
  AudioUnitElement element_;

  thread thread_;
  atomic<bool> decompress_flag_;
};

AudioFileSource::AudioFileSource(const char* path) noexcept {
  printf("<AudioFileSource: 0x%p>: ctor: %s\n", this, path);
  audio_file_.Open(path);
  auto file_format = audio_file_.GetFileDataFormat();
  format_ = CAStreamBasicDescription(file_format.mSampleRate, file_format.NumberChannels(), CAStreamBasicDescription::kPCMFormatFloat32, true);
  audio_file_.SetClientFormat(format_);
  duration_ = audio_file_.GetNumberFrames() * format_.mSampleRate;
}

AudioFileSource::~AudioFileSource() noexcept {
  printf("<AudioFileSource: 0x%p>: dtor\n", this);
  decompress_flag_.store(false, memory_order_release);
  thread_.join();
}

void AudioFileSource::Bind(AudioRenderer* renderer) noexcept {
  if (renderer_) {
    renderer_->ReleaseElement(element_);
    renderer_ = nullptr;
  }

  if (renderer) {
    element_ = renderer->AcquireElement(format_);
    if (element_ != AudioRenderer::INVALID_ELEMENT) {
      renderer_ = renderer;
    }
  }
}

void AudioFileSource::Start() noexcept {
  decompress_flag_.store(true, memory_order_release);
  thread_ = thread([this](){
    while (decompress_flag_.load(memory_order_acquire)) {
      this_thread::sleep_for(seconds(1));
    }
  });
}

#pragma mark -

int main(int argc, char* const argv[]) {
  printf("rxaudio_test\n");
  if (argc < 3) {
    printf("usage: %s <audio file 1> <audio file 2>\n", argv[0]);
    exit(EX_USAGE);
  }

  pid_t pid = getpid();
  printf("pid: %d\nstarting in 5 seconds...\n", pid);
  this_thread::sleep_for(chrono::seconds(5));

#if BASE_TESTS
#pragma mark BASE TESTS
  printf("\n-->  testing source detach and re-attach during playback\n");
  try {
    AudioFileSource source(argv[1]);

    AudioRenderer renderer;
    renderer.Initialize();
    source.Bind(&renderer);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);

    printf("detaching...\n");
    source.Bind(nullptr);
    this_thread::sleep_for(chrono::seconds(2));

    printf("attaching source again...\n");
    source.Bind(&renderer);

    this_thread::sleep_for(PLAYBACK_DURATION);
    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }

  printf("\n-->  testing without a source\n");
  try {
    AudioRenderer renderer;
    renderer.Initialize();

    renderer.Start();
    this_thread::sleep_for(chrono::seconds(5));
    renderer.Stop();
  } catch (CAXException c) {
    (void)c;
  }

  printf("\n-->  testing no explicit source detach\n");
  try {
    AudioFileSource source(argv[1]);

    AudioRenderer renderer;
    renderer.Initialize();
    source.Bind(&renderer);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);
    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }

  printf("\n-->  testing source attach during playback\n");
  try {
    AudioFileSource source(argv[1]);

    AudioRenderer renderer;
    renderer.Initialize();

    printf("starting renderer...\n");
    renderer.Start();
    this_thread::sleep_for(chrono::seconds(2));

    printf("attaching...\n");
    source.Bind(&renderer);

    this_thread::sleep_for(PLAYBACK_DURATION);
    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }

  printf("\n-->  testing source detach after renderer stop\n");
  try {
    AudioFileSource source(argv[1]);

    AudioRenderer renderer;
    renderer.Initialize();
    source.Bind(&renderer);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);

    renderer.Stop();
    source.Bind(nullptr);
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }

  printf("\n-->  testing source attach and detach without playback\n");
  try {
    AudioFileSource source(argv[1]);
    AudioRenderer renderer;
    renderer.Initialize();
    source.Bind(&renderer);
    source.Bind(nullptr);
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }
#endif  // BASE_TESTS

#if RAMP_TESTS
#pragma mark RAMP TESTS
  printf("\n-->  testing gain ramping\n");
  try {
    AudioFileSource source(argv[1]);
    AudioFileSource source2(argv[2]);

    AudioRenderer renderer;
    renderer.Initialize();
    renderer.AttachSource(source);
    renderer.AttachSource(source2);

    renderer.SetSourceGain(source2, 0.1f);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);

    float paramValue = renderer.SourceGain(source);
    printf("initial value for source is %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("initial value for source2 is %f\n", paramValue);

    printf("first ramp...\n");
    renderer.ScheduleGainEdits({ {source.bus(), 0.1f, RAMP_DURATION}, {source2.bus(), 1.0f, RAMP_DURATION} });

    this_thread::sleep_for(RAMP_DURATION + seconds{1});

    paramValue = renderer.SourceGain(source);
    printf("ramped source to %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("ramped source2 to %f\n", paramValue);

    printf("second ramp...\n");
    renderer.ScheduleGainEdits({ {source.bus(), 1.0f, RAMP_DURATION}, {source2.bus(), 0.1f, RAMP_DURATION} });

    this_thread::sleep_for(RAMP_DURATION + seconds{1});

    paramValue = renderer.SourceGain(source);
    printf("ramped source to %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("ramped source2 to %f\n", paramValue);

    printf("ramp done\n");
    this_thread::sleep_for(PLAYBACK_DURATION);

    paramValue = renderer.SourceGain(source);
    printf("final value for source is %f\n", paramValue);
    paramValue = renderer.SourceGain(source2);
    printf("final value for source2 is %f\n", paramValue);

    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }

  printf("\n-->  testing pan ramping\n");
  try {
    AudioFileSource source(argv[1]);
    AudioRenderer renderer;
    renderer.Initialize();
    renderer.AttachSource(source);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);

    float paramValue = renderer.SourcePan(source);
    printf("initial value is %f\n", paramValue);

    printf("panning left...\n");
    renderer.SetSourcePan(source, 0.0f, RAMP_DURATION);
    this_thread::sleep_for(RAMP_DURATION + seconds{1});

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("panning right...\n");
    renderer.SetSourcePan(source, 1.0f, RAMP_DURATION * 2);
    this_thread::sleep_for(RAMP_DURATION * 2 + seconds{1});

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("panning center...\n");
    renderer.SetSourcePan(source, 0.5f, RAMP_DURATION);
    this_thread::sleep_for(RAMP_DURATION + seconds{1});

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("ramp done\n");
    this_thread::sleep_for(PLAYBACK_DURATION);

    paramValue = renderer.SourcePan(source);
    printf("final value is %f\n", paramValue);

    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }

  printf("\n-->  testing ramp update\n");
  try {
    AudioFileSource source(argv[1]);
    AudioRenderer renderer;
    renderer.Initialize();
    renderer.AttachSource(source);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);

    float paramValue = renderer.SourceGain(source);
    printf("initial value is %f\n", paramValue);

    printf("fading out...\n");
    renderer.SetSourceGain(source, 0.0f, RAMP_DURATION);
    this_thread::sleep_for(RAMP_DURATION / 2);

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("fading in...\n");
    renderer.SetSourceGain(source, 1.0f, RAMP_DURATION);
    this_thread::sleep_for(RAMP_DURATION + seconds{1});

    paramValue = renderer.SourcePan(source);
    printf("ramped to %f\n", paramValue);

    printf("ramp done\n");
    this_thread::sleep_for(PLAYBACK_DURATION);

    paramValue = renderer.SourceGain(source);
    printf("final value is %f\n", paramValue);

    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }
#endif  // RAMP_TESTS

#if ENABLED_TESTS
#pragma mark ENABLED TESTS
  printf("\n-->  testing source enabling and disabling\n");
  try {
    AudioFileSource source(argv[1]);
    AudioRenderer renderer;
    renderer.Initialize();
    renderer.AttachSource(source);

    printf("disabling source...\n");
    source.SetEnabled(false);

    renderer.Start();
    this_thread::sleep_for(PLAYBACK_DURATION);

    float paramValue = 0.0f;

    printf("scheduling gain ramp while source is disabled...\n");
    renderer.RampSourceGain(source, 0.1f, RAMP_DURATION);
    this_thread::sleep_for(chrono::seconds((RAMP_DURATION + 1)));

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("enabling source...\n");
    source.SetEnabled(true);
    this_thread::sleep_for(chrono::seconds(RAMP_DURATION));

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("scheduling gain ramp source...\n");
    renderer.RampSourceGain(source, 1.0f, RAMP_DURATION * 2);
    this_thread::sleep_for(chrono::seconds(RAMP_DURATION));

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("disabling source before gain ramp is done...\n");
    source.SetEnabled(false);
    this_thread::sleep_for(chrono::seconds(RAMP_DURATION));

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    printf("enabling source at expected gain ramp completion...\n");
    source.SetEnabled(true);
    this_thread::sleep_for(chrono::seconds((RAMP_DURATION + 1)));

    paramValue = renderer.SourceGain(source);
    printf("ramped to %f\n", paramValue);

    renderer.Stop();
  } catch (CAXException c) {
    char errorString[256];
    printf("error %s in %s\n", c.FormatError(errorString, sizeof(errorString)), c.mOperation);
  }
#endif  // ENABLED_TESTS

  return 0;
}
