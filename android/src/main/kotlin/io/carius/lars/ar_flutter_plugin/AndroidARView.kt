package io.carius.lars.ar_flutter_plugin


import android.R
import android.app.Activity
import android.app.Application
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import com.google.ar.sceneform.*
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.*
import com.google.ar.sceneform.ux.*
import com.microsoft.azure.spatialanchors.*
import io.carius.lars.ar_flutter_plugin.Serialization.deserializeMatrix4
import io.carius.lars.ar_flutter_plugin.Serialization.serializeHitResult
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.collections.set


internal class AndroidARView(
    val activity: Activity,
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView {
    // constants
    private val TAG: String = AndroidARView::class.java.name

    // Lifecycle variables
    private var mUserRequestedInstall = true
    lateinit var activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks
    private val viewContext: Context

    // Platform channels
    private val sessionManagerChannel: MethodChannel = MethodChannel(messenger, "arsession_$id")
    private val objectManagerChannel: MethodChannel = MethodChannel(messenger, "arobjects_$id")
    private val anchorManagerChannel: MethodChannel = MethodChannel(messenger, "aranchors_$id")

    // UI variables
    private lateinit var arSceneView: ArSceneView

    // Setting defaults
    private var footprintSelectionVisualizer = FootprintSelectionVisualizer()


    private lateinit var azureSpatialAnchorsManager: AzureSpatialAnchorsManager
    private val anchorVisuals: ConcurrentHashMap<String, AnchorVisualAsset> = ConcurrentHashMap()

    // Assets
    private var nearbyAssets: ArrayList<Asset> = ArrayList()

    private lateinit var sceneUpdateListener: com.google.ar.sceneform.Scene.OnUpdateListener

    // Method channel handlers
    private val onSessionMethodCall =
        object : MethodChannel.MethodCallHandler {
            override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
                Log.d(TAG, "AndroidARView onsessionmethodcall reveived a call!")
                when (call.method) {
                    "init" -> {
                        initializeARView(call, result)
                    }
                    "dispose" -> {
                        dispose()
                    }
                    else -> {
                    }
                }
            }
        }
    private val onObjectMethodCall =
        object : MethodChannel.MethodCallHandler {
            override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
                Log.d(TAG, "AndroidARView onobjectmethodcall reveived a call!")
                Log.d(TAG, call.method)
            }
        }
    private val onAnchorMethodCall =
        object : MethodChannel.MethodCallHandler {
            override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
                when (call.method) {
                    "addAnchor" -> {
                        val dict_asset: HashMap<String, Any>? =
                            call.argument<HashMap<String, Any>>("asset")
                        val dict_anchor: HashMap<String, Any>? =
                            call.argument<HashMap<String, Any>>("anchor")
                        if (dict_asset != null && dict_anchor != null) {
                            val transform: ArrayList<Double> =
                                dict_anchor["transformation"] as ArrayList<Double>
                            val name: String = dict_anchor["name"] as String
                            val asset: Asset = Asset(dict_asset)
                            result.success(addAnchor(transform, name, asset))
                        } else {
                            result.success(false)
                        }
                    }
                    "removeAnchor" -> {
                        val anchorName: String = call.argument<String>("name") as String
                        removeAnchor(anchorName, result) //assetId
                    }
                    "startLocateAnchors" -> {
                        val assets: List<Map<String, Any>>? =
                            call.argument<List<Map<String, Any>>>("assets")
                        if (assets != null) {
                            for (map in assets.toTypedArray()) {
                                nearbyAssets.add(Asset(map))
                            }
                            var ids: ArrayList<String> = ArrayList()
                            for (a: Asset in nearbyAssets){
                                if(!a.arAnchorID.equals("")){
                                    ids.add(a.arAnchorID)
                                }
                            }
                            startLocatingNearbyAssets(ids, result)
                        } else {
                            result.success(false)
                        }
                    }
                    "uploadAnchor" -> {
                        val anchorName: String = call.argument<String>("name") as String
                        uploadAnchor(anchorName, result)
                    }
                    else -> {
                    }
                }
            }
        }

    override fun getView(): View {
        return arSceneView
    }

    override fun dispose() {
        // Destroy AR session
        Log.d(TAG, "dispose called")
        sessionManagerChannel.invokeMethod("log", "dispose")
        try {
            onPause()
            onDestroy()
            ArSceneView.destroyAllResources()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    init {

        Log.d(TAG, "Initializing AndroidARView")
        sessionManagerChannel.invokeMethod("log", "Initializing AndroidARView")
        viewContext = context

        arSceneView = ArSceneView(context)

        setupLifeCycle(context)

        sessionManagerChannel.setMethodCallHandler(onSessionMethodCall)
        objectManagerChannel.setMethodCallHandler(onObjectMethodCall)
        anchorManagerChannel.setMethodCallHandler(onAnchorMethodCall)

        //Original visualizer: com.google.ar.sceneform.ux.R.raw.sceneform_footprint

        MaterialFactory.makeTransparentWithColor(context, Color(255f, 255f, 255f, 0.3f))
            .thenAccept { mat ->
                footprintSelectionVisualizer.footprintRenderable =
                    ShapeFactory.makeCylinder(0.7f, 0.05f, Vector3(0f, 0f, 0f), mat)
            }

        onResume() // call onResume once to setup initial session
        // TODO: find out why this does not happen automatically
    }

    private fun setupLifeCycle(context: Context) {
        activityLifecycleCallbacks =
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityCreated(
                    activity: Activity,
                    savedInstanceState: Bundle?
                ) {
                    Log.d(TAG, "onActivityCreated")
                    sessionManagerChannel.invokeMethod("log", "onActivityCreated")
                }

                override fun onActivityStarted(activity: Activity) {
                    Log.d(TAG, "onActivityStarted")
                    sessionManagerChannel.invokeMethod("log", "onActivityStarted")
                }

                override fun onActivityResumed(activity: Activity) {
                    Log.d(TAG, "onActivityResumed")
                    sessionManagerChannel.invokeMethod("log", "onActivityResumed")
                    onResume()
                }

                override fun onActivityPaused(activity: Activity) {
                    Log.d(TAG, "onActivityPaused")
                    sessionManagerChannel.invokeMethod("log", "onActivityPaused")
                    onPause()
                }

                override fun onActivityStopped(activity: Activity) {
                    Log.d(TAG, "onActivityStopped")
                    sessionManagerChannel.invokeMethod("log", "onActivityStopped")
                    onPause()
                }

                override fun onActivitySaveInstanceState(
                    activity: Activity,
                    outState: Bundle
                ) {
                }

                override fun onActivityDestroyed(activity: Activity) {
                    Log.d(TAG, "onActivityDestroyed")
                    sessionManagerChannel.invokeMethod("log", "onActivityDestroyed")
                }
            }

        activity.application.registerActivityLifecycleCallbacks(this.activityLifecycleCallbacks)
    }

    fun onResume() {
        sessionManagerChannel.invokeMethod("log", "onResume")
        // Create session if there is none
        if (arSceneView.session == null) {
            Log.d(TAG, "ARSceneView session is null. Trying to initialize")
            try {
                var session: Session?
                if (ArCoreApk.getInstance().requestInstall(activity, mUserRequestedInstall) ==
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED
                ) {
                    Log.d(TAG, "Install of ArCore APK requested")
                    session = null
                } else {
                    session = Session(activity)
                }

                if (session == null) {
                    // Ensures next invocation of requestInstall() will either return
                    // INSTALLED or throw an exception.
                    mUserRequestedInstall = false
                    return
                } else {
                    val config = Config(session)
                    config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    config.cloudAnchorMode = Config.CloudAnchorMode.ENABLED
                    config.focusMode = Config.FocusMode.AUTO
                    session.configure(config)
                    arSceneView.setupSession(session)
                    azureSpatialAnchorsManager =
                        AzureSpatialAnchorsManager(arSceneView.session)

                    azureSpatialAnchorsManager.addAnchorLocatedListener(
                        AnchorLocatedListener { event ->
                            onAnchorLocated(event)
                        })
                }
            } catch (ex: UnavailableUserDeclinedInstallationException) {
                // Display an appropriate message to the user zand return gracefully.
                Toast.makeText(
                    activity,
                    "TODO: handle exception " + ex.localizedMessage,
                    Toast.LENGTH_LONG
                )
                    .show()
                return
            } catch (ex: UnavailableArcoreNotInstalledException) {
                Toast.makeText(activity, "Please install ARCore", Toast.LENGTH_LONG).show()
                return
            } catch (ex: UnavailableApkTooOldException) {
                Toast.makeText(activity, "Please update ARCore", Toast.LENGTH_LONG).show()
                return
            } catch (ex: UnavailableSdkTooOldException) {
                Toast.makeText(activity, "Please update this app", Toast.LENGTH_LONG).show()
                return
            } catch (ex: UnavailableDeviceNotCompatibleException) {
                Toast.makeText(activity, "This device does not support AR", Toast.LENGTH_LONG)
                    .show()
                return
            } catch (e: Exception) {
                Toast.makeText(activity, "Failed to create AR session", Toast.LENGTH_LONG).show()
                return
            }
        }

        try {
            arSceneView.resume()
            azureSpatialAnchorsManager.start()

        } catch (ex: CameraNotAvailableException) {
            Log.d(TAG, "Unable to get camera $ex")
            activity.finish()
            return
        } catch (e: Exception) {
            Log.d(TAG, "Something wrong in onResume")
            sessionManagerChannel.invokeMethod("log", "Something wrong in onResume")
            return
        }
    }

    fun onPause() {
        sessionManagerChannel.invokeMethod("log", "onPause")
        arSceneView.pause()
        if (this::azureSpatialAnchorsManager.isInitialized) {
            azureSpatialAnchorsManager.stop();
        }
    }

    fun onDestroy() {
        sessionManagerChannel.invokeMethod("log", "onDestroy")
        try {
            arSceneView.session?.close()
            arSceneView.destroy()
            arSceneView.scene?.removeOnUpdateListener(sceneUpdateListener)
            if (this::azureSpatialAnchorsManager.isInitialized) {
                azureSpatialAnchorsManager.reset();
            }

        } catch (e: Exception) {
            e.printStackTrace();
        }
    }

    private fun initializeARView(call: MethodCall, result: MethodChannel.Result) {
        // Unpack call arguments
        val argPlaneDetectionConfig: Int? = call.argument<Int>("planeDetectionConfig")
        val argShowPlanes: Boolean? = call.argument<Boolean>("showPlanes")

        arSceneView.scene.setOnTouchListener { hitTestResult: HitTestResult, motionEvent: MotionEvent? ->
            onTap(
                hitTestResult,
                motionEvent
            )
        }

        sceneUpdateListener =
            com.google.ar.sceneform.Scene.OnUpdateListener { frameTime: FrameTime ->
                if (this::azureSpatialAnchorsManager.isInitialized) {
                    azureSpatialAnchorsManager.update(arSceneView.arFrame)
                }
            }

        arSceneView.scene?.addOnUpdateListener(sceneUpdateListener)

        // Configure plane detection
        val config = arSceneView.session?.config
        if (config == null) {
            sessionManagerChannel.invokeMethod("onError", listOf("session is null"))
        }
        when (argPlaneDetectionConfig) {
            1 -> {
                config?.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
            }
            2 -> {
                config?.planeFindingMode = Config.PlaneFindingMode.VERTICAL
            }
            3 -> {
                config?.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            }
            else -> {
                config?.planeFindingMode = Config.PlaneFindingMode.DISABLED
            }
        }
        arSceneView.session?.configure(config)

        // Configure whether or not detected planes should be shown
        arSceneView.planeRenderer.isVisible = argShowPlanes == true

        result.success(null)
    }

    private fun onTap(hitTestResult: HitTestResult, motionEvent: MotionEvent?): Boolean {
        val frame = arSceneView.arFrame
        Log.d(TAG, "onTap")
        if (hitTestResult.node != null && motionEvent?.action == MotionEvent.ACTION_DOWN) {
            Log.d(TAG, "onTapNode")
            objectManagerChannel.invokeMethod("onNodeTap", hitTestResult.node!!.name)
            return true
        }
        if (motionEvent != null && motionEvent.action == MotionEvent.ACTION_DOWN) {
            Log.d(TAG, "onTapSurface")
            val allHitResults = frame?.hitTest(motionEvent) ?: listOf<HitResult>()
            val planeAndPointHitResults =
                allHitResults.filter { ((it.trackable is Plane) || (it.trackable is Point)) }
            val serializedPlaneAndPointHitResults: ArrayList<HashMap<String, Any>> =
                ArrayList(planeAndPointHitResults.map { serializeHitResult(it) })
            sessionManagerChannel.invokeMethod(
                "onPlaneOrPointTap",
                serializedPlaneAndPointHitResults
            )
            return true
        }
        return false
    }

    private fun addAnchor(transform: ArrayList<Double>, anchorName: String, asset: Asset): Boolean {
        Log.d(TAG, "addAnchor (local)")
        return try {
            val position = floatArrayOf(
                deserializeMatrix4(transform).second.x,
                deserializeMatrix4(transform).second.y,
                deserializeMatrix4(transform).second.z
            )
            val rotation = floatArrayOf(
                deserializeMatrix4(transform).third.x,
                deserializeMatrix4(transform).third.y,
                deserializeMatrix4(transform).third.z,
                deserializeMatrix4(transform).third.w
            )
            var anchor = arSceneView.session!!.createAnchor(Pose(position, rotation))
            val visual = AnchorVisualAsset(anchor, asset, anchorName)
            visual.render(viewContext, arSceneView.scene)
            anchorVisuals[visual.name] = visual
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun removeAnchor(name: String, result: MethodChannel.Result) {
        try {
            val visual: AnchorVisualAsset =
                anchorVisuals[name] as AnchorVisualAsset
            visual.localAnchor.detach()
            for (node in visual.node.children) {
                node.setParent(null)
            }
            visual.node.setParent(null)
            anchorVisuals.remove(name)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }

    }

    private fun uploadAnchor(name: String, result: MethodChannel.Result) {
        val visual: AnchorVisualAsset =
            anchorVisuals[name] as AnchorVisualAsset
        val cloudAnchor = CloudSpatialAnchor()
        cloudAnchor.localAnchor = visual.localAnchor
        visual.cloudAnchor = cloudAnchor

        // In this sample app we delete the cloud anchor explicitly, but you can also set it to expire automatically
        val now = Date()
        val cal = Calendar.getInstance()
        cal.time = now
        cal.add(Calendar.DATE, 7)
        val oneWeekFromNow = cal.time
        cloudAnchor.expiration = oneWeekFromNow
        try {
            var anchorSaveResult =
                azureSpatialAnchorsManager.createAnchorAsync(visual.cloudAnchor!!)
            if (anchorSaveResult == null) {
                sessionManagerChannel.invokeMethod(
                    "onError",
                    listOf("Error initializing cloud anchor mode: Session is null")
                )
                result.success(null)
            } else {
                anchorSaveResult.thenAccept { csa: CloudSpatialAnchor ->
                    result.success(csa.identifier);
                }
            }
        } catch (e: Exception) {
            result.success(null)
        }

    }

    private fun startLocatingNearbyAssets(ids: ArrayList<String>, result: MethodChannel.Result) {
        val criteria = AnchorLocateCriteria()
        Log.d(TAG, ids.toString());
        criteria.identifiers = ids.toTypedArray<String>()
        sessionManagerChannel.invokeMethod("log", "startLocatingNearbyAssets"+ids.toString())
        try {
            if (this::azureSpatialAnchorsManager.isInitialized) {
                azureSpatialAnchorsManager.stopLocating()
                azureSpatialAnchorsManager.startLocating(criteria)
                sessionManagerChannel.invokeMethod("log", "realStart")
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun onAnchorLocated(event: AnchorLocatedEvent) {
        val status = event.status
        sessionManagerChannel.invokeMethod("log", "onAnchorLocated")
        if (status == LocateAnchorStatus.Located) {
            sessionManagerChannel.invokeMethod("log", "real Located")
            Log.d(TAG, "renderLocatedAnchor: rendering located anchor" + event.anchor.identifier)
            var cloudAnchor = event.anchor
            //get the asset name to print
            //get the asset name to print
            var theAsset = Asset("porcodio", "PORCODIO", cloudAnchor.identifier)
            //synchronized(nearbyAssets) {
            //    for (asset in nearbyAssets) {
            //        if (asset.arAnchorID.equals(cloudAnchor.identifier)) {
            //            theAsset = asset
            //            break
            //        }
            //    }
            //}
            activity.runOnUiThread {
                val foundVisual = AnchorVisualAsset(cloudAnchor.localAnchor, theAsset, theAsset.id)
                foundVisual.cloudAnchor = cloudAnchor
                foundVisual.render(viewContext, arSceneView.scene)
                anchorVisuals[foundVisual.name] = foundVisual
            }

        }
    }
}


