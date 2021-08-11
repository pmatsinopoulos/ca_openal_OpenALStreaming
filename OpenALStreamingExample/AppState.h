//
//  MyLoopPlayer.h
//  PositionalSoundRotateSource
//
//  Created by Panayotis Matsinopoulos on 6/8/21.
//

#ifndef AppState_h
#define AppState_h

#include <AudioToolbox/AudioToolbox.h>

#define BUFFER_COUNT 3

typedef struct _AppState {
  ExtAudioFileRef extAudioFile;
  AudioStreamBasicDescription convertToDataFormat;
  
  ALuint buffers[BUFFER_COUNT];
  ALuint sources[1];
  
  UInt64 totalFramesToEnqueue;
  UInt64 totalFramesEnqueued;
  UInt64 bufferSizeInFrames;
  
  double duration;
} AppState;

#endif /* AppState_h */
