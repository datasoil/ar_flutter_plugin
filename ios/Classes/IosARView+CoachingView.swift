//
//  IosARView+CoachingView.swift
//  ar_flutter_plugin
//
//  Created by datasoil on 27/06/23.
//

import Foundation

extension IosARView: ARCoachingOverlayViewDelegate {
    func initializeCoachingView() {
        coachingView.delegate = self
        if coachingView.superview == nil {
            sceneView.addSubview(coachingView)
            coachingView.autoresizingMask = [
                .flexibleWidth, .flexibleHeight
            ]
            coachingView.session = sceneView.session
            coachingView.activatesAutomatically = true
            coachingView.goal = .tracking
        }
    }

    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        // use this delegate method to hide anything in the UI that could cover the coaching overlay view
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        // Reset the session.
        sceneView.session.run(configuration, options: [.resetTracking])
    }
}
