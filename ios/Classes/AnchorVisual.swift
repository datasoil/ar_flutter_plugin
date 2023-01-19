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
        let sk = SKScene(size: CGSize(width: 1500, height: 1000))
        sk.backgroundColor = UIColor.clear
        // sk.anchorPoint = CGPoint(x:0,y:2024/4)
        var icon = "armarker_normal_png"
        if info.type == "ticket" {
            icon = "armarker_ticket_png"
        }
        let markerNode = SKSpriteNode(imageNamed: icon)
        markerNode.size = CGSize(width: 496, height: 496)
        markerNode.position = CGPoint(x: sk.size.width/2.0, y: sk.size.height/4.0)
       
        let controlrectangle = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 1500, height: 1000), cornerRadius: 10)
        controlrectangle.fillColor = UIColor.black
        controlrectangle.strokeColor = UIColor.red
        controlrectangle.lineWidth = 15
        controlrectangle.alpha = 0.3
      
        let rectangle = SKShapeNode(rect: CGRect(x: 0, y: sk.size.height/2.0, width: 1500, height: sk.size.height/2.0), cornerRadius: 10)
        rectangle.fillColor = UIColor.black
        // rectangle.strokeColor = UIColor.white
        // rectangle.lineWidth = 5
        rectangle.alpha = 0.8
           
        let lbl = SKLabelNode(text: info.name)
        lbl.fontSize = 130
        lbl.numberOfLines = 0
        lbl.fontColor = UIColor.white
        lbl.fontName = "Helvetica-Bold"
        lbl.position = CGPoint(x: sk.size.width/2.0, y: 3.0*sk.size.height/4.0)
        lbl.preferredMaxLayoutWidth = 1500
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        // lbl.zRotation = .pi// not needed as we apply the transformation later
        
        sk.addChild(rectangle)
        sk.addChild(lbl)
        sk.addChild(markerNode)
        //  sk.addChild(controlrectangle)
       
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
    
    func hide() {
        node?.isHidden = true
    }

    func show() {
        node?.isHidden = false
    }
}
