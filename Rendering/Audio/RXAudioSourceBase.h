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
  virtual ~AudioSourceBase() throw(CAXException);

  // format
  inline CAStreamBasicDescription Format() const throw() { return format; }

  // enabling
  inline bool Enabled() const throw() { return enabled; }
  void SetEnabled(bool enable) throw(CAXException);

protected:
  static OSStatus AudioSourceRenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                            UInt32 inNumberFrames, AudioBufferList* ioData);

  AudioSourceBase() throw(CAXException);

  void Finalize() throw(CAXException);

  virtual void HandleAttach() throw(CAXException) = 0;
  virtual void HandleDetach() throw(CAXException) = 0;

  virtual bool Enable() throw(CAXException) = 0;
  virtual bool Disable() throw(CAXException) = 0;

  virtual OSStatus Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) throw();

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
