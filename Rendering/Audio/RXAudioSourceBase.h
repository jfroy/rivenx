/*
 *  RXAudioSourceBase.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 16/02/2006.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#if !defined(RX_AUDIO_SOURCE_BASE_H)
#define RX_AUDIO_SOURCE_BASE_H

#include "RXAudioRenderer.h"

#include "Rendering/Audio/PublicUtility/CAStreamBasicDescription.h"
#include "Rendering/Audio/PublicUtility/CAAudioUnit.h"

namespace RX {

class AudioSourceBase {
  friend class AudioRenderer;

private:
  // WARNING: sub-classes are responsible for checking this variable and should output silence without updating their rendering state if it is true
  bool enabled;
  pthread_mutex_t transitionMutex;

public:
  virtual ~AudioSourceBase() noexcept(false);

  // format
  inline CAStreamBasicDescription Format() const noexcept { return format; }

  // enabling
  inline bool Enabled() const noexcept { return enabled; }
  void SetEnabled(bool enable) noexcept(false);

protected:
  static OSStatus AudioSourceRenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                            UInt32 inNumberFrames, AudioBufferList* ioData);

  AudioSourceBase() noexcept(false);

  void Finalize() noexcept(false);

  virtual void HandleAttach() noexcept(false) = 0;
  virtual void HandleDetach() noexcept(false) = 0;

  virtual bool Enable() noexcept(false) = 0;
  virtual bool Disable() noexcept(false) = 0;

  virtual OSStatus Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) noexcept;

  CAStreamBasicDescription format;
  AudioUnitElement bus;

  // WARNING: a NULL renderer is the convention for indicating a source is not attached
  AudioRenderer* rendererPtr;

private:
  AudioSourceBase(const AudioSourceBase& c) {}
  AudioSourceBase& operator=(const AudioSourceBase& c) { return *this; }
};
}

#endif // RX_AUDIO_SOURCE_BASE_H
