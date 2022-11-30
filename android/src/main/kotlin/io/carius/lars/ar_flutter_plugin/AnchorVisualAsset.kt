// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
package io.carius.lars.ar_flutter_plugin

import android.content.Context
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.Plane
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.HitTestResult
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.collision.Box
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.Material
import com.google.ar.sceneform.rendering.Renderable
import com.google.ar.sceneform.rendering.ViewRenderable
import com.google.ar.sceneform.ux.ArFragment
import com.microsoft.azure.spatialanchors.CloudSpatialAnchor
import java.math.RoundingMode

internal class AnchorVisualAsset(val node: AnchorNode, val asset: Asset) {
    var cloudAnchor: CloudSpatialAnchor? = null
    private val color: Material? = null
    private var nodeRenderable: Renderable? = null
    private var ctx: Context? = null

    val localAnchor: Anchor?
        get() = node.anchor



    fun destroy() {
        this.node.renderable = null
        this.node.setParent(null)
    }

}