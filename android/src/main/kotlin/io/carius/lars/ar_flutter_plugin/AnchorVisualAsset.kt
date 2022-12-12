// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
package io.carius.lars.ar_flutter_plugin

import android.R
import android.content.Context
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import androidx.annotation.RequiresApi
import com.google.ar.core.Anchor
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.Scene
import com.google.ar.sceneform.rendering.ViewRenderable
import com.microsoft.azure.spatialanchors.CloudSpatialAnchor


internal class AnchorVisualAsset(_localAnchor: Anchor, val asset: Asset, val name: String) {
    var cloudAnchor: CloudSpatialAnchor? = null
    val node = AnchorNode(_localAnchor)
    val localAnchor = _localAnchor

    @RequiresApi(Build.VERSION_CODES.O)
    fun render(context: Context, scene: Scene){
        Log.d("ArModelBuilder", "makeNodeFromAsset")
        ViewRenderable.builder()
            .setView(context, io.carius.lars.ar_flutter_plugin.R.layout.ar_label_extended)
            .build()
            .thenAccept{ renderable: ViewRenderable ->
                val extra: View = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.extra_info)
                val parent: View = renderable.view
                val asset_cod: TextView = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.cod_label)
                if (asset.Events != null && asset.Events.size > 0) {
                    (parent.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.main_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.ar_alert_icon)
                } else if (asset.Tickets != null && asset.Tickets.size > 0) {
                    (parent.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.main_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.ar_maint_icon)
                }
                renderable.isShadowReceiver=false
                renderable.isShadowCaster=false
                asset_cod.text = asset.Cod
                extra.visibility=View.VISIBLE
                if(asset.Function!=null){
                    val function_label: TextView = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.function_label)
                    var strExtra = asset.Function!!.Cod
                    if(asset.FuncCategory!=null){
                        strExtra+=" - " + asset.FuncCategory!!.Cod
                    }
                    function_label.text = strExtra
                }
                if (asset.Events != null && asset.Events.size > 0) {
                    (extra.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.events_title) as TextView).setTextColor(
                        context.getColor(
                            io.carius.lars.ar_flutter_plugin.R.color.events_red
                        )
                    )
                    (extra.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.events_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.alert_red)
                    (extra.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.events_label) as TextView).text =
                        asset.Events[0].toString()
                }
                if (asset.Tickets != null && asset.Tickets.size > 0) {
                    (extra.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.tickets_title) as TextView).setTextColor(
                        context.getColor(
                            io.carius.lars.ar_flutter_plugin.R.color.tickets_orange
                        )
                    )
                    (extra.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.tickets_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.maint_orange)
                    (extra.findViewById<View>(io.carius.lars.ar_flutter_plugin.R.id.tickets_label) as TextView).text =
                        asset.Tickets[0].toString()
                }
                //(parent.findViewById(io.carius.lars.ar_flutter_plugin.R.id.main_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.ar_alert_icon)
                this.node.renderable = renderable
                this.node.name = this.name
                this.node.setParent(scene)
            }
    }



}