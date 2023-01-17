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

    var enableTapToAdd = false
    var pendingAnchorVisual: AnchorVisual?
    var anchorVisuals = [String: AnchorVisual]()
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
            case "startPositioning":
                let toHide = arguments?["toHideIds"] as? [String]
                startPositioning(toHideIds: toHide)
                result(nil)

            case "createAnchor":
                let dictInfo = arguments?["info"] as! [String: Any]
                let transform = arguments?["transformation"] as! [NSNumber]
                createAnchor(transform: transform, info: AnchorInfo(val: dictInfo))
                result(nil)

            case "uploadAnchor":
                uploadAnchor(result: result)

            case "successPositioning":
                let toShow = arguments?["toShowIds"] as? [String]
                successPositioning(toShowIds: toShow)
                result(nil)

            case "abortPositioning":
                let toShow = arguments?["toShowIds"] as? [String]
                abortPositioning(toShowIds: toShow)
                result(nil)

            case "deleteAnchor":
                let infoId = arguments!["id"] as! String
                deleteAnchor(infoId: infoId)
                result(nil)

            case "deleteCloudAnchor":
                let infoId = arguments!["id"] as! String
                deleteCloudAnchor(infoId: infoId, result: result)

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

    func startPositioning(toHideIds: [String]?) {
        if toHideIds != nil {
            hideAnchors(ids: toHideIds!)
        }
        enableTapToAdd = true
    }

    func successPositioning(toShowIds: [String]?) {
        if toShowIds != nil {
            showAnchors(ids: toShowIds!)
        }
        enableTapToAdd = false
        // prendo l' anchor in pending
        if let pav = pendingAnchorVisual {
            let id = pav.id
            // guardo se ne avevo uno già posizionato
            if let av = anchorVisuals[id] {
                // se lo avevo lo elimino dalla scena e provo dal cloud
                sceneView.session.remove(anchor: av.localAnchor)
                cloudSession!.delete(av.cloudAnchor!, withCompletionHandler: { (_: Error?) in })
            }
            anchorVisuals[id] = pendingAnchorVisual
            pendingAnchorVisual = nil
        }
    }

    func abortPositioning(toShowIds: [String]?) {
        if toShowIds != nil {
            showAnchors(ids: toShowIds!)
        }
        enableTapToAdd = false
        if let pav = pendingAnchorVisual {
            sceneView.session.remove(anchor: pav.localAnchor)
            pendingAnchorVisual = nil
        }
    }

    func hideAnchors(ids: [String]) {
        ids.forEach { if anchorVisuals[$0] != nil { anchorVisuals[$0]!.node?.isHidden = true }}
    }

    func showAnchors(ids: [String]) {
        ids.forEach { if anchorVisuals[$0] != nil { anchorVisuals[$0]!.node?.isHidden = false }}
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
        if let pav = pendingAnchorVisual, pav.localAnchor == anchor {
            let anode: SCNNode? = pav.renderNode()
            let yFreeConstraint = SCNBillboardConstraint()
            yFreeConstraint.freeAxes = [.Y, .X] // optionally
            node.constraints = [yFreeConstraint]
            node.isHidden = false
            node.addChildNode(anode!)
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

    func createAnchor(transform: [NSNumber], info: AnchorInfo) {
        NSLog("createAnchor")
        let arAnchor = ARAnchor(transform: simd_float4x4(deserializeMatrix4(transform)))
        sceneView.session.add(anchor: arAnchor)
        pendingAnchorVisual = AnchorVisual(localAnchor: arAnchor, info: info)
    }

    func deleteAnchor(infoId: String) {
        if let v = anchorVisuals[infoId] {
            sceneView.session.remove(anchor: v.localAnchor)
            anchorVisuals.removeValue(forKey: infoId)
        }
    }

    func uploadAnchor(result: @escaping FlutterResult) {
        NSLog("uploadAnchor")
        if let pav = pendingAnchorVisual {
            let cloudAnchor = ASACloudSpatialAnchor()
            cloudAnchor!.localAnchor = pav.localAnchor

            // In this sample app we delete the cloud anchor explicitly, but you can also set it to expire automatically
            let secondsInADay = 60 * 60 * 24
            let oneWeekFromNow = Date(timeIntervalSinceNow: TimeInterval(secondsInADay * 2))
            cloudAnchor!.expiration = oneWeekFromNow

            cloudSession!.createAnchor(cloudAnchor, withCompletionHandler: { (error: Error?) in
                if let error = error {
                    NSLog(error.localizedDescription)
                    NSLog("error upload pending anchor")
                    result(nil)
                } else {
                    pav.cloudAnchor = cloudAnchor
                    result(cloudAnchor?.identifier)
                }
            })
        } else {
            result(nil)
        }
    }

    func deleteCloudAnchor(infoId: String, result: @escaping FlutterResult) {
        NSLog("deleteCloudAnchor")
        if let visual = anchorVisuals[infoId], visual.cloudAnchor != nil {
            cloudSession!.delete(visual.cloudAnchor!, withCompletionHandler: { (error: Error?) in
                if let error = error {
                    NSLog(error.localizedDescription)
                    NSLog("errore remove cloud anchor")
                    result(false)
                } else {
                    NSLog("deleted")
                    self.sceneView.session.remove(anchor: visual.localAnchor)
                    self.anchorVisuals.removeValue(forKey: infoId)
                    result(true)
                }
            })
        }
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
        NSLog("onTap")
        let touchLocation = recognizer.location(in: sceneView)
        let allHitResults = sceneView.hitTest(touchLocation, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
        let nodeHitResult = allHitResults.first?.node
        if nodeHitResult != nil && nodeHitResult?.name != nil {
            NSLog("onNodeTap")
            NSLog(nodeHitResult!.name!)
            anchorManagerChannel.invokeMethod("onNodeTap", arguments: nodeHitResult!.name!)
            return
        }
        if enableTapToAdd {
            NSLog("enableTapToAdd")
            let planeTypes: ARHitTestResult.ResultType
            if #available(iOS 11.3, *) {
                planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingGeometry, .featurePoint])
            } else {
                planeTypes = ARHitTestResult.ResultType([.existingPlaneUsingExtent, .featurePoint])
            }
            let planeAndPointHitResults = sceneView.hitTest(touchLocation, types: planeTypes)
            let serializedPlaneAndPointHitResults = planeAndPointHitResults.map { serializeHitResult($0) }
            if serializedPlaneAndPointHitResults.count != 0 {
                NSLog("sendxd")
                sessionManagerChannel.invokeMethod("onPlaneOrPointTap", arguments: serializedPlaneAndPointHitResults)
            }
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
