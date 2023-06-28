//
//  IosARView+GestureDetector.swift
//  ar_flutter_plugin
//
//  Created by datasoil on 27/06/23.
//

import Foundation

extension IosARView: UIGestureRecognizerDelegate {
    func initalizeGestureRecognizers() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGestureRecognizer.delegate = self
        sceneView.gestureRecognizers?.append(tapGestureRecognizer)
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let sceneView = recognizer.view as? ARSCNView else {
            return
        }
        let touchLocation = recognizer.location(in: sceneView)
        let allHitResults = sceneView.hitTest(touchLocation, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])

        if let nodeHitResultName = allHitResults.first?.node.name {
            if let visual = anchorVisuals[nodeHitResultName] {
                switch visual.info.type {
                    case "asset":
                        channel.invokeMethod("onAssetTap", arguments: nodeHitResultName)
                    case "ticket":
                        channel.invokeMethod("onTicketTap", arguments: nodeHitResultName)
                    default:
                        NSLog("ERROR: node tapped unrecognized")
                }
            }
            return
        }
        if enableTapToAdd {
            let planeTypes: ARHitTestResult.ResultType
            if #available(iOS 11.3, *) {
                planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingGeometry, .featurePoint])
            } else {
                planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingExtent, .featurePoint])
            }
            let planeAndPointHitResults = sceneView.hitTest(touchLocation, types: planeTypes)
            let serializedPlaneAndPointHitResults = planeAndPointHitResults.map { serializeHitResult($0) }
            if serializedPlaneAndPointHitResults.count != 0 {
                channel.invokeMethod("onPlaneOrPointTap", arguments: serializedPlaneAndPointHitResults)
            }
        }
    }
}
