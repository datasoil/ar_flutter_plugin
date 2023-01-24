// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
import Foundation

class AnchorVisual {
    var node: SCNNode?
    // id dell'asset per AnchorAsset, id del ticket per AnchorTicket
    var id: String
    var cloudAnchor: ASACloudSpatialAnchor?
    var localAnchor: ARAnchor
    var info: AnchorInfo
    
    init(localAnchor: ARAnchor, info: AnchorInfo) {
        self.id = info.id
        self.localAnchor = localAnchor
        self.info = info
    }
    
    // var arLabel: SKLabelNode? = nil
    
    func createLabelMaterial() -> SCNMaterial {
        let assetWTickets =  info.type == "asset" && info.tickets?.isEmpty == false
        let w = assetWTickets ? 1600 : 800 as Double
        let h = assetWTickets ? 1000 : 500 as Double
        let sk = SKScene(size: CGSize(width: w, height: h))
        sk.backgroundColor = UIColor.clear
        var icon = "armarker_normal_png"
        if info.type == "ticket" {
            icon = "armarker_ticket_png"
        }
        let mns = assetWTickets ? 496 : 248 as Double
        let markerNode = SKSpriteNode(imageNamed: icon)
        markerNode.size = CGSize(width: mns, height: mns)
        markerNode.position = CGPoint(x: w/2.0, y: h/4.0)
        
        let rectangle = SKShapeNode(rect: CGRect(x: 0, y: h/2.0, width: w, height: h/2.0), cornerRadius: 10)
        rectangle.fillColor = UIColor.black
        rectangle.alpha = 0.9
           
        let lblY = assetWTickets ? 7.0*h/8.0 : 3.0*h/4.0
        let lbl = SKLabelNode(text: info.name)
        lbl.fontSize = assetWTickets ? 130 : 100
        lbl.numberOfLines = 0
        lbl.fontColor = UIColor.white
        lbl.fontName = "Helvetica-Bold"
        lbl.position = CGPoint(x: w/2.0, y: lblY)
        lbl.preferredMaxLayoutWidth = w
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        
        
        
        sk.addChild(rectangle)
        sk.addChild(lbl)
        sk.addChild(markerNode)
        if(assetWTickets){
            let aTktMarker = SKSpriteNode(imageNamed:  "armarker_ticket_png")
            aTktMarker.size = CGSize(width: 200, height: 200)
            aTktMarker.position = CGPoint(x: w/4.0, y: 5.0*h/8.0)
            let tktLbl = String(info.tickets!.count) + (info.tickets!.count>1 ? " tickets" : " ticket")
            let aTkLbl = SKLabelNode(text: tktLbl)
            aTkLbl.fontSize = 130
            aTkLbl.numberOfLines = 0
            aTkLbl.fontColor = UIColor.white
            aTkLbl.fontName = "Helvetica"
            aTkLbl.position = CGPoint(x: 3.0*w/8.0, y: 5.0*h/8.0)
            aTkLbl.preferredMaxLayoutWidth = 800
            aTkLbl.horizontalAlignmentMode = .left
            aTkLbl.verticalAlignmentMode = .center
            sk.addChild(aTktMarker)
            sk.addChild(aTkLbl)
        }
       
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.diffuse.contents = sk
        return material
    }
    
    func renderNode(node: SCNNode, hidden: Bool) {
        // see if we need to initialize node
        if self.node == nil {
            let yFreeConstraint = SCNBillboardConstraint()
            yFreeConstraint.freeAxes = [.Y, .X] // optionally
            node.constraints = [yFreeConstraint]
            node.geometry = SCNPlane(width: 0.4, height: 0.4*2.0/3.0)
            node.name = id
            let label: SCNMaterial = createLabelMaterial()
            let plane = node.geometry as! SCNPlane
            node.geometry?.materials = [label]
            node.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
            node.position = SCNVector3(x: 0, y: Float(plane.height)/4.0, z: 0)
            if hidden {
                node.isHidden = true
            } else {
                node.isHidden = false
            }
            self.node = node
        }
    }
    func updateVisual(){
        if let node = self.node{
            let label: SCNMaterial = createLabelMaterial()
            node.geometry?.materials = [label]
            node.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
        }
    }
    func hide() {
        node?.isHidden = true
    }

    func show() {
        node?.isHidden = false
    }
}
