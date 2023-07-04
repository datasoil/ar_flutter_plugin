//
//  IosARView+ARSCNViewDelegate.swift
//  ar_flutter_plugin
//
//  Created by datasoil on 27/06/23.
//

import Foundation

extension IosARView: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // NSLog("IosARView: renderer didAdd")
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
        if let cloudSession = cloudSession, sessionRunning == true, let frame = sceneView.session.currentFrame {
            cloudSession.processFrame(frame)
        }
    }
}
