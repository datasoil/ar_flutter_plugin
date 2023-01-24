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
import com.google.ar.sceneform.FrameTime
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.Scene
import com.google.ar.sceneform.math.Quaternion
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.ViewRenderable
import com.microsoft.azure.spatialanchors.CloudSpatialAnchor


internal class AnchorVisual(val localAnchor: Anchor, var info: AnchorInfo): AnchorNode(localAnchor) {
    val id = info.id
    var cloudAnchor: CloudSpatialAnchor? = null
    //private val node = AnchorNode(localAnchor)
    private val visual = Node()

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
                this.visual.renderable=renderable
                this.visual.isEnabled = !hidden
                this.visual.name = this.id
                this.visual.parent=this
                this.parent = scene
            }
    }

    override fun onUpdate(frameTime: FrameTime?) {
        super.onUpdate(frameTime)
        if(scene == null){
            return
        }

        val cameraPosition = scene!!.camera.worldPosition
        val cardPosition: Vector3 = visual.worldPosition
        val direction = Vector3.subtract(cameraPosition, cardPosition)
        val lookRotation: Quaternion = Quaternion.lookRotation(direction, Vector3.up())
        visual.worldRotation = lookRotation

    }

    fun dispose() {
        this.visual.renderable = null
        this.visual.parent = null
        this.parent=null
        this.anchor=null
        this.localAnchor.detach()

    }

    fun show() {
        this.visual.isEnabled = true
    }

    fun hide() {
        this.visual.isEnabled = false
    }

    override fun toString(): String {
        return "AnchorVisualAsset(id: $id, info: ${info}, cloudAnchor: ${cloudAnchor.toString()}, node: ${this.toString()}, localAnchor: ${localAnchor.toString()})"
    }
}