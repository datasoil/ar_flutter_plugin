import 'package:flutter/services.dart';

import '../models/ar_hittest_result.dart';
import '../utils/json_converters.dart';

// Type definitions to enforce a consistent use of the API
typedef NodeTapResultHandler = void Function(String node);
typedef ARHitResultHandler = void Function(List<ARHitTestResult> hits);
typedef ARReadyToUpload = void Function();

/// Handles all anchor-related functionality of an [ARView], including configuration and usage of collaborative sessions
class ArController {
  /// Platform channel used for communication from and to [ARAnchorManager]
  late MethodChannel _channel;

  /// Callback function that is invoked when the platform detects a tap on a node
  NodeTapResultHandler? onAssetTap;

  NodeTapResultHandler? onTicketTap;

  /// Receives hit results from user taps with tracked planes or feature points
  ARHitResultHandler? onPlaneOrPointTap;

  ARReadyToUpload? onReadyToUpload;

  ArController(int id) {
    _channel = MethodChannel('archannel_$id');
    _channel.setMethodCallHandler(_platformCallHandler);
  }

  Future<dynamic> _platformCallHandler(MethodCall call) async {
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
        case 'readyToUpload':
          if (onReadyToUpload != null) onReadyToUpload!();
          break;
        case 'dispose':
          _channel.invokeMethod<void>("dispose");
          break;
        default:
          print('Unimplemented method ${call.method} ');
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

  Future<void> syncData(
      {List<Map<String, dynamic>>? assets,
      List<Map<String, dynamic>>? tickets}) async {
    try {
      return await _channel.invokeMethod<void>(
          "updateNearbyObjects", {"assets": assets, "tickets": tickets});
    } catch (e) {
      print(e);
    }
  }
}
