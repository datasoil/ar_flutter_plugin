package io.carius.lars.ar_flutter_plugin


import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.widget.Toast
import android.widget.TextView
import android.widget.LinearLayout
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import com.google.ar.sceneform.*
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.*
import com.google.ar.sceneform.ux.*
import com.microsoft.azure.spatialanchors.* //import all ASA stuff
import io.carius.lars.ar_flutter_plugin.Serialization.deserializeMatrix4
import io.carius.lars.ar_flutter_plugin.Serialization.serializeHitResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.*
import java.text.DecimalFormat
import java.util.concurrent.ConcurrentHashMap
import kotlin.collections.set


internal class AndroidARView(
    val activity: Activity,
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView {
    private var enoughDataForSaving : Boolean = false
    private val progressLock : Object = Object()
    private var createByTapEnabled : Boolean = true

    // constants
    private val TAG: String = AndroidARView::class.java.name

    // Lifecycle variables
    private var mUserRequestedInstall = true
    lateinit var activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks
    private val viewContext: Context

    // Platform channels
    private val sessionManagerChannel: MethodChannel = MethodChannel(messenger, "arsession_$id")
    private val anchorManagerChannel: MethodChannel = MethodChannel(messenger, "aranchors_$id")

    // UI variables
    private var arSceneView: ArSceneView
    //private var scanProgressText: TextView
    //private var arFragment : ArFragment
    //private var backButton : Button
    //private var saveAnchorButton : Button
    //private var cancelAnchorButton : Button
    //private var gridSwitch : Switch
    private var anchorEditButtons : LinearLayout = LinearLayout(context)
    private var scanProgressText : TextView = TextView(context)
    //private var sceneView : ArSceneView
    private var statusText : TextView = TextView(context)
    //private var reactContext : ThemedReactContext
    //private var assetselect :View

    // Setting defaults
    private var footprintSelectionVisualizer = FootprintSelectionVisualizer()


    private lateinit var azureSpatialAnchorsManager: AzureSpatialAnchorsManager
    private val anchorVisuals: ConcurrentHashMap<String, AnchorVisualAsset> = ConcurrentHashMap()

    // Assets
    private var nearbyAssets: ArrayList<Asset> = ArrayList()

    private lateinit var sceneUpdateListener: com.google.ar.sceneform.Scene.OnUpdateListener

    // Method channel handlers
    private val onSessionMethodCall = object : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            Log.d(TAG, "AndroidARView onSessionMethodCall reveived a call!")
            when (call.method) {
                "init" -> {
                    val argShowPlanes: Boolean? = call.argument<Boolean>("showPlanes")
                    initializeARView(argShowPlanes)
                }
                "dispose" -> {
                    dispose()
                }
                else -> {
                    Log.d(TAG, call.method + "not supported on sessionManager")
                }
            }
        }
    }
    private val onAnchorMethodCall = object : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "addAnchor" -> {
                    val dictAsset: HashMap<String, Any>? = call.argument("asset")
                    val dictAnchor: HashMap<String, Any>? = call.argument("anchor")
                    if (dictAsset != null && dictAnchor != null) {
                        val transform: ArrayList<Double> =
                            dictAnchor["transformation"] as ArrayList<Double>
                        val name: String = dictAnchor["name"] as String
                        val asset = Asset(dictAsset)
                        result.success(addAnchor(transform, name, asset))
                    } else {
                        result.success(false)
                    }
                }
                "removeAnchor" -> {
                    val anchorName: String? = call.argument("name")
                    if (anchorName != null) {
                        result.success(removeAnchor(anchorName))
                    } else {
                        result.success(false)
                    }
                }
                "startLocateAnchors" -> {
                    val assets: List<Map<String, Any>>? = call.argument("assets")
                    if (assets != null) {
                        for (map in assets.toTypedArray()) {
                            nearbyAssets.add(Asset(map))
                        }
                        var ids: ArrayList<String> = ArrayList()
                        for (a: Asset in nearbyAssets) {
                            if (a.anchorId != "" && a.anchorId != null) {
                                ids.add(a.anchorId!!)
                            }
                        }
                        result.success(startLocatingNearbyAssets(ids))
                    } else {
                        result.success(false)
                    }

                }
                "uploadAnchor" -> {
                    val anchorName: String? = call.argument("name")
                    if (anchorName != null) {
                        uploadAnchor(anchorName, result)
                    } else {
                        result.success(false)
                    }
                }
                "removeCloudAnchor" -> {
                    val anchorName: String? = call.argument("name")
                    if (anchorName != null) {
                        removeCloudAnchor(anchorName, result)
                    } else {
                        result.success(false)
                    }
                }
                else -> {
                    Log.d(TAG, call.method + "not supported on anchorManager")
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
        viewContext = context

        arSceneView = ArSceneView(context)

        setupLifeCycle(context)

        sessionManagerChannel.setMethodCallHandler(onSessionMethodCall)
        anchorManagerChannel.setMethodCallHandler(onAnchorMethodCall)

        //Original visualizer: com.google.ar.sceneform.ux.R.raw.sceneform_footprint

        MaterialFactory.makeTransparentWithColor(context, Color(255f, 255f, 255f, 0.3f))
            .thenAccept { mat ->
                footprintSelectionVisualizer.footprintRenderable =
                    ShapeFactory.makeCylinder(0.7f, 0.05f, Vector3(0f, 0f, 0f), mat)
            }

        onResume()
    }

    private fun setupLifeCycle(context: Context) {
        activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(
                activity: Activity, savedInstanceState: Bundle?
            ) {
                Log.d(TAG, "onActivityCreated")
            }

            override fun onActivityStarted(activity: Activity) {
                Log.d(TAG, "onActivityStarted")
            }

            override fun onActivityResumed(activity: Activity) {
                Log.d(TAG, "onActivityResumed")
                onResume()
            }

            override fun onActivityPaused(activity: Activity) {
                Log.d(TAG, "onActivityPaused")
                onPause()
            }

            override fun onActivityStopped(activity: Activity) {
                Log.d(TAG, "onActivityStopped")
                onPause()
            }

            override fun onActivitySaveInstanceState(
                activity: Activity, outState: Bundle
            ) {
            }

            override fun onActivityDestroyed(activity: Activity) {
                Log.d(TAG, "onActivityDestroyed")
            }
        }

        activity.application.registerActivityLifecycleCallbacks(this.activityLifecycleCallbacks)
    }

    fun onResume() {
        // Create session if there is none
        if (arSceneView.session == null) {
            Log.d(TAG, "ARSceneView session is null. Trying to initialize")
            try {
                var session: Session?
                if (ArCoreApk.getInstance().requestInstall(
                        activity,
                        mUserRequestedInstall
                    ) == ArCoreApk.InstallStatus.INSTALL_REQUESTED
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
                    azureSpatialAnchorsManager = AzureSpatialAnchorsManager(arSceneView.session)

                    azureSpatialAnchorsManager.addAnchorLocatedListener(AnchorLocatedListener { event ->
                        onAnchorLocated(event)
                    })
                    azureSpatialAnchorsManager.addSessionUpdatedListener(SessionUpdatedListener { event -> 
                        onSessionUpdated(event)
                    })
                }
            } catch (ex: UnavailableUserDeclinedInstallationException) {
                // Display an appropriate message to the user zand return gracefully.
                Toast.makeText(
                    activity, "TODO: handle exception " + ex.localizedMessage, Toast.LENGTH_LONG
                ).show()
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

    private fun initializeARView(argShowPlanes: Boolean?) {

        arSceneView.scene.setOnTouchListener { hitTestResult: HitTestResult, motionEvent: MotionEvent? ->
            onTap(
                hitTestResult, motionEvent
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
        config?.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
        arSceneView.session?.configure(config)

        // Configure whether or not detected planes should be shown
        arSceneView.planeRenderer.isVisible = argShowPlanes == true
    }

    private fun onTap(hitTestResult: HitTestResult, motionEvent: MotionEvent?): Boolean {
        val frame = arSceneView.arFrame
        if (hitTestResult.node != null && motionEvent?.action == MotionEvent.ACTION_DOWN) {
            Log.d(TAG, "onTapNode")
            anchorManagerChannel.invokeMethod("onNodeTap", hitTestResult.node!!.name)
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
                "onPlaneOrPointTap", serializedPlaneAndPointHitResults
            )
            return true
        }
        return false
    }

    private fun addAnchor(transform: ArrayList<Double>, anchorName: String, asset: Asset): Boolean {
        Log.d(TAG, "addAnchor $anchorName")
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

    private fun removeAnchor(name: String): Boolean {
        Log.d(TAG, "removeAnchor $name")
        return try {
            val visual: AnchorVisualAsset = anchorVisuals[name] as AnchorVisualAsset
            visual.dispose()
            anchorVisuals.remove(name)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun uploadAnchor(name: String, result: MethodChannel.Result) {
        Log.d(TAG, "uploadAnchor $name")
        val visual: AnchorVisualAsset = anchorVisuals[name] as AnchorVisualAsset
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

        //here we use ASA's tools
        azureSpatialAnchorsManager.createAnchorAsync(visual.cloudAnchor!!)!!.exceptionally { thrown ->
            thrown.printStackTrace()
            result.success(null)
            null
        }.thenAccept { csa ->
            if (csa != null) {
                result.success(csa.identifier);
            } else {
                result.success(null)
            }
        }

    }

    private fun removeCloudAnchor(name: String, result: MethodChannel.Result) {
        Log.d(TAG, "removeCloudAnchor $name")
        val visual: AnchorVisualAsset = anchorVisuals[name] as AnchorVisualAsset

        azureSpatialAnchorsManager.deleteAnchorAsync(visual.cloudAnchor!!).exceptionally { thrown ->
            thrown.printStackTrace()
            result.success(false)
            null
        }.thenAccept { _ ->
            Log.d(TAG, "Anchor Deleted")
            Log.d(TAG, visual.toString())
            activity.runOnUiThread {
                visual.dispose()
            }
            Log.d(TAG, visual.toString())
            Log.d(TAG, "Anchor Disposed")
            anchorVisuals.remove(name)
            Log.d(TAG, "Anchor removed from list")
            result.success(true)
            Log.d(TAG, "After result")
        }
    }

    private fun startLocatingNearbyAssets(ids: ArrayList<String>): Boolean {
        Log.d(TAG, "startLocatingNearbyAssets")
        val criteria = AnchorLocateCriteria()
        criteria.identifiers = ids.toTypedArray()
        return try {
            if (this::azureSpatialAnchorsManager.isInitialized) {
                azureSpatialAnchorsManager.stopLocating()
                azureSpatialAnchorsManager.startLocating(criteria)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun onAnchorLocated(event: AnchorLocatedEvent) {
        val status = event.status
        if (status == LocateAnchorStatus.Located) {
            Log.d(TAG, "onAnchorLocated" + event.anchor.identifier)
            var cloudAnchor = event.anchor
            var theAsset = Asset(
                "Unknown", "Unknown", cloudAnchor.identifier, null, null, ArrayList(0), ArrayList(0)
            )
            for (asset in nearbyAssets) {
                if (asset.anchorId == cloudAnchor.identifier) {
                    theAsset = asset
                    break
                }
            }
            activity.runOnUiThread {
                val foundVisual = AnchorVisualAsset(cloudAnchor.localAnchor, theAsset, theAsset.id)
                foundVisual.cloudAnchor = cloudAnchor
                foundVisual.render(viewContext, arSceneView.scene)
                anchorVisuals[foundVisual.name] = foundVisual
            }

        }
    }

    //makes sure there are enough frames
    //SessionUpdatedEvent is from ASA cloud
    private fun onSessionUpdated(args: SessionUpdatedEvent) {
        var progress = args.getStatus().getRecommendedForCreateProgress();
        enoughDataForSaving = progress >= 1.0;
        synchronized (progressLock) {
            if (!createByTapEnabled) {
                var decimalFormat : DecimalFormat = DecimalFormat("00");
                activity.runOnUiThread {
                    var progressMessage : String = "Scan progress is " + decimalFormat.format(Math.min(1.0f, progress) * 100) + "%"
                    scanProgressText.setText(progressMessage)
                }

                if (enoughDataForSaving && anchorEditButtons.getVisibility() != View.VISIBLE) {
                    // Enable the save button
                    activity.runOnUiThread {
                        statusText.setText("Ready to save")
                        anchorEditButtons.setVisibility(View.VISIBLE)
                    }
                }
            }
        }
    }
}


