import 'dart:io';

import 'package:ar_flutter_plugin/managers/ar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// Type definitions to enforce a consistent use of the API
typedef ARViewCreatedCallback = void Function(ArController arController);

ArController? createManagers(int id, BuildContext? context,
    ARViewCreatedCallback? arViewCreatedCallback) {
  if (context == null || arViewCreatedCallback == null) {
    return null;
  }
  final controller = ArController(id);
  arViewCreatedCallback(controller);
  return controller;
}

class ARView extends StatefulWidget {
  final String permissionPromptDescription;
  final String permissionPromptButtonText;
  final String apiKey;
  final String apiId;

  /// Function to be called when the AR View is created
  final ARViewCreatedCallback onARViewCreated;

  const ARView({
    Key? key,
    required this.onARViewCreated,
    required this.apiId,
    required this.apiKey,
    this.permissionPromptDescription =
        "Camera permission must be given to the app for AR functions to work",
    this.permissionPromptButtonText = "Grant Permission",
  }) : super(key: key);

  @override
  _ARViewState createState() => _ARViewState(
      permissionPromptDescription: this.permissionPromptDescription,
      permissionPromptButtonText: this.permissionPromptButtonText);
}

class _ARViewState extends State<ARView> with WidgetsBindingObserver {
  PermissionStatus _cameraPermission = PermissionStatus.denied;
  String permissionPromptDescription;
  String permissionPromptButtonText;
  ArController? _controller;

  _ARViewState(
      {required this.permissionPromptDescription,
      required this.permissionPromptButtonText});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    requestCameraPermission();
  }

  @override
  void dispose() {
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appLifecycleState) {
    debugPrint(appLifecycleState.name);
    if (appLifecycleState == AppLifecycleState.resumed) {
      _controller?.resume();
    } else if (appLifecycleState == AppLifecycleState.paused) {
      _controller?.pause();
    }
    super.didChangeAppLifecycleState(appLifecycleState);
  }

  Future<void> requestCameraPermission() async {
    final cameraPermission = await Permission.camera.request();
    setState(() {
      _cameraPermission = cameraPermission;
    });
  }

  Future<void> requestCameraPermissionFromSettings() async {
    final cameraPermission = await Permission.camera.request();
    if (cameraPermission == PermissionStatus.permanentlyDenied) {
      openAppSettings();
    }
    setState(() {
      _cameraPermission = cameraPermission;
    });
  }

  @override
  Widget build(BuildContext context) {
    void onPlatformViewCreated(int id) {
      print("Platform view created!");
      final controller = createManagers(id, context, widget.onARViewCreated);
      setState(() {
        _controller = controller;
      });
    }

    if (_cameraPermission.isGranted) {
      final Map<String, dynamic> creationParams = <String, dynamic>{};
      creationParams['apiKey'] = widget.apiKey;
      creationParams['apiId'] = widget.apiId;
      if (Platform.isIOS)
        return UiKitView(
          viewType: 'ar_flutter_plugin',
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: onPlatformViewCreated,
        );
      if (Platform.isAndroid)
        return AndroidView(
          viewType: 'ar_flutter_plugin',
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: onPlatformViewCreated,
        );
      return Text('Platform not supported');
    }

    if (_cameraPermission.isDenied) {
      return SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(permissionPromptDescription),
            SizedBox(height: 12),
            FilledButton(
                child: Text(permissionPromptButtonText),
                onPressed: requestCameraPermission)
          ],
        ),
      ));
    }

    return SafeArea(
        child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(permissionPromptDescription),
          SizedBox(height: 12),
          FilledButton(
              child: Text(permissionPromptButtonText),
              onPressed: requestCameraPermissionFromSettings)
        ],
      ),
    ));
  }
}
