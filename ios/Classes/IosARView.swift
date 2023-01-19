import ARCoreCloudAnchors
import ARKit
import Combine
import Flutter
import Foundation
import UIKit

class IosARView: NSObject, FlutterPlatformView, ARSCNViewDelegate, UIGestureRecognizerDelegate, ASACloudSpatialAnchorSessionDelegate {
    let sceneView: ARSCNView
    let coachingView: ARCoachingOverlayView
    let sessionManagerChannel: FlutterMethodChannel
    let anchorManagerChannel: FlutterMethodChannel

    private var configuration: ARWorldTrackingConfiguration!

    var enableTapToAdd = false
    var pendingAnchorVisual: AnchorVisual?
    var anchorVisuals = [String: AnchorVisual]()
    var cloudSession: ASACloudSpatialAnchorSession?
    var mainWatcher: ASACloudSpatialAnchorWatcher?
    private var apiKey: String = "NONE"
    private var apiId: String = "NONE"
    private var nearbyAssets = [String: AnchorInfo]()
    private var nearbyTickets = [String: AnchorInfo]()
    var hideAssetTickets = [String: Bool]()
    var hideTickets = false

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
                self.nearbyAssets = assets.reduce(into: [String: AnchorInfo]()) {
                    $0[$1["id"] as! String] = AnchorInfo(val: $1)
                }
            }
            if let tickets = argumentsDictionary["tickets"] as? [[String: Any]] {
                self.nearbyTickets = tickets.reduce(into: [String: AnchorInfo]()) {
                    $0[$1["id"] as! String] = AnchorInfo(val: $1)
                }
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
        // sceneView.session.delegate = self

        sessionManagerChannel.setMethodCallHandler(onSessionMethodCalled)
        anchorManagerChannel.setMethodCallHandler(onAnchorMethodCalled)

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
        self.configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration)

        startSession()
    }

    func view() -> UIView {
        return sceneView
    }

    func onDispose() {
        print("DISPOSE ARVIEW")
        stopSession()
        sceneView.session.pause()
        sessionManagerChannel.setMethodCallHandler(nil)
        anchorManagerChannel.setMethodCallHandler(nil)
    }

    func onPause() {
        sceneView.session.pause()
        print("PAUSE ARVIEW")
    }

    func onResume() {
        print("RESTART ARVIEW")
        configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration)
    }

    func onSessionMethodCalled(_ call: FlutterMethodCall, _ result: FlutterResult) {
        let arguments = call.arguments as? [String: Any]

        switch call.method {
            case "dispose":
                onDispose()
                result(nil)
            case "pause":
                onPause()
                result(nil)
            case "resume":
                onResume()
                result(nil)
            case "updateNearbyObjects":
                let assetsDict = arguments?["assets"] as? [[String: Any]]
                let ticketsDict = arguments?["tickets"] as? [[String: Any]]
                let assets = assetsDict?.map { AnchorInfo(val: $0) }
                let tickets = ticketsDict?.map { AnchorInfo(val: $0) }
                updateNearbyObjects(newAssets: assets, newTickets: tickets)
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
            case "showAssetTicketsAnchors":
                let assetId = arguments?["assetId"] as! String
                if let asset = nearbyAssets[assetId], let ats = asset.tickets {
                    showAnchors(ids: ats.compactMap { $0.id })
                    hideAssetTickets[assetId] = false
                }
                result(nil)
            case "hideAssetTicketsAnchors":
                let assetId = arguments?["assetId"] as! String
                if let asset = nearbyAssets[assetId], let ats = asset.tickets {
                    hideAnchors(ids: ats.compactMap { $0.id })
                    hideAssetTickets[assetId] = true
                }
                result(nil)
            case "showTicketsAnchors":
                let toHide = arguments?["toShowIds"] as! [String]
                showAnchors(ids: toHide)
                hideTickets = false
                result(nil)
            case "hideTicketsAnchors":
                let toHide = arguments?["toHideIds"] as! [String]
                hideAnchors(ids: toHide)
                hideTickets = true
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
        }
    }

    func updateNearbyObjects(newAssets: [AnchorInfo]?, newTickets: [AnchorInfo]?) {
        NSLog("updateNearbyObjects")
        NSLog("NT LEN: " + String(newTickets?.count ?? 0))
        NSLog("OT LEN: " + String(nearbyTickets.count))

        NSLog("NA LEN: " + String(newAssets?.count ?? 0))
        NSLog("OT LEN: " + String(nearbyAssets.count))
        if newTickets != nil {
            NSLog("ho nuovi geoticket")
            // ho dei nuovi ticket
            for nt in newTickets! {
                // se c'era già lo aggiorno, altrimenti lo aggiungo
                nearbyTickets[nt.id] = nt
                // controllo le anchorvisual se devo aggiornarle
                if anchorVisuals[nt.id] != nil {
                    // aggiorno la visual con il nuovo ticket
                    if nt.ARanchorID != nil {
                        anchorVisuals[nt.id]!.info = nt
                    } else {
                        deleteAnchor(infoId: nt.id)
                    }
                    // forse va aggiornata anche la label del nodo
                }
            }
            if newTickets!.count < nearbyTickets.count {
                NSLog("hanno rimosso geoticket")
                // hanno rimosso dei ticket
                for ot in nearbyTickets.values {
                    if !newTickets!.contains(where: { $0.id == ot.id }) {
                        let id = ot.id
                        // ot non è contenuto nei newTicket, quindi lo tolgo
                        nearbyTickets.removeValue(forKey: id)
                        // elimino anche l' anchor visual
                        deleteAnchor(infoId: id)
                    }
                }
            }
        }

        if newAssets != nil {
            NSLog("ho nuovi asset")
            // ho dei nuovi asset
            for na in newAssets! {
                // controllo le anchorvisual per sapere se devo aggiornare quella dell' asset
                if anchorVisuals[na.id] != nil {
                    // aggiorno la visual con il nuovo asset
                    if na.ARanchorID != nil {
                        anchorVisuals[na.id]!.info = na
                    } else {
                        deleteAnchor(infoId: na.id)
                    }
                    // forse va aggiornata anche la label del nodo
                }
                // controllo le anchorvisual per sapere se devo aggiornare quelle dei ticket dell' asset
                na.tickets?.forEach {
                    if anchorVisuals[$0.id] != nil {
                        // aggiorno la visual con il nuovo asset
                        if $0.ARanchorID != nil {
                            anchorVisuals[$0.id]!.info = $0
                        } else {
                            deleteAnchor(infoId: $0.id)
                        }
                        // forse va aggiornata anche la label del nodo
                    }
                }
                if let nats = na.tickets, let oa = nearbyAssets[na.id], let oats = oa.tickets, nats.count < oats.count {
                    NSLog("hanno rimosso asset ticket")
                    // hanno rimosso degli asset ticket
                    for oat in oats {
                        if !nats.contains(where: { $0.id == oat.id }) {
                            let id = oat.id
                            // oat non è contenuto nei newAssetsTickets, quindi lo tolgo
                            oa.tickets = oa.tickets?.filter { $0.id != id }
                            // elimino anche l' anchor visual
                            deleteAnchor(infoId: id)
                        }
                    }
                }
                // se c'era già lo aggiorno, altrimenti lo aggiungo
                nearbyAssets[na.id] = na
            }
            if newAssets!.count < nearbyAssets.count {
                NSLog("hanno rimosso asset")
                // hanno rimosso degli asset
                for oa in nearbyAssets.values {
                    if !newAssets!.contains(where: { $0.id == oa.id }) {
                        let id = oa.id
                        // elimino le visual dei ticket dell'asset
                        oa.tickets?.forEach { deleteAnchor(infoId: $0.id) }
                        // oa non è contenuto nei newAssets, quindi lo tolgo
                        nearbyAssets.removeValue(forKey: id)
                        // elimino anche l' anchor visual
                        deleteAnchor(infoId: id)
                    }
                }
            }
        }
        lookForNearbyAnchors()
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
        lookForNearbyAnchors()
    }

    func lookForNearbyAnchors() {
        if (nearbyAssets.count < 1 && nearbyTickets.count < 1) || cloudSession == nil {
            return
        }
        // compactMap rimuove gli elementi a nil
        // attualmente non sto cercando gli anchor dei ticket degli asset
        var ids: [String] = []
        for asset in nearbyAssets.values {
            if let assetARanchor = asset.ARanchorID {
                ids.append(assetARanchor)
            }
            if let t = asset.tickets {
                ids.append(contentsOf: t.compactMap { $0.ARanchorID })
            }
        }
        ids.append(contentsOf: nearbyTickets.compactMapValues { $0.ARanchorID }.values)
        print("SEARCHING ANCHORS", ids)
        let criteria = ASAAnchorLocateCriteria()!
        criteria.identifiers = ids
        let ws = cloudSession!.getActiveWatchers()
        ws?.first?.stop()
        cloudSession!.createWatcher(criteria)
    }

    func stopSession() {
        if let cloudSession = cloudSession {
            cloudSession.stop()
            cloudSession.dispose()
        }
        cloudSession = nil

        for visual in anchorVisuals.values {
            visual.node?.removeFromParentNode()
            sceneView.session.remove(anchor: visual.localAnchor)
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
            let newArAnchorId = pav.cloudAnchor!.identifier
            if let asset = nearbyAssets[id] {
                asset.ARanchorID = newArAnchorId
            } else if let ticket = nearbyTickets[id] {
                ticket.ARanchorID = newArAnchorId
            } else if let assetTicket = nearbyAssets.values.filter({ $0.tickets != nil }).flatMap({ $0.tickets ?? [] }).first(where: { $0.id == id }) {
                assetTicket.ARanchorID = newArAnchorId
            }
            anchorVisuals[id] = pav
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
        print("ALL ANCHORS", anchorVisuals.keys)
        print("HIDE ANCHORS", ids)
        ids.forEach { if anchorVisuals[$0] != nil { anchorVisuals[$0]!.hide() }}
    }

    func showAnchors(ids: [String]) {
        print("ALL ANCHORS", anchorVisuals.keys)
        print("SHOW ANCHORS", ids)
        ids.forEach { if anchorVisuals[$0] != nil { anchorVisuals[$0]!.show() }}
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if anchor as? ARPlaneAnchor != nil {
            // se è un anchor plane ignoro
            return
        }
        // anchor creato
        if let pav = pendingAnchorVisual, pav.localAnchor == anchor {
            pav.renderNode(node: node, hidden: false)
            return
        }
        // anchor localizzato
        for visual in anchorVisuals.values {
            if visual.localAnchor == anchor {
                if nearbyAssets[visual.id] != nil {
                    // significa che l'anchor individuato è di un asset
                    visual.renderNode(node: node, hidden: false)
                } else if nearbyTickets[visual.id] != nil {
                    // significa che l'anchor individuato è di un ticket
                    visual.renderNode(node: node, hidden: hideTickets)
                } else if let asset = nearbyAssets.values.first(where: { $0.tickets?.contains(where: { $0.id == visual.id }) ?? false }) {
                    // significa che l'anchor individuato è di un assetTicket
                    visual.renderNode(node: node, hidden: hideAssetTickets[asset.id] ?? true)
                }
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
        // NSLog(String(status.recommendedForCreateProgress))
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
            NSLog("deleteAnchor")
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
                    if let asset = self.nearbyAssets[infoId] {
                        asset.ARanchorID = nil
                    } else if let ticket = self.nearbyTickets[infoId] {
                        ticket.ARanchorID = nil
                    } else if let assetTicket = self.nearbyAssets.values.filter({ $0.tickets != nil }).flatMap({ $0.tickets ?? [] }).first(where: { $0.id == infoId }) {
                        assetTicket.ARanchorID = nil
                    }
                    result(true)
                }
            })
        }
    }

    internal func anchorLocated(_ cloudSpatialAnchorSession: ASACloudSpatialAnchorSession!, _ args: ASAAnchorLocatedEventArgs!) {
        let status = args.status
        switch status {
            case .located, .alreadyTracked:
                let cloudAnchor = args.anchor
                print("Cloud Anchor found! Identifier: \(cloudAnchor!.identifier ?? "nil").")
                // cerco prima negli asset
                if let asset = nearbyAssets.values.first(where: { $0.ARanchorID == cloudAnchor?.identifier }) {
                    if anchorVisuals[asset.id] == nil {
                        let visual = AnchorVisual(localAnchor: cloudAnchor!.localAnchor, info: asset)
                        visual.cloudAnchor = cloudAnchor
                        anchorVisuals[asset.id] = visual
                        sceneView.session.add(anchor: cloudAnchor!.localAnchor)
                    }
                    // cerco nei ticket
                } else if let ticket = nearbyTickets.values.first(where: { $0.ARanchorID == cloudAnchor?.identifier }) {
                    if anchorVisuals[ticket.id] == nil {
                        let visual = AnchorVisual(localAnchor: cloudAnchor!.localAnchor, info: ticket)
                        visual.cloudAnchor = cloudAnchor
                        anchorVisuals[ticket.id] = visual
                        sceneView.session.add(anchor: cloudAnchor!.localAnchor)
                    }
                    // cerco nei ticket dentro gli asset
                } else if let assetTicket = nearbyAssets.values.filter({ $0.tickets != nil }).flatMap({ $0.tickets ?? [] }).first(where: { $0.ARanchorID == cloudAnchor?.identifier }) {
                    if anchorVisuals[assetTicket.id] == nil {
                        let visual = AnchorVisual(localAnchor: cloudAnchor!.localAnchor, info: assetTicket)
                        visual.cloudAnchor = cloudAnchor
                        anchorVisuals[assetTicket.id] = visual
                        sceneView.session.add(anchor: cloudAnchor!.localAnchor)
                    }
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

        if let nodeHitResultName = allHitResults.first?.node.name {
            NSLog("onNodeTap")
            NSLog(nodeHitResultName)
            if let visual = anchorVisuals[nodeHitResultName] {
                switch visual.info.type {
                    case "asset":
                        anchorManagerChannel.invokeMethod("onAssetTap", arguments: nodeHitResultName)
                    case "ticket":
                        anchorManagerChannel.invokeMethod("onTicketTap", arguments: nodeHitResultName)
                    default:
                        NSLog("ERROR: node tapped unrecognized")
                }
            }
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
