#import <Foundation/Foundation.h>
#import <FlutterMacOS/FlutterMacOS.h>
#import <Speech/Speech.h>

API_AVAILABLE(macos(10.15))
@interface FlutterSpeechRecognitionPlugin : NSObject<FlutterPlugin, SFSpeechRecognizerDelegate>


@end

