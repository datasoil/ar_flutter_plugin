import ARKit
import Combine
import Flutter
import Foundation
import UIKit

class IosARView: NSObject, FlutterPlatformView {
    let sceneView: ARSCNView
    let coachingView: ARCoachingOverlayView
    let channel: FlutterMethodChannel

    var configuration: ARWorldTrackingConfiguration!

    var enableTapToAdd = false
    var pendingAnchorVisual: AnchorVisual?
    var anchorVisuals = [String: AnchorVisual]()
    var cloudSession: ASACloudSpatialAnchorSession?
    var mainWatcher: ASACloudSpatialAnchorWatcher?
    private var apiKey: String!
    private var apiId: String!
    var nearbyAssets = [String: AnchorInfo]()
    var nearbyTickets = [String: AnchorInfo]()
    var hideAssetTickets = [String: Bool]()
    var hideTickets = false
    var sessionRunning = false

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        NSLog("IosARView: init")
        if let argumentsDictionary = args as? [String: Any] {
            self.apiId = argumentsDictionary["apiId"] as? String
            self.apiKey = argumentsDictionary["apiKey"] as? String
        }
        self.sceneView = ARSCNView(frame: frame)
        self.coachingView = ARCoachingOverlayView(frame: frame)
        self.channel = FlutterMethodChannel(name: "archannel_\(viewId)", binaryMessenger: messenger)
        super.init()

        sceneView.delegate = self

        channel.setMethodCallHandler(onMethodCalled)
        initalizeGestureRecognizers()
        initializeCoachingView()

        self.configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration)
        self.sessionRunning = true

        NSLog("IosARView: startCloudSession")
        if cloudSession != nil {
            return
        }
        self.cloudSession = ASACloudSpatialAnchorSession()
        cloudSession!.session = sceneView.session
        cloudSession!.logLevel = .error
        cloudSession!.delegate = self
        cloudSession!.configuration.accountId = apiId
        cloudSession!.configuration.accountKey = apiKey
        cloudSession!.start()
        print("Cloud session STARTED")
    }

    func view() -> UIView {
        return sceneView
    }

    func onMethodCalled(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        NSLog("IosARView: onAnchorMethodCalled \(call.method)")
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
}
