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
import com.google.ar.sceneform.rendering.ViewRenderable
import com.microsoft.azure.spatialanchors.CloudSpatialAnchor


internal class AnchorVisualAsset(_localAnchor: Anchor, private val asset: Asset, val name: String) {
    var cloudAnchor: CloudSpatialAnchor? = null
    private val node = AnchorNode(_localAnchor)
    val localAnchor = _localAnchor
    private val TAG: String = AndroidARView::class.java.name

    fun render(context: Context, scene: Scene) {
        Log.d(TAG, "render")
        ViewRenderable.builder().setView(context, R.layout.ar_label_extended).build()
            .thenAccept { renderable: ViewRenderable ->
                val extra: View = renderable.view.findViewById(R.id.extra_info)
                val parent: View = renderable.view
                val assetCod: TextView = renderable.view.findViewById(R.id.cod_label)
                if (asset.events.size > 0) {
                    (parent.findViewById<View>(R.id.main_icon) as ImageView).setImageResource(R.drawable.ar_alert_icon)
                } else if (asset.tickets.size > 0) {
                    (parent.findViewById<View>(R.id.main_icon) as ImageView).setImageResource(R.drawable.ar_maint_icon)
                }
                renderable.isShadowReceiver = false
                renderable.isShadowCaster = false
                assetCod.text = asset.cod
                extra.visibility = View.VISIBLE
                if (asset.function != null) {
                    val functionL: TextView = renderable.view.findViewById(R.id.function_label)
                    var strExtra = asset.function!!.cod
                    if (asset.category != null) {
                        strExtra += " - " + asset.category!!.cod
                    }
                    functionL.text = strExtra
                }
                if (asset.events.size > 0) {
                    (extra.findViewById<View>(R.id.events_title) as TextView).setTextColor(
                        context.getColor(
                            R.color.events_red
                        )
                    )
                    (extra.findViewById<View>(R.id.events_icon) as ImageView).setImageResource(R.drawable.alert_red)
                    (extra.findViewById<View>(R.id.events_label) as TextView).text =
                        asset.events[0].toString()
                }
                if (asset.tickets.size > 0) {
                    (extra.findViewById<View>(R.id.tickets_title) as TextView).setTextColor(
                        context.getColor(
                            R.color.tickets_orange
                        )
                    )
                    (extra.findViewById<View>(R.id.tickets_icon) as ImageView).setImageResource(R.drawable.maint_orange)
                    (extra.findViewById<View>(R.id.tickets_label) as TextView).text =
                        asset.tickets[0].toString()
                }
                this.node.renderable = renderable
                this.node.name = this.name
                this.node.setParent(scene)
            }
    }

    fun dispose() {
        Log.d(TAG, "dispose")
        this.node.renderable=null
        Log.d(TAG, "renderable")
        this.node.setParent(null)
        Log.d(TAG, "parent")
        this.node.anchor=null
        Log.d(TAG, "anchor")
        this.localAnchor.detach()
        Log.d(TAG, "detached anchor")

    }

    override fun toString(): String {
        return "AnchorVisualAsset(name: $name, asset: ${asset.toString()}, cloudAnchor: ${cloudAnchor.toString()}, node: ${node.toString()}, localAnchor: ${localAnchor.toString()})"
    }
}