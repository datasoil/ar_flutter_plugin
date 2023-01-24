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
  NodeTapResultHandler? onAssetTap;

  NodeTapResultHandler? onTicketTap;

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
        case 'onAssetTap':
          if (onAssetTap != null) {
            final tappedNode = call.arguments as String;
            onAssetTap!(tappedNode);
          }
          break;
        case 'onTicketTap':
          if (onTicketTap != null) {
            final tappedNode = call.arguments as String;
            onTicketTap!(tappedNode);
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

  ///Initialize the process of new anchor positioning, can also hide some object anchors
  Future<void> startPositioning({List<String>? toHideIds}) async {
    return await _channel
        .invokeMethod<void>('startPositioning', {'toHideIds': toHideIds});
  }

  ///Complete the process of new anchor positioning, can also show some object anchors
  Future<void> successPositioning({List<String>? toShowIds}) async {
    return await _channel
        .invokeMethod<void>('successPositioning', {'toShowIds': toShowIds});
  }

  ///Abort the process of new anchor positioning, can also show some object anchors
  Future<void> abortPositioning({List<String>? toShowIds}) async {
    return await _channel
        .invokeMethod<void>('abortPositioning', {'toShowIds': toShowIds});
  }

  ///Show the given asset ticket anchors from the AR scene, and also show the new located asset ticket anchors
  Future<void> showAssetTicketsAnchors({required String assetId}) async {
    return await _channel
        .invokeMethod<void>('showAssetTicketsAnchors', {'assetId': assetId});
  }

  ///Hide the given asset ticket anchors from the AR scene, and also hide the new located asset ticket anchors
  Future<void> hideAssetTicketsAnchors({required String assetId}) async {
    return await _channel
        .invokeMethod<void>('hideAssetTicketsAnchors', {'assetId': assetId});
  }

  ///Show the given geo ticket anchors from the AR scene, and also show the new located geo ticket anchors
  Future<void> showTicketsAnchors({required List<String> toShowIds}) async {
    return await _channel
        .invokeMethod<void>('showTicketsAnchors', {'toShowIds': toShowIds});
  }

  ///Hide the given geo ticket anchors from the AR scene, and also hide the new located geo ticket anchors
  Future<void> hideTicketsAnchors({required List<String> toHideIds}) async {
    return await _channel
        .invokeMethod<void>('hideTicketsAnchors', {'toHideIds': toHideIds});
  }

  /// Add anchor to the AR scene where info is Asset or Ticket
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

  /// Upload the latest added Anchor to the ASA Cloud
  Future<String?> uploadAnchor() async {
    try {
      return await _channel.invokeMethod<String?>('uploadAnchor');
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Delete the given anchor from the ASA Cloud and the AR Scene
  Future<bool?> deleteCloudAnchor({required String anchorId}) async {
    try {
      return await _channel
          .invokeMethod<bool?>('deleteCloudAnchor', {'id': anchorId});
    } on PlatformException catch (_) {
      return null;
    }
  }
}
