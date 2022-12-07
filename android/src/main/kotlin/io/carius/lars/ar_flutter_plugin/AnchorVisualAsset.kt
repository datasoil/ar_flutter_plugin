// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
package io.carius.lars.ar_flutter_plugin

import android.content.Context
import android.util.Log
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import com.google.ar.core.Anchor
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.Scene
import com.google.ar.sceneform.rendering.Material
import com.google.ar.sceneform.rendering.Renderable
import com.google.ar.sceneform.rendering.ViewRenderable
import com.google.ar.sceneform.ux.TransformableNode
import com.google.ar.sceneform.ux.TransformationSystem
import com.microsoft.azure.spatialanchors.CloudSpatialAnchor
import io.carius.lars.ar_flutter_plugin.Serialization.deserializeMatrix4
import java.util.concurrent.CompletableFuture

internal class AnchorVisualAsset(_localAnchor: Anchor, val asset: Asset, val name: String) {
    var cloudAnchor: CloudSpatialAnchor? = null
    val node = AnchorNode(_localAnchor)
    val localAnchor = _localAnchor

    fun render(context: Context, scene: Scene){
        Log.d("ArModelBuilder", "makeNodeFromAsset")
        ViewRenderable.builder()
            .setView(context, R.layout.ar_label_extended)
            .build()
            .thenAccept{ renderable: ViewRenderable ->
                val extra: View = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.extra_info)
                val parent: View = renderable.view
                val asset_cod: TextView = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.cod_label)
                renderable.isShadowReceiver=false
                renderable.isShadowCaster=false
                asset_cod.text = asset.cod
                (parent.findViewById(io.carius.lars.ar_flutter_plugin.R.id.main_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.ar_alert_icon)
                this.node.renderable = renderable
                this.node.setParent(scene)
            }
    }



}