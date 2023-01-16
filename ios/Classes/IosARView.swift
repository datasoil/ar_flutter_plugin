import ARCoreCloudAnchors
import ARKit
import Combine
import Flutter
import Foundation
import UIKit

class IosARView: NSObject, FlutterPlatformView, ARSCNViewDelegate, UIGestureRecognizerDelegate, ARSessionDelegate, ASACloudSpatialAnchorSessionDelegate {
    let sceneView: ARSCNView
    let coachingView: ARCoachingOverlayView
    let sessionManagerChannel: FlutterMethodChannel
    let anchorManagerChannel: FlutterMethodChannel

    private var configuration: ARWorldTrackingConfiguration!

    var anchorVisuals = [String: AnchorVisual]()
    var cachedAnchorVisual: AnchorVisual?
    var cloudSession: ASACloudSpatialAnchorSession?
    private var apiKey: String = "NONE"
    private var apiId: String = "NONE"
    private var nearbyAssets: [AnchorInfo] = []
    private var nearbyTickets: [AnchorInfo] = []

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        NSLog("init")
        if let argumentsDictionary = args as? [String: Any] {
            self.apiId = argumentsDictionary["apiId"] as! String
            self.apiKey = argumentsDictionary["apiKey"] as! String
            if let assets = argumentsDictionary["assets"] as? [[String: Any]] {
                self.nearbyAssets = assets.map { AnchorInfo(val: $0) }
            }
            if let tickets = argumentsDictionary["tickets"] as? [[String: Any]] {
                self.nearbyTickets = tickets.map { AnchorInfo(val: $0) }
            }
        }
        print("nearbyTickets LEN: " + String(nearbyTickets.count))
        print("nearbyAssets LEN: " + String(nearbyAssets.count))
        self.sceneView = ARSCNView(frame: frame)
        self.coachingView = ARCoachingOverlayView(frame: frame)

        self.sessionManagerChannel = FlutterMethodChannel(name: "arsession_\(viewId)", binaryMessenger: messenger)
        self.anchorManagerChannel = FlutterMethodChannel(name: "aranchors_\(viewId)", binaryMessenger: messenger)
        super.init()

        sceneView.delegate = self
        coachingView.delegate = self
        sceneView.session.delegate = self

        sessionManagerChannel.setMethodCallHandler(onSessionMethodCalled)
        anchorManagerChannel.setMethodCallHandler(onAnchorMethodCalled)

        self.configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGestureRecognizer.delegate = self
        sceneView.gestureRecognizers?.append(tapGestureRecognizer)
        if coachingView.superview == nil {
            sceneView.addSubview(coachingView)
            coachingView.autoresizingMask = [
                .flexibleWidth, .flexibleHeight
            ]
            coachingView.session = sceneView.session
            coachingView.activatesAutomatically = true
            coachingView.goal = .tracking
        }
        sceneView.session.run(configuration)

