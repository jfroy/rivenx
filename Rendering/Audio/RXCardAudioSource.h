/*
 *  RXCardAudioSource.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 08/03/2006.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#if !defined(_RXCardAudioSource_)
#define _RXCardAudioSource_

#if !defined(__cplusplus)
#error C++ is required to include RXCardAudioSource.h
#endif

#include <libkern/OSAtomic.h>
#include <MHKKit/MHKAudioDecompression.h>

#include "Rendering/Audio/RXAudioSourceBase.h"

#include "Base/RXAtomic.h"
#include "Utilities/VirtualRingBuffer.h"

namespace RX {

class CardAudioSource : public AudioSourceBase {
public:
  static OSStatus RXCardAudioSourceRenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp,
                                                  UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData);

  CardAudioSource(id<MHKAudioDecompression> decompressor, float gain, float pan, bool loop) noexcept(false);
  virtual ~CardAudioSource() noexcept(false);

  // rendering
  void RenderTask() noexcept;
  void Reset() noexcept;

  // info
  inline int64_t FrameCount() const noexcept { return [_decompressor frameCount]; }
  inline double Duration() const noexcept { return [_decompressor frameCount] / format.mSampleRate; }

  // nominal gain
  inline float NominalGain() const noexcept { return _gain; }
  inline void SetNominalGain(float g) noexcept { _gain = g; }

  // nominal pan
  inline float NominalPan() const noexcept { return _pan; }
  inline void SetNominalPan(float p) noexcept { _pan = p; }

  // looping
  inline bool Looping() const noexcept { return _loop; }
  inline void SetLooping(bool loop) noexcept { _loop = loop; }

protected:
  virtual void HandleAttach() noexcept(false);
  virtual void HandleDetach() noexcept(false);

  virtual bool Enable() noexcept(false);
  virtual bool Disable() noexcept(false);

  virtual OSStatus Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inNumberFrames, AudioBufferList* ioData) noexcept;

private:
  void task(uint32_t byte_limit) noexcept;

  id<MHKAudioDecompression> _decompressor;
  float _gain;
  float _pan;
  bool _loop;

  VirtualRingBuffer* _decompressionBuffer;
  VirtualRingBuffer* volatile _render_buffer;
  OSSpinLock _buffer_swap_lock;

  int64_t _bufferedFrames;
  uint32_t _bytesPerTask;

  uint8_t* _loopBuffer;
  uint8_t* _loopBufferEnd;
  uint8_t* _loopBufferReadPointer;
  uint64_t _loopBufferLength;

  OSSpinLock _task_lock;
};
}

#endif // _RXCardAudioSource_
