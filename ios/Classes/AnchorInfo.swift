//
//  AnchorInfo.swift
//  RNAzureSpatialAnchors
//
//  Created by Pietro De Caro on 21/11/2019.
//  Copyright © 2019 Facebook. All rights reserved.
//

import Foundation

class BadgeInfo {
    var count: Int
    var icon: String
    
    init(val: [String: Any]) {
        count = val["count"] as! Int
        icon = val["icon"] as! String
    }
}

class AnchorInfo: Hashable {
    var id: String
    var name: String
    var type: String
    var ARanchorID: String
    var icon: String
    var badges: [BadgeInfo]
    
    init() {
        id = ""
        name = ""
        type = ""
        ARanchorID = ""
        icon = ""
        badges = [BadgeInfo]()
    }
  
    init(val: [String: Any]) {
        id = val["id"] as! String
        type = ""
        icon = ""
        name = val["cod"] as! String
        // icon = val["icon"] as! String
        // type = val["type"] as! String
    
        if let arid = val["ar_anchor"] as? String {
            ARanchorID = arid
        } else {
            ARanchorID = ""
        }
        if let bdgs = val["badges"] as? [[String: Any]] {
            badges = bdgs.map { t -> BadgeInfo in BadgeInfo(val: t) }
        } else {
            badges = [BadgeInfo]()
        }
    }
  
    static func ==(lhs: AnchorInfo, rhs: AnchorInfo) -> Bool {
        return lhs.id == rhs.id
    }
  
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
