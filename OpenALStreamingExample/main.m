//
//  main.m
//  OpenALStreamingExample
//
//  Created by Panayotis Matsinopoulos on 10/8/21.
//

#import <Foundation/Foundation.h>
#import <OpenAL/OpenAL.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AppState.h"
#import "CheckError.h"
#import "CheckALError.h"
#import "OpenAudioFile.h"
#import "GetNumberOfFramesInFile.h"
#import "GetExtAudioFileAudioDataFormat.h"

#define ORBIT_SPEED 1
#define BUFFER_DURATION_SECONDS  1.0

ALCdevice *OpenDevice(void) {
  ALCdevice *alDevice = alcOpenDevice(NULL);
  CheckALError("opening the defaul AL device");

  return alDevice;
}

ALCcontext * CreateContext(ALCdevice *alDevice) {
  ALCcontext *alContext = alcCreateContext(alDevice, 0);
  CheckALError("creating AL context");
  
  alcMakeContextCurrent(alContext);
  CheckALError("making the context current");
  
  return alContext;
}

void UpdateSourceLocation(AppState *appState) {
  double theta = fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED, M_PI * 2);
  ALfloat x = 3 * cos(theta);
  ALfloat y = 0.5 * sin(theta);
  ALfloat z = 1.0 * sin(theta);
  
  alSource3f(appState->sources[0], AL_POSITION, x, y, z);
  
  CheckALError("updating source lodation");
  
  return;
}

void CreateSource(AppState *appState) {
  alGenSources(1, appState->sources);

  alSourcef(appState->sources[0],
            AL_GAIN,
            AL_MAX_GAIN);
  CheckALError("setting the AL property for gain");
  
  UpdateSourceLocation(appState);
}

void PositionListenerInScene(void) {
  alListener3f(AL_POSITION, 0.0, 0.0, 0.0);
  CheckALError("setting the listener position");
}

void StartSource(AppState *appState) {
  alSourcePlay(appState->sources[0]);
  CheckALError("starting the source");
}

void StopSource(AppState *appState) {
  alSourceStop(appState->sources[0]);
  CheckALError("stopping the source");
}

void ReleaseResources(AppState *appState, ALCdevice *alDevice, ALCcontext *alContext) {
  CheckError(ExtAudioFileDispose(appState->extAudioFile), "Disposing the ext audio file");
  alDeleteSources(1, appState->sources);
  alDeleteBuffers(BUFFER_COUNT, appState->buffers);
  alcDestroyContext(alContext);
  alcCloseDevice(alDevice);
}

AudioStreamBasicDescription SpecifyAudioFormatToConverTo(ExtAudioFileRef extAudioFile) {
  AudioStreamBasicDescription dataFormat;
  
  memset((void *)&(dataFormat), 0, sizeof(dataFormat));
  dataFormat.mFormatID = kAudioFormatLinearPCM;
  dataFormat.mFramesPerPacket = 1;
  dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
  dataFormat.mBitsPerChannel = 16;
  dataFormat.mChannelsPerFrame = 1; // mono
  dataFormat.mBytesPerFrame = dataFormat.mBitsPerChannel * dataFormat.mChannelsPerFrame / 8;
  dataFormat.mBytesPerPacket = dataFormat.mBytesPerFrame * dataFormat.mFramesPerPacket;
  dataFormat.mSampleRate = 44100.0;

  CheckError(ExtAudioFileSetProperty(extAudioFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(dataFormat),
                                     &(dataFormat)),
             "Setting the client data format on the ext audio file");
  return dataFormat;
}

void ReadAudioDataAndStoreInTempBuffer(AppState *appState,
                                       UInt8 **oTempBuffer,
                                       UInt32 *oTempBufferSize) {
  *oTempBufferSize = appState->framesToPutInEachBuffer * appState->convertToDataFormat.mBytesPerFrame;
  (*oTempBuffer) = malloc(*oTempBufferSize);

  // This is a temporary structure that will basically be used as an interface
  // to the ExtAudioFileRead(). Its mBuffers[0].mData pointer will point to the
  // part of the (*oTempBuffer) we want to put data in when reading from
  // ExtAudioFileRead().
  AudioBufferList abl;
  abl.mNumberBuffers = 1;
  abl.mBuffers[0].mNumberChannels = appState->convertToDataFormat.mChannelsPerFrame;
    
  UInt32 totalFramesRead = 0;
  UInt32 framesToRead = 0;
  do {
    abl.mBuffers[0].mData = (*oTempBuffer) + totalFramesRead * appState->convertToDataFormat.mBytesPerFrame;
    framesToRead = appState->framesToPutInEachBuffer - totalFramesRead;
    abl.mBuffers[0].mDataByteSize = framesToRead * appState->convertToDataFormat.mBytesPerFrame;
    
    CheckError(ExtAudioFileRead(appState->extAudioFile,
                                &framesToRead,
                                &abl),
               "Reading data from the audio file");
    totalFramesRead += framesToRead;
    appState->totalFramesPutInBuffers += framesToRead;
  } while(totalFramesRead < appState->framesToPutInEachBuffer &&
          appState->totalFramesPutInBuffers < appState->totalFramesToPutInBuffers);
}

