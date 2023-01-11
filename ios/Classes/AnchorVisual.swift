// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
import Foundation

class AnchorVisual {
    init() {
        node = nil
        identifier = ""
        cloudAnchor = nil
        localAnchor = nil
    }
    
    var node: SCNNode?
    var identifier: String
    var cloudAnchor: ASACloudSpatialAnchor?
    var localAnchor: ARAnchor?
    var info: AnchorInfo?
    // var arLabel: SKLabelNode? = nil
    
    func createLabelMaterial(text: String)->SCNMaterial {
        let sk = SKScene(size: CGSize(width: 1500, height: 1000))
        sk.backgroundColor = UIColor.clear
        // sk.anchorPoint = CGPoint(x:0,y:2024/4)
        var theIcon = "armarker_normal_png"
        if let chosenIcon = info?.icon {
            if chosenIcon != "" {
                theIcon = chosenIcon
            }
        }
        let markerNode = SKSpriteNode(imageNamed: theIcon)
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
           
        let lbl = SKLabelNode(text: text)
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
    
    func renderNode()->SCNNode {
        // see if we need to initialize node
        if node == nil {
            node = SCNNode()
            node!.geometry = SCNPlane(width: 0.4, height: 0.4*2.0/3.0)
            node!.name = identifier
        }
        var label: SCNMaterial?
        // we allow overriding the text manually
        if let c = info?.name {
            label = createLabelMaterial(text: c)
        } else {
            label = createLabelMaterial(text: "[?ASSET?]")
        }
        
        let plane = node!.geometry as! SCNPlane
        node!.geometry?.materials = [label!]
        node!.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
        node!.position = SCNVector3(x: 0, y: Float(plane.height)/4.0, z: 0)
               
        return node!
    }
}
