import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:flutter/services.dart';

import '../utils/json_converters.dart';

// Type definitions to enforce a consistent use of the API
typedef NodeTapResultHandler = void Function(String node);

/// Handles all anchor-related functionality of an [ARView], including configuration and usage of collaborative sessions
class ARAnchorManager {
  /// Platform channel used for communication from and to [ARAnchorManager]
  late MethodChannel _channel;

  /// Debugging status flag. If true, all platform calls are printed. Defaults to false.
  final bool debug;

  /// Callback function that is invoked when the platform detects a tap on a node
  NodeTapResultHandler? onNodeTap;

  ARAnchorManager(int id, {this.debug = false}) {
    _channel = MethodChannel('aranchors_$id');
    _channel.setMethodCallHandler(_platformCallHandler);
    if (debug) {
      print("ARAnchorManager initialized");
    }
  }

  Future<dynamic> _platformCallHandler(MethodCall call) async {
    if (debug) {
      print('_platformCallHandler call ${call.method} ${call.arguments}');
    }
    try {
      switch (call.method) {
        case 'onError':
          print(call.arguments);
          break;
        case 'onNodeTap':
          if (onNodeTap != null) {
            final tappedNode = call.arguments as String;
            onNodeTap!(tappedNode);
          }
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

  Future<void> startPositioning({List<String>? toHideIds}) async {
    return await _channel
        .invokeMethod<void>('startPositioning', {'toHideIds': toHideIds});
  }

  Future<void> successPositioning({List<String>? toShowIds}) async {
    return await _channel
        .invokeMethod<void>('successPositioning', {'toShowIds': toShowIds});
  }

  Future<void> abortPositioning({List<String>? toShowIds}) async {
    return await _channel
        .invokeMethod<void>('abortPositioning', {'toShowIds': toShowIds});
  }

  /// Add given anchor to the underlying AR scene
  Future<void> createAnchor(
      {required Matrix4 transformation,
      required Map<String, dynamic> info}) async {
    return await _channel.invokeMethod<void>('createAnchor', {
      "transformation": MatrixConverter().toJson(transformation),
      "info": info
    });
  }

  /// Remove given anchor and all its children from the AR Scene
  Future<void> deleteAnchor({required String anchorId}) async {
    return await _channel.invokeMethod<void>('deleteAnchor', {'id': anchorId});
  }

  /// Upload given anchor from the underlying AR scene to the Google Cloud Anchor API
  Future<String?> uploadAnchor() async {
    try {
      return await _channel.invokeMethod<String?>('uploadAnchor');
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Upload given anchor from the underlying AR scene to the Google Cloud Anchor API
  Future<bool?> deleteCloudAnchor({required String anchorId}) async {
    try {
      return await _channel
          .invokeMethod<bool?>('deleteCloudAnchor', {'id': anchorId});
    } on PlatformException catch (_) {
      return null;
    }
  }
}
