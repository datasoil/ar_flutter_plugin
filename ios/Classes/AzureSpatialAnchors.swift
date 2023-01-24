//
//  AzureSpatialAnchors.swift
//  ASARmodule
//
//  Created by Pietro De Caro on 17/10/2019.
//  Copyright © 2019 Facebook. All rights reserved.
//

import Foundation

@objc(AzureSpatialAnchors)
class AzureSpatialAnchors: NSObject {
  
  static var SpatialAnchorsAccountId:String = "NOT SET"
  static var SpatialAnchorsAccountKey:String = "NOT SET"
  
  @objc func setCredentials(_ apiID:String, apiKey:String) {
    AzureSpatialAnchors.SpatialAnchorsAccountId = apiID
    AzureSpatialAnchors.SpatialAnchorsAccountKey = apiKey
  }
  
  @objc static func requiresMainQueueSetup() -> Bool {
      return false
    }
}
