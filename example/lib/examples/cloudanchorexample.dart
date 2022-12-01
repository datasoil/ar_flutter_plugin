import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:collection/collection.dart';

class CloudAnchorWidget extends StatefulWidget {
  CloudAnchorWidget({Key? key}) : super(key: key);
  @override
  _CloudAnchorWidgetState createState() => _CloudAnchorWidgetState();
}

class _CloudAnchorWidgetState extends State<CloudAnchorWidget> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;
  ARLocationManager? arLocationManager;

  Map<String, ARNode> nodes = {};
  List<ARAnchor> anchors = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    arSessionManager!.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Cloud Anchors'),
        ),
        body: Container(
            child: Stack(children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
            creationParams: {
              "assets": [
                {"id": "1234", "cod": "Codice", "ar_anchor": ""}
              ]
            },
          ),
          Align(
            alignment: FractionalOffset.bottomCenter,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                      onPressed: onRemoveEverything,
                      child: Text("Remove Everything")),
                ]),
          ),
          Align(
            alignment: FractionalOffset.topCenter,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Visibility(
                      visible: true,
                      child: ElevatedButton(
                          onPressed: onUploadButtonPressed,
                          child: Text("Upload"))),
                  Visibility(
                      visible: true,
                      child: ElevatedButton(
                          onPressed: onDownloadButtonPressed,
                          child: Text("Download"))),
                ]),
          )
        ])));
  }

  void onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;
    this.arAnchorManager = arAnchorManager;
    this.arLocationManager = arLocationManager;

    this.arSessionManager!.onInitialize(
          showPlanes: false,
          showAnimatedGuide: true,
          customPlaneTexturePath: "Images/triangle.png",
        );
    this.arObjectManager!.onInitialize();
    this.arAnchorManager!.initAzureCloudAnchorMode();

    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
    this.arObjectManager!.onNodeTap = onNodeTapped;

    this
        .arLocationManager!
        .startLocationUpdates()
        .then((value) => null)
        .onError((error, stackTrace) {
      switch (error.toString()) {
        case 'Location services disabled':
          {
            showAlertDialog(
                context,
                "Action Required",
                "To use cloud anchor functionality, please enable your location services",
                "Settings",
                this.arLocationManager!.openLocationServicesSettings,
                "Cancel");
            break;
          }

        case 'Location permissions denied':
          {
            showAlertDialog(
                context,
                "Action Required",
                "To use cloud anchor functionality, please allow the app to access your device's location",
                "Retry",
                this.arLocationManager!.startLocationUpdates,
                "Cancel");
            break;
          }

        case 'Location permissions permanently denied':
          {
            showAlertDialog(
                context,
                "Action Required",
                "To use cloud anchor functionality, please allow the app to access your device's location",
                "Settings",
                this.arLocationManager!.openAppPermissionSettings,
                "Cancel");
            break;
          }

        default:
          {
            this.arSessionManager!.onError(error.toString());
            break;
          }
      }
      this.arSessionManager!.onError(error.toString());
    });
  }

  Future<void> onRemoveEverything() async {
    anchors.forEach((anchor) {
      this.arAnchorManager!.removeAnchor(anchor);
    });
    anchors = [];
  }

  Future<void> onNodeTapped(String nodeName) async {
    var foregroundNode = nodes[nodeName] as ARNode;
    this.arSessionManager!.onError(foregroundNode.data!["onTapText"]);
  }

  Future<void> onPlaneOrPointTapped(
      List<ARHitTestResult> hitTestResults) async {
    var singleHitTestResult = hitTestResults.firstOrNull;
    if (singleHitTestResult != null) {
      var asset = {"id": '1231546', "cod": "Asset nuovo più nuovo"};
      var newAnchor = ARAnchor(
          transformation: singleHitTestResult.worldTransform,
          name: asset["id"].toString());
      bool? didAddAnchor =
          await this.arAnchorManager!.addAnchor(newAnchor, asset);
      if (didAddAnchor ?? false) {
        this.anchors.add(newAnchor);
      } else {
        this.arSessionManager!.onError("Adding Node to Anchor failed");
      }
    } else {
      this.arSessionManager!.onError("Adding Anchor failed");
    }
  }

  Future<void> onUploadButtonPressed() async {
    var uploaded = await this.arAnchorManager!.uploadAnchor(this.anchors.first);
    if (uploaded ?? false) {
      print('caricato');
    } else {
      this.arSessionManager!.onError("Upload failed");
    }
  }

  Future<void> onDownloadButtonPressed() async {}
}

void showAlertDialog(BuildContext context, String title, String content,
    String buttonText, Function buttonFunction, String cancelButtonText) {
  // set up the buttons
  Widget cancelButton = ElevatedButton(
    child: Text(cancelButtonText),
    onPressed: () {
      Navigator.of(context).pop();
    },
  );
  Widget actionButton = ElevatedButton(
    child: Text(buttonText),
    onPressed: () {
      buttonFunction();
      Navigator.of(context).pop();
    },
  );

  // set up the AlertDialog
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: Text(content),
    actions: [
      cancelButton,
      actionButton,
    ],
  );

  // show the dialog
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}
