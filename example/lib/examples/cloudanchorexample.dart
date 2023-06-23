//import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'dart:ffi';

import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
//import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
//import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:collection/collection.dart';

class CloudAnchorWidget extends StatefulWidget {
  CloudAnchorWidget({Key? key}) : super(key: key);
  @override
  _CloudAnchorWidgetState createState() => _CloudAnchorWidgetState();
}

class _CloudAnchorWidgetState extends State<CloudAnchorWidget> {
  //assegnati in void onARViewCreated()
  ARSessionManager? arSessionManager;
  //ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;
  //ARLocationManager? arLocationManager;

  Map<String, ARNode> nodes = {};
  List<ARAnchor> anchors = [];
  bool showTextFlag = false;

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
          //init della vista AR su assi xy e z
          ARView(
            onARViewCreated: onARViewCreated,
            apiId: "9112a285-e29a-4acf-a703-32df2770edc0",
            apiKey: "7CLQd5s3RMM0Hhp/Q2c36k8UBdnlNUQnyopAclvJOQI=",
            //planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical, //removed bc default xyz
            /*creationParams: {
              "assets": [
                {"id": "1234", "cod": "Codice", "ar_anchor": ""}
              ]
            },*/
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
          ),
          Align(
            alignment: FractionalOffset.center,
            child: Visibility(
                visible: this.showTextFlag,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                  ),
                  child: Text(
                    "Anchor Uploaded",
                    style: TextStyle(color: Colors.white),
                  ),
                )),
          ),
        ])));
  }

  void onARViewCreated(
      ARSessionManager arSessionManager,
      //ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager
      //ARLocationManager arLocationManager
      ) {
    this.arSessionManager = arSessionManager;
    //this.arObjectManager = arObjectManager;
    this.arAnchorManager = arAnchorManager;
    //this.arLocationManager = arLocationManager;

    //this.arObjectManager!.onInitialize();
    //aggiunta: default usa Google Cloud Anchors
    //this.arAnchorManager!.initAzureCloudAnchorMode(); //ASA mode is only mode

    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
    //this.arObjectManager!.onNodeTap = onNodeTapped;
    //removed from og:
    //this.arAnchorManager!.onAnchorUploaded = onAnchorUploaded;
    //this.arAnchorManager!.onAnchorDownloaded = onAnchorDownloaded;

    //location manager has been removed
    /*
    this
        .arLocationManager!
        .startLocationUpdates()
        .then((value) => null)
        .onError((error, stackTrace) {
      switch (error.toString()) {
        //switch per errori sui permessi app
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
    }); */
  }

  Future<void> onRemoveEverything() async {
    // anchors.forEach((anchor) {
    //   this.arAnchorManager!.removeAnchor(anchor.name);
    // });
    anchors = [];
    //in og code then e do some minor stuff
  }

  Future<void> onNodeTapped(String nodeName) async {
    var foregroundNode = nodes[nodeName] as ARNode;
    this.arSessionManager!.onError(foregroundNode.data!["onTapText"]);
  }

  //permette di creare nuova anchor
  Future<void> onPlaneOrPointTapped(
      List<ARHitTestResult> hitTestResults) async {
    var singleHitTestResult = hitTestResults.firstOrNull;
    if (singleHitTestResult != null) {
      var asset = {"id": 'asset_id', "cod": "Nome dell'Asset"};
      //var newAnchor = ARPlaneAnchor ()
      //anchor di tipo plane: ARPlaneAnchor extends ARAnchor (other type = UndefiniedAnchor)
      var newAnchor = ARAnchor(
          transformation: singleHitTestResult.worldTransform,
          name: asset["id"].toString());
      bool? didAddAnchor = false;
      //= await this.arAnchorManager!.addAnchor(newAnchor, asset);
      if (didAddAnchor ?? false) {
        this.anchors.add(newAnchor);
        print("didAddAnchor == true");
        print(newAnchor.toString());
      } else {
        this.arSessionManager!.onError("Adding Node to Anchor failed");
      }
    } else {
      this.arSessionManager!.onError("Adding Anchor failed");
    }
  }

  Future<void> onUploadButtonPressed() async {
    String? uploaded = null;
    //await this.arAnchorManager!.uploadAnchor(this.anchors.first.name);
    if (uploaded != null) {
      print('caricato');
      // Show a text message
      setState(() {
        this.showTextFlag = true;
      });

      // Wait for 2 seconds before hiding the text message
      await Future.delayed(Duration(seconds: 2));
      setState(() {
        this.showTextFlag = false;
      });
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
