#import "FlutterSpeechRecognitionPlugin.h"
#import <Speech/Speech.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@implementation FlutterSpeechRecognitionPlugin {
    FlutterMethodChannel *channel;
    AVAudioEngine *audioEngine;
    SFSpeechRecognizer *speechRecognizer;
    SFSpeechRecognitionTask *recognitionTask;
    SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
    NSTimer *speechTimer;
}

- (instancetype)initWithChannel:(FlutterMethodChannel *) channel
{
    self = [super init];
    if (self) {
        audioEngine = [[AVAudioEngine alloc] init];
        self->channel = channel;
    }
    return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"com.flutter.speech_recognition"
            binaryMessenger:[registrar messenger]];
  FlutterSpeechRecognitionPlugin* instance = [[FlutterSpeechRecognitionPlugin alloc] initWithChannel:channel];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"speech.activate" isEqualToString:call.method]) {
      [self activate: call.arguments result:result];
  } else if ([@"speech.listen" isEqualToString:call.method]) {
      [self start:result];
  } else
  if ([@"speech.cancel" isEqualToString:call.method]) {
      [self cancel:result];
  } else
  if ([@"speech.stop" isEqualToString:call.method]) {
      [self stop:result];
  }
  else {
    result(FlutterMethodNotImplemented);
  }
}

- (void) cancel:(FlutterResult) result {
    if(speechTimer) {
        [speechTimer invalidate];
    }
    speechTimer = nil;
    if(recognitionTask) {
        [recognitionTask cancel];
        recognitionTask = nil;
    }
    if(result) {
        result([NSNumber numberWithBool:TRUE]);
    }
}

- (void) stop:(FlutterResult) result {
    if(speechTimer) {
        [speechTimer invalidate];
    }
    speechTimer = nil;
    if(audioEngine.isRunning) {
        [audioEngine stop];
        if(recognitionRequest) {
            [recognitionRequest endAudio];
        }
    }
    if(result) {
        result([NSNumber numberWithBool:TRUE]);
    }
}

- (void) start:(FlutterResult) result {
    if(audioEngine.isRunning) {
        [self stop:nil];
    }
    
    [self cancel:nil];
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryRecord mode:AVAudioSessionModeVoiceChat options:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [audioSession setMode:AVAudioSessionModeMeasurement error:nil];
    [audioSession setActive:TRUE withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    
    recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    
    if(!recognitionRequest) {
        result([FlutterError errorWithCode: @"ERROR_SPEECH_CANT_START" message:@"Can't create a SFSpeechAudioBufferRecognitionRequest :/ " details:nil]);
        return;
    }
    
    AVAudioInputNode *inputNode = audioEngine.inputNode;
    recognitionRequest.shouldReportPartialResults = TRUE;
    
    recognitionTask = [speechRecognizer recognitionTaskWithRequest:recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable speechResult, NSError * _Nullable error) {
        BOOL isFinal = FALSE;
        
        if(speechResult) {
            [self->channel invokeMethod:@"speech.onSpeech" arguments:[speechResult.bestTranscription formattedString]];
            isFinal = speechResult.isFinal;
            //NSLog(@"partial: %@", [speechResult.bestTranscription formattedString]);
            if(self->speechTimer) {
                [self->speechTimer invalidate];
            }
            if(!isFinal) {
                self->speechTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:FALSE block:^(NSTimer * _Nonnull timer) {
                    [self stop:nil];
                    [self->channel invokeMethod:@"speech.onRecognitionComplete" arguments:[speechResult.bestTranscription formattedString]];
                }];
            }
        }
        
        if(isFinal) {
            [self->channel invokeMethod:@"speech.onRecognitionComplete" arguments:[speechResult.bestTranscription formattedString]];
            //NSLog(@"final: %@", [speechResult.bestTranscription formattedString]);
        }
        
        if(error != nil || isFinal) {
            [self->audioEngine stop];
            [inputNode removeTapOnBus:0];
            self->recognitionRequest = nil;
            self->recognitionTask = nil;
        }
    }];
    
    AVAudioFormat *recognitionFormat = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:recognitionFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        if(self->recognitionRequest) {
            [self->recognitionRequest appendAudioPCMBuffer:buffer];
        }
    }];
    
    [audioEngine prepare];
    [audioEngine startAndReturnError:nil];//FIXME manage errors
    
    [channel invokeMethod:@"speech.onRecognitionStarted" arguments:nil];
    
    result([NSNumber numberWithBool:TRUE]);
}

- (void) activate:(NSString *) locale result: (FlutterResult) result {
    
    // Initialize the Speech Recognizer with the locale, couldn't find a list of locales
    // but I assume it's standard UTF-8 https://wiki.archlinux.org/index.php/locale
    speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:locale]];
    
    // Set speech recognizer delegate
    speechRecognizer.delegate = self;

    // Request the authorization to make sure the user is asked for permission so you can get an authorized response
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                result([NSNumber numberWithBool:TRUE]);
                break;
            case SFSpeechRecognizerAuthorizationStatusDenied:
                NSLog(@"Denied");
                result([FlutterError errorWithCode:@"SPEECH_PERMISSION_DENIED" message:@"Permission need to be accepted to use speech recognition" details:nil]);
                break;
            case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                NSLog(@"Not Determined");
                result([FlutterError errorWithCode:@"SPEECH_PERMISSION_NOT_DETERMINED" message:@"Permission need to be accepted to use speech recognition" details:nil]);
                break;
            case SFSpeechRecognizerAuthorizationStatusRestricted:
                NSLog(@"Restricted");
                result([FlutterError errorWithCode:@"SPEECH_PERMISSION_RESTRICTED" message:@"Permission need to be accepted to use speech recognition" details:nil]);
                break;
            default:
                result([FlutterError errorWithCode:@"SPEECH_PERMISSION_UNKNOWN" message:@"Permission need to be accepted to use speech recognition" details:nil]);
                break;
        }
    }];
}

#pragma mark - SFSpeechRecognizerDelegate Delegate Methods
    
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    [channel invokeMethod:@"speech.onSpeechAvailability" arguments:@(available)];
}

@end
