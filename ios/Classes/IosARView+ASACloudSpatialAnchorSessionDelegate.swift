//
//  IosARView+ASACloudSpatialAnchorSessionDelegate.swift
//  ar_flutter_plugin
//
//  Created by datasoil on 27/06/23.
//

import Foundation

extension IosARView: ASACloudSpatialAnchorSessionDelegate {
    func onLogDebug(_ cloudSpatialAnchorSession: ASACloudSpatialAnchorSession!, _ args: ASAOnLogDebugEventArgs!) {
        if let message = args.message {
            print(message)
        }
    }

    func sessionUpdated(_ cloudSpatialAnchorSession: ASACloudSpatialAnchorSession!, _ args: ASASessionUpdatedEventArgs!) {
        let status = args.status!

        let enoughDataForSaving = status.recommendedForCreateProgress >= 1.0
        if enoughDataForSaving {
            channel.invokeMethod("readyToUpload", arguments: nil)
        }
    }

    func anchorLocated(_ cloudSpatialAnchorSession: ASACloudSpatialAnchorSession!, _ args: ASAAnchorLocatedEventArgs!) {
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
}