void CopyTempBufferDataToALBuffer(ALuint buffer,
                                  UInt8 *tempBuffer,
                                  UInt32 tempBufferSize,
                                  AudioStreamBasicDescription convertToDataFormat) {
  alBufferData(buffer,
               AL_FORMAT_MONO16,
               tempBuffer,
               tempBufferSize,
               convertToDataFormat.mSampleRate);
  CheckALError("giving data to the AL buffer");
}

void ReleaseTempBuffer(UInt8 **oTempBuffer) {
  free(*oTempBuffer);
  oTempBuffer = NULL;
}

void FillBufferWithAudioDataFromFile(AppState *appState,
                                     ALuint buffer) {
  // this is the buffer that we will fill in from the
  // the audio file and we will finally give to the OpenAL Source.
  // OpenAL Source will copy data from this buffer.
  UInt8 *tempBuffer;
  UInt32 tempBufferSize;
  
  ReadAudioDataAndStoreInTempBuffer(appState,
                                    &tempBuffer,
                                    &tempBufferSize);
      
  CopyTempBufferDataToALBuffer(buffer,
                               tempBuffer,
                               tempBufferSize,
                               appState->convertToDataFormat);
  
  ReleaseTempBuffer(&tempBuffer);
}

void RefillALBuffers(AppState *appState) {
  ALint buffersProcessed = 0;
  alGetSourcei(appState->sources[0], AL_BUFFERS_PROCESSED, &buffersProcessed);
  CheckALError("getting the number of buffers processed");
  
  while (buffersProcessed > 0) {
    ALuint bufferId;
    alSourceUnqueueBuffers(appState->sources[0], 1, &bufferId);
    CheckALError("unqueue buffer");
    
    FillBufferWithAudioDataFromFile(appState, bufferId);
    
    alSourceQueueBuffers(appState->sources[0], 1, &bufferId);
    CheckALError("re-enqueueing buffer to source");
    
    buffersProcessed--;
  }
}

void CreateAndFillBuffers(AppState *appState, const char *fileName) {
  appState->extAudioFile = OpenAudioFile(fileName);
  
  AudioStreamBasicDescription inputDataFormat = GetExtAudioFileAudioDataFormat(appState->extAudioFile);
  
  SInt64 fileLengthFrames = GetNumberOfFramesInFile(appState->extAudioFile);
  
  appState->convertToDataFormat = SpecifyAudioFormatToConverTo(appState->extAudioFile);
  
  appState->totalFramesToPutInBuffers = fileLengthFrames * appState->convertToDataFormat.mSampleRate / inputDataFormat.mSampleRate;
  
  appState->totalFramesPutInBuffers = 0;
  
  appState->framesToPutInEachBuffer = appState->convertToDataFormat.mSampleRate * BUFFER_DURATION_SECONDS;
  
  appState->duration = appState->totalFramesToPutInBuffers / appState->convertToDataFormat.mSampleRate;
    
  alGenBuffers(BUFFER_COUNT, appState->buffers);
  CheckALError("AL generating buffers");
  
  for (UInt i = 0; i < BUFFER_COUNT; i++) {
    FillBufferWithAudioDataFromFile(appState,
                                    appState->buffers[i]);
  }
}

void LinkBuffersToSource(AppState *appState) {
  alSourceQueueBuffers(appState->sources[0], BUFFER_COUNT, appState->buffers);
  CheckALError("linking buffers to the source");
}

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    NSLog(@"Starting...");
    
    AppState appState = {0};
    
    ALCdevice *alDevice = OpenDevice();
    
    ALCcontext *alContext = CreateContext(alDevice);
    
    CreateSource(&appState);

    CreateAndFillBuffers(&appState, argv[1]);
    
    LinkBuffersToSource(&appState);
    
    PositionListenerInScene();
    
    StartSource(&appState);
    
    printf("Playing ... \n");
    time_t startTime = time(NULL);
    
    do {
      UpdateSourceLocation(&appState);
      RefillALBuffers(&appState);
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    } while(difftime(time(NULL), startTime) < (appState.duration + 0.5));
    
    StopSource(&appState);
    
    ReleaseResources(&appState, alDevice, alContext);

    NSLog(@"Bye");
  }
  return 0;
}
