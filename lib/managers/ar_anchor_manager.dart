import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:flutter/services.dart';

// Type definitions to enforce a consistent use of the API
typedef AnchorUploadedHandler = void Function(ARAnchor arAnchor);
typedef AnchorDownloadedHandler = ARAnchor Function(
    Map<String, dynamic> serializedAnchor);

/// Handles all anchor-related functionality of an [ARView], including configuration and usage of collaborative sessions
class ARAnchorManager {
  /// Platform channel used for communication from and to [ARAnchorManager]
  late MethodChannel _channel;

  /// Debugging status flag. If true, all platform calls are printed. Defaults to false.
  final bool debug;

  /// Reference to all anchors that are being uploaded to the google cloud anchor API
  List<ARAnchor> pendingAnchors = [];

  /// Callback that is triggered once an anchor has successfully been uploaded to the google cloud anchor API
  AnchorUploadedHandler? onAnchorUploaded;

  /// Callback that is triggered once an anchor has successfully been downloaded from the google cloud anchor API and resolved within the current scene
  AnchorDownloadedHandler? onAnchorDownloaded;

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

  /// Activates collaborative AR mode (using Google Cloud Anchors)
  Future<bool?> initAzureCloudAnchorMode() async {
    return await _channel.invokeMethod<bool>('initAzureCloudAnchorMode');
  }

  /// Start search for anchors ids
  Future<bool?> startLocateAnchors(List<Map<String, dynamic>> assets) async {
    return await _channel
        .invokeMethod<bool>('startLocateAnchors', {"assets": assets});
  }

  /// Add given anchor to the underlying AR scene
  Future<bool?> addAnchor(ARAnchor anchor, Map<String, dynamic> asset) async {
    try {
      return await _channel.invokeMethod<bool>(
          'addAnchor', {"anchor": anchor.toJson(), "asset": asset});
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Remove given anchor and all its children from the AR Scene
  Future<bool?> removeAnchor(String anchorId) async {
    return await _channel
        .invokeMethod<bool>('removeAnchor', {'name': anchorId});
  }

  /// Upload given anchor from the underlying AR scene to the Google Cloud Anchor API
  Future<String?> uploadAnchor(String anchorId) async {
    try {
      return await _channel
          .invokeMethod<String?>('uploadAnchor', {'name': anchorId});
    } on PlatformException catch (_) {
      return null;
    }
  }
}
