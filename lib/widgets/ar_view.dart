import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';

// Type definitions to enforce a consistent use of the API
//inglobatore di mangers per passarli in giro?
typedef ARViewCreatedCallback = void Function(
    ARSessionManager arSessionManager, ARAnchorManager arAnchorManager);

/// Factory method for creating a platform-dependent AR view
abstract class PlatformARView {
  factory PlatformARView(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return AndroidARView();
      case TargetPlatform.iOS:
        return IosARView();
      default:
        throw FlutterError;
    }
  }

  Widget build(
      {@required BuildContext context,
      @required ARViewCreatedCallback arViewCreatedCallback,
      @required String apiKey,
      @required String apiId,
      @required List<Map<String, dynamic>>? assets,
      @required List<Map<String, dynamic>>? tickets});

  /// Callback function that is executed once the view is established
  void onPlatformViewCreated(int id);
}

//funzione implicitamente void?
/// Instantiates [ARSessionManager], [ARObjectManager] and returns them to the widget instantiating the [ARView] using the [arViewCreatedCallback]
createManagers(int id, BuildContext? context,
    ARViewCreatedCallback? arViewCreatedCallback) {
  if (context == null || arViewCreatedCallback == null) {
    return;
  }
  arViewCreatedCallback(ARSessionManager(id, context), ARAnchorManager(id));
}

/// Android-specific implementation of [PlatformARView]
/// Uses Hybrid Composition to increase peformance on Android 9 and below (https://flutter.dev/docs/development/platform-integration/platform-views)
class AndroidARView implements PlatformARView {
  late BuildContext? _context;
  late ARViewCreatedCallback? _arViewCreatedCallback;

  @override
  void onPlatformViewCreated(int id) {
    print("Android platform view created!");
    createManagers(id, _context, _arViewCreatedCallback);
  }

  @override
  Widget build(
      {BuildContext? context,
      ARViewCreatedCallback? arViewCreatedCallback,
      String? apiKey,
      String? apiId,
      List<Map<String, dynamic>>? assets,
      List<Map<String, dynamic>>? tickets}) {
    _context = context;
    _arViewCreatedCallback = arViewCreatedCallback;
    // This is used in the platform side to register the view.
    final String viewType = 'ar_flutter_plugin_view';
    final Map<String, dynamic> creationParams = <String, dynamic>{};
    creationParams['apiKey'] = apiKey;
    creationParams['apiId'] = apiId;
    creationParams['assets'] = assets;
    creationParams['tickets'] = tickets;
    return AndroidView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onPlatformViewCreated //onPlatformViewCreated,
        );
  }
}

/// iOS-specific implementation of [PlatformARView]
class IosARView implements PlatformARView {
  BuildContext? _context;
  ARViewCreatedCallback? _arViewCreatedCallback;

  @override
  void onPlatformViewCreated(int id) {
    print("iOS platform view created!");
    createManagers(id, _context, _arViewCreatedCallback);
  }

  @override
  Widget build(
      {BuildContext? context,
      ARViewCreatedCallback? arViewCreatedCallback,
      String? apiKey,
      String? apiId,
      List<Map<String, dynamic>>? assets,
      List<Map<String, dynamic>>? tickets}) {
    _context = context;
    _arViewCreatedCallback = arViewCreatedCallback;
    // This is used in the platform side to register the view.
    final String viewType = 'ar_flutter_plugin';
    final Map<String, dynamic> creationParams = <String, dynamic>{};
    creationParams['apiKey'] = apiKey;
    creationParams['apiId'] = apiId;
    creationParams['assets'] = assets;
    creationParams['tickets'] = tickets;
    return UiKitView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: onPlatformViewCreated,
    );
  }
}

