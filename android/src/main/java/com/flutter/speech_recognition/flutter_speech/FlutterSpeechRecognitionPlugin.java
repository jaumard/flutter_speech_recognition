package com.flutter.speech_recognition.flutter_speech;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.util.Log;

import androidx.core.app.ActivityCompat;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;

import java.util.ArrayList;

/** FlutterSpeechRecognitionPlugin */
public class FlutterSpeechRecognitionPlugin implements MethodCallHandler, RecognitionListener, PluginRegistry.RequestPermissionsResultListener {

  private static final String LOG_TAG = "FlutterSpeechPlugin";
  private static final int MY_PERMISSIONS_RECORD_AUDIO = 16669;
  private SpeechRecognizer speech;
  private MethodChannel speechChannel;
  private String transcription = "";
  private Intent recognizerIntent;
  private Activity activity;
  private Result permissionResult;

  /**
   * Plugin registration.
   */
  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "com.flutter.speech_recognition");
    final FlutterSpeechRecognitionPlugin plugin = new FlutterSpeechRecognitionPlugin(registrar.activity(), channel);
    channel.setMethodCallHandler(plugin);
    registrar.addRequestPermissionsResultListener(plugin);
  }

  private FlutterSpeechRecognitionPlugin(Activity activity, MethodChannel channel) {
    this.speechChannel = channel;
    this.speechChannel.setMethodCallHandler(this);
    this.activity = activity;

    speech = SpeechRecognizer.createSpeechRecognizer(activity.getApplicationContext());
    speech.setRecognitionListener(this);

    recognizerIntent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
    recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
    recognizerIntent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
    recognizerIntent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3);
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    switch (call.method) {
      case "speech.activate":
        Log.d(LOG_TAG, "Current Locale : " + call.arguments.toString());
        recognizerIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, getLocaleCode(call.arguments.toString()));

        if (activity.checkCallingOrSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
        } else {
          permissionResult = result;
          ActivityCompat.requestPermissions(activity, new String[]{Manifest.permission.RECORD_AUDIO}, MY_PERMISSIONS_RECORD_AUDIO);
        }

        break;
      case "speech.listen":
        speech.startListening(recognizerIntent);
        result.success(true);
        break;
      case "speech.cancel":
        speech.cancel();
        result.success(false);
        break;
      case "speech.stop":
        speech.stopListening();
        result.success(true);
        break;
      case "speech.destroy":
        speech.cancel();
        speech.destroy();
        result.success(true);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private String getLocaleCode(String code) {
    return code.replace("_", "-");
  }

  @Override
  public void onReadyForSpeech(Bundle params) {
    Log.d(LOG_TAG, "onReadyForSpeech");
    speechChannel.invokeMethod("speech.onSpeechAvailability", true);
  }

  @Override
  public void onBeginningOfSpeech() {
    Log.d(LOG_TAG, "onRecognitionStarted");
    transcription = "";
    speechChannel.invokeMethod("speech.onRecognitionStarted", null);
  }

  @Override
  public void onRmsChanged(float rmsdB) {
    Log.d(LOG_TAG, "onRmsChanged : " + rmsdB);
  }

  @Override
  public void onBufferReceived(byte[] buffer) {
    Log.d(LOG_TAG, "onBufferReceived");
  }

  @Override
  public void onEndOfSpeech() {
    Log.d(LOG_TAG, "onEndOfSpeech");
    speechChannel.invokeMethod("speech.onRecognitionComplete", transcription);
  }

  @Override
  public void onError(int error) {
    Log.d(LOG_TAG, "onError : " + error);
    speechChannel.invokeMethod("speech.onSpeechAvailability", false);
    speechChannel.invokeMethod("speech.onError", error);
  }

  @Override
  public void onPartialResults(Bundle partialResults) {
    Log.d(LOG_TAG, "onPartialResults...");
    ArrayList<String> matches = partialResults
            .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
    if (matches != null) {
      transcription = matches.get(0);
    }
    sendTranscription(false);
  }

  @Override
  public void onEvent(int eventType, Bundle params) {
    Log.d(LOG_TAG, "onEvent : " + eventType);
  }

  @Override
  public void onResults(Bundle results) {
    Log.d(LOG_TAG, "onResults...");
    ArrayList<String> matches = results
            .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
    if (matches != null) {
      transcription = matches.get(0);
      Log.d(LOG_TAG, "onResults -> " + transcription);
      sendTranscription(true);
    }
    sendTranscription(false);
  }

  private void sendTranscription(boolean isFinal) {
    speechChannel.invokeMethod(isFinal ? "speech.onRecognitionComplete" : "speech.onSpeech", transcription);
  }

  @Override
  public boolean onRequestPermissionsResult(int code, String[] permissions, int[] results) {
    if (code == MY_PERMISSIONS_RECORD_AUDIO) {
      if(results[0] == PackageManager.PERMISSION_GRANTED) {
        permissionResult.success(true);
      } else {
        permissionResult.error("ERROR_NO_PERMISSION", "Audio permission are not granted", null);
      }
      permissionResult = null;
      return true;
    }
    return false;
  }
}
