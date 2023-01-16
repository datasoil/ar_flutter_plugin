//
//  AnchorInfo.swift
//  RNAzureSpatialAnchors
//
//  Created by Pietro De Caro on 21/11/2019.
//  Copyright © 2019 Facebook. All rights reserved.
//

import Foundation

class Ticket {
    var id: String
    var title: String
    var ts: String
    var ARanchorID: String?
    
    init(val: [String: Any]) {
        id = val["id"] as! String
        title = val["title"] as! String
        ARanchorID = val["ar_anchor"] as? String
        ts = val["ts"] as! String
    }
}

class AnchorInfo: Hashable {
    var id: String
    //name: cod for Asset, title for Ticket
    var name: String
    //type: "asset" for Asset, "ticket" for Ticket
    var type: String
    var ts: String?
    var ARanchorID: String?
    var tickets: [AnchorInfo]?
  
    init(val: [String: Any]) {
        id = val["id"] as! String
        type = val["type"] as! String
        name = val["name"] as! String
        ARanchorID = val["ar_anchor"] as? String
        ts = val["ts"] as? String
        if let tkts = val["tickets"] as? [[String: Any]]{
            tickets = tkts.map { AnchorInfo(val: $0) }
        }
    }
  
    static func ==(lhs: AnchorInfo, rhs: AnchorInfo) -> Bool {
        return lhs.id == rhs.id
    }
  
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