/// If camera permission is granted, [ARView] creates a platform-dependent view from the factory method [PlatformARView]. To instantiate an [ARView],
/// the calling widget needs to pass the callback function [onARViewCreated] to which the function [createManagers] returns managers such as the
/// [ARSessionManager] and the [ARObjectManager]. [planeDetectionConfig] is passed to the constructor to determine which types of planes the underlying
/// AR frameworks should track (defaults to none).
/// If camera permission is not given, the user is prompted to grant it. To modify the UI of the prompts, the following named parameters can be used:
/// [permissionPromptDescription], [permissionPromptButtonText] and [permissionPromptParentalRestriction].
class ARView extends StatefulWidget {
  final String permissionPromptDescription;
  final String permissionPromptButtonText;
  final String permissionPromptParentalRestriction;
  final String apiKey;
  final String apiId;
  final List<Map<String, dynamic>>? assets;
  final List<Map<String, dynamic>>? tickets;

  /// Function to be called when the AR View is created
  final ARViewCreatedCallback onARViewCreated;

  ARView(
      {Key? key,
      required this.onARViewCreated,
      required this.apiId,
      required this.apiKey,
      this.assets,
      this.tickets,
      this.permissionPromptDescription =
          "Camera permission must be given to the app for AR functions to work",
      this.permissionPromptButtonText = "Grant Permission",
      this.permissionPromptParentalRestriction =
          "Camera permission is restriced by the OS, please check parental control settings"})
      : super(key: key);

  @override
  _ARViewState createState() => _ARViewState(
      permissionPromptDescription: this.permissionPromptDescription,
      permissionPromptButtonText: this.permissionPromptButtonText,
      permissionPromptParentalRestriction:
          this.permissionPromptParentalRestriction);
}

class _ARViewState extends State<ARView> {
  PermissionStatus _cameraPermission = PermissionStatus.denied;
  String permissionPromptDescription;
  String permissionPromptButtonText;
  String permissionPromptParentalRestriction;

  _ARViewState(
      {required this.permissionPromptDescription,
      required this.permissionPromptButtonText,
      required this.permissionPromptParentalRestriction});

  @override
  void initState() {
    super.initState();
    initCameraPermission();
  }

  initCameraPermission() async {
    requestCameraPermission();
  }

  requestCameraPermission() async {
    final cameraPermission = await Permission.camera.request();
    setState(() {
      _cameraPermission = cameraPermission;
    });
  }

  requestCameraPermissionFromSettings() async {
    final cameraPermission = await Permission.camera.request();
    if (cameraPermission == PermissionStatus.permanentlyDenied) {
      openAppSettings();
    }
    setState(() {
      _cameraPermission = cameraPermission;
    });
  }

  @override
  build(BuildContext context) {
    switch (_cameraPermission) {
      case (PermissionStatus
          .limited): //iOS-specific: permissions granted for this specific application
      case (PermissionStatus.granted):
        {
          return PlatformARView(Theme.of(context).platform).build(
              context: context,
              arViewCreatedCallback: widget.onARViewCreated,
              apiKey: widget.apiKey,
              apiId: widget.apiId,
              assets: widget.assets,
              tickets: widget.tickets);
        }
      case (PermissionStatus.denied):
        {
          return Center(
              child: Column(
            children: [
              Text(permissionPromptDescription),
              ElevatedButton(
                  child: Text(permissionPromptButtonText),
                  onPressed: () async => {await requestCameraPermission()})
            ],
          ));
        }
      case (PermissionStatus
          .permanentlyDenied): //Android-specific: User needs to open Settings to give permissions
        {
          return Center(
              child: Column(
            children: [
              Text(permissionPromptDescription),
              ElevatedButton(
                  child: Text(permissionPromptButtonText),
                  onPressed: () async =>
                      {await requestCameraPermissionFromSettings()})
            ],
          ));
        }
      case (PermissionStatus.restricted):
        {
          //iOS only
          return Center(child: Text(permissionPromptParentalRestriction));
        }
      default:
        return Text('something went wrong');
    }
  }
}
