package io.carius.lars.ar_flutter_plugin

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.assets.RenderableSource
import com.google.ar.sceneform.math.Quaternion
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.*
import com.google.ar.sceneform.ux.TransformableNode
import com.google.ar.sceneform.ux.TransformationSystem
import io.carius.lars.ar_flutter_plugin.Serialization.*
import java.util.concurrent.CompletableFuture


// Responsible for creating Renderables and Nodes
class ArModelBuilder {

    // Creates a coordinate system model at the world origin (X-axis: red, Y-axis: green, Z-axis:blue)
    // The code for this function is adapted from Alexander's stackoverflow answer (https://stackoverflow.com/questions/48908358/arcore-how-to-display-world-origin-or-axes-in-debug-mode) 
    fun makeWorldOriginNode(context: Context): Node {
        val axisSize = 0.1f
        val axisRadius = 0.005f

        val rootNode = Node()
        val xNode = Node()
        val yNode = Node()
        val zNode = Node()

        rootNode.addChild(xNode)
        rootNode.addChild(yNode)
        rootNode.addChild(zNode)

        xNode.worldPosition = Vector3(axisSize / 2, 0f, 0f)
        xNode.worldRotation = Quaternion.axisAngle(Vector3(0f, 0f, 1f), 90f)

        yNode.worldPosition = Vector3(0f, axisSize / 2, 0f)

        zNode.worldPosition = Vector3(0f, 0f, axisSize / 2)
        zNode.worldRotation = Quaternion.axisAngle(Vector3(1f, 0f, 0f), 90f)

        MaterialFactory.makeOpaqueWithColor(context, Color(255f, 0f, 0f))
                .thenAccept { redMat ->
                    xNode.renderable = ShapeFactory.makeCylinder(axisRadius, axisSize, Vector3.zero(), redMat)
                }

        MaterialFactory.makeOpaqueWithColor(context, Color(0f, 255f, 0f))
                .thenAccept { greenMat ->
                    yNode.renderable = ShapeFactory.makeCylinder(axisRadius, axisSize, Vector3.zero(), greenMat)
                }

        MaterialFactory.makeOpaqueWithColor(context, Color(0f, 0f, 255f))
                .thenAccept { blueMat ->
                    zNode.renderable = ShapeFactory.makeCylinder(axisRadius, axisSize, Vector3.zero(), blueMat)
                }

        return rootNode
    }

    // Creates a node form a given gltf model path or URL. The gltf asset loading in Scenform is asynchronous, so the function returns a completable future of type Node
    fun makeNodeFromGltf(context: Context, transformationSystem: TransformationSystem, name: String, modelPath: String, transformation: ArrayList<Double>): CompletableFuture<TransformableNode> {
        val completableFutureNode: CompletableFuture<TransformableNode> = CompletableFuture()

        val gltfNode = TransformableNode(transformationSystem)

        ModelRenderable.builder()
                .setSource(context, RenderableSource.builder().setSource(
                        context,
                        Uri.parse(modelPath),
                        RenderableSource.SourceType.GLTF2)
                        .build())
                .setRegistryId(modelPath)
                .build()
                .thenAccept{ renderable ->
                    gltfNode.renderable = renderable
                    gltfNode.name = name
                    val transform = deserializeMatrix4(transformation)
                    gltfNode.worldScale = transform.first
                    gltfNode.worldPosition = transform.second
                    gltfNode.worldRotation = transform.third
                    completableFutureNode.complete(gltfNode)
                }
                .exceptionally { throwable ->
                    completableFutureNode.completeExceptionally(throwable)
                    null // return null because java expects void return (in java, void has no instance, whereas in Kotlin, this closure returns a Unit which has one instance)
                }

    return completableFutureNode
    }

    // Creates a node form a given glb model path or URL. The gltf asset loading in Sceneform is asynchronous, so the function returns a compleatable future of type Node
    fun makeNodeFromGlb(context: Context, transformationSystem: TransformationSystem, name: String, modelPath: String, transformation: ArrayList<Double>): CompletableFuture<TransformableNode> {
        val completableFutureNode: CompletableFuture<TransformableNode> = CompletableFuture()

        val gltfNode = TransformableNode(transformationSystem)

        ModelRenderable.builder()
                .setSource(context, RenderableSource.builder().setSource(
                        context,
                        Uri.parse(modelPath),
                        RenderableSource.SourceType.GLB)
                        .build())
                .setRegistryId(modelPath)
                .build()
                .thenAccept{ renderable ->
                    gltfNode.renderable = renderable
                    gltfNode.name = name
                    val transform = deserializeMatrix4(transformation)
                    gltfNode.worldScale = transform.first
                    gltfNode.worldPosition = transform.second
                    gltfNode.worldRotation = transform.third
                    completableFutureNode.complete(gltfNode)
                }
                .exceptionally{throwable ->
                    completableFutureNode.completeExceptionally(throwable)
                    null // return null because java expects void return (in java, void has no instance, whereas in Kotlin, this closure returns a Unit which has one instance)
                }

        return completableFutureNode
    }

    // Creates a node form a given asset. The gltf asset loading in Scenform is asynchronous, so the function returns a completable future of type Node
    fun makeNodeFromAsset(activity: Activity, context: Context, transformationSystem: TransformationSystem, asset: Asset, transformation: ArrayList<Double>): CompletableFuture<TransformableNode> {
        val completableFutureNode: CompletableFuture<TransformableNode> = CompletableFuture()
        Log.d("ArModelBuilder", "makeNodeFromAsset")

        val assetNode = TransformableNode(transformationSystem)

        //val rootView = activity.findViewById(android.R.id.content) as ViewGroup
        ViewRenderable.builder()
                .setView(context, R.layout.ar_label_extended)
                .build()
                .thenAccept{ renderable: ViewRenderable ->
                    val extra: View = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.extra_info)
                    val parent: View = renderable.view
                    val asset_cod: TextView = renderable.view.findViewById(io.carius.lars.ar_flutter_plugin.R.id.cod_label)
                    asset_cod.text = asset.cod
                    (parent.findViewById(io.carius.lars.ar_flutter_plugin.R.id.main_icon) as ImageView).setImageResource(io.carius.lars.ar_flutter_plugin.R.drawable.ar_alert_icon)
                    assetNode.renderable = renderable
                    assetNode.name = asset.id
                    val transform = deserializeMatrix4(transformation)
                    assetNode.worldScale = transform.first
                    assetNode.worldPosition = transform.second
                    assetNode.worldRotation = transform.third
                    completableFutureNode.complete(assetNode)
                }
                .exceptionally { throwable ->
                    completableFutureNode.completeExceptionally(throwable)
                    null // return null because java expects void return (in java, void has no instance, whereas in Kotlin, this closure returns a Unit which has one instance)
                }

        return completableFutureNode
    }
}


