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

  /// Add given anchor to the underlying AR scene
  Future<bool?> addAnchor(
      Matrix4 transformation, Map<String, dynamic> info) async {
    try {
      return await _channel.invokeMethod<bool>('addAnchor', {
        "transformation": MatrixConverter().toJson(transformation),
        "info": info
      });
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Remove given anchor and all its children from the AR Scene
  Future<bool?> removeAnchor(String anchorId) async {
    return await _channel.invokeMethod<bool>('removeAnchor', {'id': anchorId});
  }

  /// Upload given anchor from the underlying AR scene to the Google Cloud Anchor API
  Future<String?> uploadAnchor(String anchorId) async {
    try {
      return await _channel
          .invokeMethod<String?>('uploadAnchor', {'id': anchorId});
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Upload given anchor from the underlying AR scene to the Google Cloud Anchor API
  Future<bool?> removeCloudAnchor(String anchorId) async {
    try {
      return await _channel
          .invokeMethod<bool?>('removeCloudAnchor', {'id': anchorId});
    } on PlatformException catch (_) {
      return null;
    }
  }
}
