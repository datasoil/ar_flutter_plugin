//
//  IosARView+Handlers.swift
//  ar_flutter_plugin
//
//  Created by datasoil on 27/06/23.
//

import Foundation

extension IosARView {
    func onDispose() {
        NSLog("IosARView: onDispose")
        NSLog("IosARView: stopCloudSession")
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
        sceneView.session.pause()
        sceneView.session.delegate = nil
        sceneView.removeFromSuperview()
        sceneView.window?.resignKey()
        sessionRunning = false
        channel.setMethodCallHandler(nil)
    }

    func onPause() {
        NSLog("IosARView: onPause")
        sceneView.session.pause()
        sessionRunning = false
    }

    func onResume() {
        NSLog("IosARView: onResume")
        if configuration == nil {
            configuration = ARWorldTrackingConfiguration()
            configuration.environmentTexturing = .automatic
            configuration.planeDetection = [.horizontal, .vertical]
        }
        sceneView.session.run(configuration)
        sessionRunning = true
    }

    func updateNearbyObjects(newAssets: [AnchorInfo]?, newTickets: [AnchorInfo]?) {
        NSLog("IosARView: updateNearbyObjects")
        NSLog("NewTickets LEN: " + String(newTickets?.count ?? 0))
        NSLog("OldTickets LEN: " + String(nearbyTickets.count))

        NSLog("NewAssets LEN: " + String(newAssets?.count ?? 0))
        NSLog("OldAssets LEN: " + String(nearbyAssets.count))
        if newTickets != nil {
            // ho dei nuovi ticket
            for nt in newTickets! {
                // se c'era già lo aggiorno, altrimenti lo aggiungo
                nearbyTickets[nt.id] = nt
                // controllo le anchorvisual se devo aggiornarle
                if anchorVisuals[nt.id] != nil {
                    // aggiorno la visual con il nuovo ticket
                    if nt.ARanchorID != nil {
                        anchorVisuals[nt.id]!.info = nt
                        anchorVisuals[nt.id]?.updateVisual()
                    } else {
                        deleteAnchor(infoId: nt.id)
                    }
                    // forse va aggiornata anche la label del nodo
                }
            }
            if newTickets!.count < nearbyTickets.count {
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
            // ho dei nuovi asset
            for na in newAssets! {
                // controllo le anchorvisual per sapere se devo aggiornare quella dell' asset
                if anchorVisuals[na.id] != nil {
                    // aggiorno la visual con il nuovo asset
                    if na.ARanchorID != nil {
                        anchorVisuals[na.id]!.info = na
                        anchorVisuals[na.id]?.updateVisual()
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
                            anchorVisuals[$0.id]?.updateVisual()
                        } else {
                            deleteAnchor(infoId: $0.id)
                        }
                        // forse va aggiornata anche la label del nodo
                    }
                }
                if let nats = na.tickets, let oa = nearbyAssets[na.id], let oats = oa.tickets, nats.count < oats.count {
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

    func lookForNearbyAnchors() {
        NSLog("IosARView: lookForNearbyAnchors")
        if (nearbyAssets.count < 1 && nearbyTickets.count < 1) || cloudSession == nil {
            NSLog("IosARView: ERROR can't lookForNearbyAnchors")
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
        print("SEARCHING ANCHORS IDS", ids)
        let criteria = ASAAnchorLocateCriteria()!
        criteria.identifiers = ids
        let ws = cloudSession!.getActiveWatchers()
        ws?.first?.stop()
        cloudSession!.createWatcher(criteria)
    }

    func startPositioning(toHideIds: [String]?) {
        NSLog("IosARView: startPositioning")
        if toHideIds != nil {
            hideAnchors(ids: toHideIds!)
        }
        enableTapToAdd = true
    }

    func successPositioning(toShowIds: [String]?) {
        NSLog("IosARView: successPositioning")
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
        NSLog("IosARView: abortPositioning")
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
        NSLog("IosARView: hideAnchors")
        print("ALL ANCHORS", anchorVisuals.keys)
        print("HIDE ANCHORS", ids)
        ids.forEach { if anchorVisuals[$0] != nil { anchorVisuals[$0]!.hide() }}
    }

    func showAnchors(ids: [String]) {
        NSLog("IosARView: showAnchors")
        print("ALL ANCHORS", anchorVisuals.keys)
        print("SHOW ANCHORS", ids)
        ids.forEach { if anchorVisuals[$0] != nil { anchorVisuals[$0]!.show() }}
    }

    func createAnchor(transform: [NSNumber], info: AnchorInfo) {
        NSLog("IosARView: createAnchor")
        let arAnchor = ARAnchor(transform: simd_float4x4(deserializeMatrix4(transform)))
        sceneView.session.add(anchor: arAnchor)
        pendingAnchorVisual = AnchorVisual(localAnchor: arAnchor, info: info)
    }

    func deleteAnchor(infoId: String) {
        NSLog("IosARView: deleteAnchor")
        if let v = anchorVisuals[infoId] {
            sceneView.session.remove(anchor: v.localAnchor)
            anchorVisuals.removeValue(forKey: infoId)
        }
    }

    func uploadAnchor(result: @escaping FlutterResult) {
        NSLog("IosARView: uploadAnchor")
        if let pav = pendingAnchorVisual {
            let cloudAnchor = ASACloudSpatialAnchor()
            cloudAnchor!.localAnchor = pav.localAnchor

            // In this sample app we delete the cloud anchor explicitly, but you can also set it to expire automatically
            /*let secondsInADay = 60 * 60 * 24
            let oneWeekFromNow = Date(timeIntervalSinceNow: TimeInterval(secondsInADay * 2))
            cloudAnchor!.expiration = oneWeekFromNow
            */
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
        NSLog("IosARView: deleteCloudAnchor")
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
}
