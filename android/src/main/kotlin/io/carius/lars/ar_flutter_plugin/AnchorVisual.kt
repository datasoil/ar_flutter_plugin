// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
package io.carius.lars.ar_flutter_plugin

import android.content.Context
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import com.google.ar.core.Anchor
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.Scene
import com.google.ar.sceneform.rendering.ViewRenderable
import com.google.ar.sceneform.ux.TransformableNode
import com.microsoft.azure.spatialanchors.CloudSpatialAnchor


internal class AnchorVisual(val localAnchor: Anchor, var info: AnchorInfo) {
    val id = info.id
    var cloudAnchor: CloudSpatialAnchor? = null
    private val node = AnchorNode(localAnchor)
    var hidden = false

    fun render(context: Context, scene: Scene, hidden: Boolean) {
        ViewRenderable.builder().setView(context, R.layout.ar_label_extended).build()
            .thenAccept { renderable: ViewRenderable ->
                //Log.d("RENDER NODE", "${info.type} ${info.name} hidden: $hidden")
                val tickets_row: View = renderable.view.findViewById(R.id.tickets_row)
                val parent: View = renderable.view
                val title_lbl: TextView = renderable.view.findViewById(R.id.cod_label)
                renderable.isShadowReceiver = false
                renderable.isShadowCaster = false
                title_lbl.text = info.name
                if (info.type == "asset") {
                    (parent.findViewById<View>(R.id.main_icon) as ImageView).setImageResource(R.drawable.ar_icon)
                    if (info.tickets != null && info.tickets!!.size > 0) {
                        tickets_row.visibility = View.VISIBLE
                        (tickets_row.findViewById<View>(R.id.tickets_icon) as ImageView).setImageResource(
                            R.drawable.ar_maint_icon
                        )
                        (tickets_row.findViewById<View>(R.id.tickets_title) as TextView).text =
                            "${info.tickets!!.size} tickets"
                    }
                } else if (info.type == "ticket") {
                    tickets_row.visibility = View.GONE
                    (parent.findViewById<View>(R.id.main_icon) as ImageView).setImageResource(R.drawable.ar_maint_icon)
                }
                this.node.isEnabled = !hidden
                this.node.renderable = renderable
                this.node.name = this.id
                this.node.parent = scene
            }
    }

    fun dispose() {
        this.node.renderable = null
        this.node.parent = null
        this.node.anchor = null
        this.localAnchor.detach()

    }

    fun show() {
        this.node.isEnabled = true
    }

    fun hide() {
        this.node.isEnabled = false
    }

    override fun toString(): String {
        return "AnchorVisualAsset(id: $id, info: ${info}, cloudAnchor: ${cloudAnchor.toString()}, node: ${node.toString()}, localAnchor: ${localAnchor.toString()})"
    }
}