        startSession()
    }

    func view() -> UIView {
        return sceneView
    }

    func onDispose(_ result: FlutterResult) {
        sceneView.session.pause()
        stopSession()
        sessionManagerChannel.setMethodCallHandler(nil)
        anchorManagerChannel.setMethodCallHandler(nil)
        result(nil)
    }

    func onSessionMethodCalled(_ call: FlutterMethodCall, _ result: FlutterResult) {
        // let arguments = call.arguments as? [String: Any]

        switch call.method {
            case "dispose":
                onDispose(result)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
        }
    }

    func onAnchorMethodCalled(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        switch call.method {
            case "addAnchor":
                let dictInfo = arguments?["info"] as? [String: Any]
                let transform = arguments?["transformation"] as? [NSNumber]
                if dictInfo != nil, transform != nil {
                    let info = AnchorInfo(val: dictInfo!)
                    result(addAnchor(transform: transform!, info: info))
                } else {
                    result(false)
                }
            case "removeAnchor":
                if let infoId = arguments!["id"] as? String {
                    result(removeAnchor(infoId: infoId))
                }
            case "uploadAnchor":
                if let infoId = arguments!["id"] as? String {
                    uploadAnchor(infoId: infoId, result: result)
                }
            case "removeCloudAnchor":
                if let infoId = arguments!["id"] as? String {
                    removeCloudAnchor(infoId: infoId, result: result)
                }
            default:
                result(FlutterMethodNotImplemented)
        }
    }

    func startSession() {
        if cloudSession != nil {
            return
        }
        print("STARTSESSION")
        cloudSession = ASACloudSpatialAnchorSession()
        cloudSession!.session = sceneView.session
        cloudSession!.logLevel = .information
        cloudSession!.delegate = self
        cloudSession!.configuration.accountId = apiId
        cloudSession!.configuration.accountKey = apiKey
        cloudSession!.start()
        print("STARTED")
        updateLookForAssetsAnchor()
    }

    func stopSession() {
        if let cloudSession = cloudSession {
            cloudSession.stop()
            cloudSession.dispose()
        }
        cloudSession = nil

        for visual in anchorVisuals.values {
            visual.node?.parent?.removeFromParentNode()
        }

        anchorVisuals.removeAll()
    }

    func updateLookForAssetsAnchor() {
        if nearbyAssets.count < 1 || cloudSession == nil {
            return
        }
        // compactMap rimuove gli elementi a nil
        // attualmente non sto cercando gli anchor dei ticket degli asset
        var ids = nearbyAssets.compactMap { $0.ARanchorID }
        ids.append(contentsOf: nearbyTickets.compactMap { $0.ARanchorID })
        print("SEARCHING IDS", ids)
        let criteria = ASAAnchorLocateCriteria()!
        criteria.identifiers = ids
        let ws = cloudSession!.getActiveWatchers()
        ws?.first?.stop()
        cloudSession!.createWatcher(criteria)
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if anchor as? ARPlaneAnchor != nil {
            // se è un anchor plane ignoro
            return
        }
        for visual in anchorVisuals.values {
            if visual.localAnchor == anchor {
                let anode: SCNNode? = visual.renderNode()
                let yFreeConstraint = SCNBillboardConstraint()
                yFreeConstraint.freeAxes = [.Y, .X] // optionally
                node.constraints = [yFreeConstraint]
                node.isHidden = false
                node.addChildNode(anode!)
                return
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if cloudSession != nil && sceneView.session.currentFrame != nil {
            cloudSession!.processFrame(sceneView.session.currentFrame)
        }
    }

    internal func sessionUpdated(_ cloudSpatialAnchorSession: ASACloudSpatialAnchorSession!, _ args: ASASessionUpdatedEventArgs!) {
        let status = args.status!

        let enoughDataForSaving = status.recommendedForCreateProgress >= 1.0
        NSLog(String(status.recommendedForCreateProgress))
        if enoughDataForSaving {
            sessionManagerChannel.invokeMethod("readyToUpload", arguments: nil)
        }
    }

    func addAnchor(transform: [NSNumber], info: AnchorInfo) -> Bool {
        let infoId = info.id
        // lo rimuovo se lo trovo tra quelli già posizionati (caso di riposizionamento)
        if anchorVisuals[infoId] != nil {
            cachedAnchorVisual = anchorVisuals[infoId]!
            cachedAnchorVisual?.node?.isHidden = true
        }
        let arAnchor = ARAnchor(transform: simd_float4x4(deserializeMatrix4(transform)))
        sceneView.session.add(anchor: arAnchor)
        anchorVisuals[infoId] = AnchorVisual(localAnchor: arAnchor, info: info)
        return true
    }

    func removeAnchor(infoId: String) -> Bool {
        let visual = anchorVisuals[infoId]
        if visual == nil {
            return false
        }
        sceneView.session.remove(anchor: visual!.localAnchor)
        anchorVisuals.removeValue(forKey: infoId)

        if cachedAnchorVisual != nil {
            // entro qui se interrompo il processo di riposizionamento
            // ho già eliminato l'anchor appena creato, rimetto visibile quello di prima
            anchorVisuals[infoId] = cachedAnchorVisual!
            anchorVisuals[infoId]!.node?.isHidden = false
            cachedAnchorVisual = nil
        }
        return true
    }

    func uploadAnchor(infoId: String, result: @escaping FlutterResult) {
        let visual = anchorVisuals[infoId]
        if visual == nil {
            result(nil)
            return
        }
        let cloudAnchor = ASACloudSpatialAnchor()
        cloudAnchor!.localAnchor = visual!.localAnchor

        // In this sample app we delete the cloud anchor explicitly, but you can also set it to expire automatically
        let secondsInADay = 60 * 60 * 24
        let oneWeekFromNow = Date(timeIntervalSinceNow: TimeInterval(secondsInADay * 2))
        cloudAnchor!.expiration = oneWeekFromNow
        cloudSession!.createAnchor(cloudAnchor, withCompletionHandler: { (error: Error?) in
            if let error = error {
                NSLog(error.localizedDescription)
                NSLog("errore upload")
                result(nil)
            } else {
                visual!.cloudAnchor = cloudAnchor
                if self.cachedAnchorVisual != nil {
                    // entro qui se termino il processo di riposizionamento
                    // provo ad eliminare dal cloud il vecchio anchor
                    self.cloudSession!.delete(self.cachedAnchorVisual!.cloudAnchor!, withCompletionHandler: { (_: Error?) in })
                    // ignoro il risultato dell' operazione
                    // elimino il vecchio anchor localmente
                    self.sceneView.session.remove(anchor: self.cachedAnchorVisual!.localAnchor)
                    self.cachedAnchorVisual = nil
                }
                result(cloudAnchor?.identifier)
            }
        })
    }

    func removeCloudAnchor(infoId: String, result: @escaping FlutterResult) {
        let visual = anchorVisuals[infoId]
        NSLog("removeCloudAnchor")
        if visual == nil || visual?.cloudAnchor == nil {
            result(false)
            return
        }
        NSLog("valid to remove")
        NSLog(visual!.cloudAnchor!.identifier)
        cloudSession!.delete(visual!.cloudAnchor!, withCompletionHandler: { (error: Error?) in
            if let error = error {
                NSLog(error.localizedDescription)
                NSLog("errore remove cloud anchor")
                result(false)
            } else {
                NSLog("deleted")
                self.sceneView.session.remove(anchor: visual!.localAnchor)
                self.anchorVisuals.removeValue(forKey: infoId)
                result(true)
            }
        })
    }

    internal func anchorLocated(_ cloudSpatialAnchorSession: ASACloudSpatialAnchorSession!, _ args: ASAAnchorLocatedEventArgs!) {
        let status = args.status
        switch status {
            case .located:
                let cloudAnchor = args.anchor
                print("Cloud Anchor found! Identifier: \(cloudAnchor!.identifier ?? "nil").")
                // cerco prima negli asset
                if let asset = nearbyAssets.first(where: { $0.ARanchorID == cloudAnchor?.identifier }) {
                    let visual = AnchorVisual(localAnchor: cloudAnchor!.localAnchor, info: asset)
                    visual.cloudAnchor = cloudAnchor
                    anchorVisuals[asset.id] = visual
                    sceneView.session.add(anchor: cloudAnchor!.localAnchor)
                    // cerco nei ticket
                } else if let ticket = nearbyTickets.first(where: { $0.ARanchorID == cloudAnchor?.identifier }) {
                    let visual = AnchorVisual(localAnchor: cloudAnchor!.localAnchor, info: ticket)
                    visual.cloudAnchor = cloudAnchor
                    anchorVisuals[ticket.id] = visual
                    sceneView.session.add(anchor: cloudAnchor!.localAnchor)
                    // cerco nei ticket dentro gli asset
                } else if let assetTicket = nearbyAssets.filter({ $0.tickets != nil }).flatMap({ $0.tickets ?? [] }).first(where: { $0.ARanchorID == cloudAnchor?.identifier }) {
                    let visual = AnchorVisual(localAnchor: cloudAnchor!.localAnchor, info: assetTicket)
                    visual.cloudAnchor = cloudAnchor
                    anchorVisuals[assetTicket.id] = visual
                    sceneView.session.add(anchor: cloudAnchor!.localAnchor)
                } else {
                    print("ERROR Located an unknown anchor!!!!!!!")
                    break
                }
            default:
                break
        }
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let sceneView = recognizer.view as? ARSCNView else {
            return
        }
        let touchLocation = recognizer.location(in: sceneView)
        let allHitResults = sceneView.hitTest(touchLocation, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
        let nodeHitResult = allHitResults.first?.node
        if nodeHitResult != nil && nodeHitResult?.name != nil {
            NSLog("onNodeTap")
            NSLog(nodeHitResult!.name!)
            anchorManagerChannel.invokeMethod("onNodeTap", arguments: nodeHitResult!.name!)
            return
        }
        let planeTypes: ARHitTestResult.ResultType
        if #available(iOS 11.3, *) {
            planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingGeometry, .featurePoint])
        } else {
            planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingExtent, .featurePoint])
        }
        let planeAndPointHitResults = sceneView.hitTest(touchLocation, types: planeTypes)
        let serializedPlaneAndPointHitResults = planeAndPointHitResults.map { serializeHitResult($0) }
        if serializedPlaneAndPointHitResults.count != 0 {
            sessionManagerChannel.invokeMethod("onPlaneOrPointTap", arguments: serializedPlaneAndPointHitResults)
        }
    }
}

// ---------------------- ARCoachingOverlayViewDelegate ---------------------------------------

extension IosARView: ARCoachingOverlayViewDelegate {
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        // use this delegate method to hide anything in the UI that could cover the coaching overlay view
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        // Reset the session.
        sceneView.session.run(configuration, options: [.resetTracking])
    }
}
