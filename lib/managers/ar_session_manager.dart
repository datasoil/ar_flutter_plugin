import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Type definitions to enforce a consistent use of the API
typedef ARHitResultHandler = void Function(List<ARHitTestResult> hits);
typedef ARReadyToUpload = void Function();

/// Manages the session configuration, parameters and events of an [ARView]
class ARSessionManager {
  /// Platform channel used for communication from and to [ARSessionManager]
  late MethodChannel _channel;

  /// Debugging status flag. If true, all platform calls are printed. Defaults to false.
  final bool debug;

  /// Context of the [ARView] widget that this manager is attributed to
  final BuildContext buildContext;

  /// Receives hit results from user taps with tracked planes or feature points
  ARHitResultHandler? onPlaneOrPointTap;

  ARReadyToUpload? onReadyToUpload;

  ARSessionManager(int id, this.buildContext, {this.debug = false}) {
    _channel = MethodChannel('arsession_$id');
    _channel.setMethodCallHandler(_platformCallHandler);
    if (debug) {
      print("ARSessionManager initialized");
    }
  }

  Future<void> _platformCallHandler(MethodCall call) {
    if (debug) {
      print('_platformCallHandler call ${call.method} ${call.arguments}');
    }
    try {
      switch (call.method) {
        case 'onError':
          onError(call.arguments[0]);
          print(call.arguments);
          break;
        case 'onPlaneOrPointTap':
          final rawHitTestResults = call.arguments as List<dynamic>;
          final serializedHitTestResults = rawHitTestResults
              .map((hitTestResult) => Map<String, dynamic>.from(hitTestResult))
              .toList();
          final hitTestResults = serializedHitTestResults.map((e) {
            return ARHitTestResult.fromJson(e);
          }).toList();
          if (onPlaneOrPointTap != null) onPlaneOrPointTap!(hitTestResults);
          break;
        case 'log':
          final msg = call.arguments as String;
          debugPrint("Native LOG: " + msg);
          break;
        case 'readyToUpload':
          if (onReadyToUpload != null) onReadyToUpload!();
          break;
        case 'dispose':
          _channel.invokeMethod<void>("dispose");
          break;
        default:
          if (debug) {
            print('Unimplemented method ${call.method} ');
          }
      }
    } catch (e) {
      print('Error caught: ' + e.toString());
    }
    return Future.value();
  }

  /// Function to initialize the platform-specific AR view. Can be used to initially set or update session settings.
  /// [customPlaneTexturePath] refers to flutter assets from the app that is calling this function, NOT to assets within this plugin. Make sure
  /// the assets are correctly registered in the pubspec.yaml of the parent app (e.g. the ./example app in this plugin's repo)
  onInitialize({bool showPlanes = true, String? customPlaneTexturePath}) {
    _channel.invokeMethod<void>('init', {
      'showPlanes': showPlanes,
    });
  }

  /// Displays the [errorMessage] in a snackbar of the parent widget
  onError(String errorMessage) {
    ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(
        content: Text(errorMessage),
        action: SnackBarAction(
            label: 'HIDE',
            onPressed:
                ScaffoldMessenger.of(buildContext).hideCurrentSnackBar)));
  }

  /// Dispose the AR view on the platforms to pause the scenes and disconnect the platform handlers.
  /// You should call this before removing the AR view to prevent out of memory erros
  void dispose() async {
    try {
      await _channel.invokeMethod<void>("dispose");
    } catch (e) {
      print(e);
    }
  }

  void pause() async {
    try {
      await _channel.invokeMethod<void>("pause");
    } catch (e) {
      print(e);
    }
  }

  void resume() async {
    try {
      await _channel.invokeMethod<void>("resume");
    } catch (e) {
      print(e);
    }
  }

  updateParamas(
      {List<Map<String, dynamic>>? assets,
      List<Map<String, dynamic>>? tickets}) async {
    try {
      await _channel.invokeMethod<void>(
          "updateNearbyObjects", {"assets": assets, "tickets": tickets});
    } catch (e) {
      print(e);
    }
  }
}
