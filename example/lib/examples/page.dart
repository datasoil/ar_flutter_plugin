import 'package:ar_flutter_plugin/managers/ar_controller.dart';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';

class ArPage extends StatefulWidget {
  ArPage({Key? key}) : super(key: key);
  @override
  _ArPageState createState() => _ArPageState();
}

class _ArPageState extends State<ArPage> {
  ArController? arController;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    arController!.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('ArPage example'),
        ),
        body: Container(
            child: Stack(
          children: [
            //init della vista AR su assi xy e z
            ARView(
              onARViewCreated: onARViewCreated,
              apiId: "9112a285-e29a-4acf-a703-32df2770edc0",
              apiKey: "7CLQd5s3RMM0Hhp/Q2c36k8UBdnlNUQnyopAclvJOQI=",
            ),
          ],
        )));
  }

  void onARViewCreated(
    ArController controller,
  ) {
    this.arController = arController;
  }
}
