package io.carius.lars.ar_flutter_plugin

import android.app.Activity
import android.app.Application
import android.content.Context
import android.opengl.EGL14
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.os.Bundle
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.Toast
import android.widget.TextView
import android.widget.LinearLayout
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import com.google.ar.sceneform.*
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
    private var apiKey: String = creationParams!!["apiKey"] as String
    private var apiId: String = creationParams!!["apiId"] as String

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
    private var isStarted: Boolean = false
    private var showAnimatedGuide: Boolean = false
    private var animatedGuide: View
    private var showScanProgress: Boolean = false
    private lateinit var scanProgress: View


    private var azureSpatialAnchorsManager: AzureSpatialAnchorsManager? = null
    private val anchorVisuals: ConcurrentHashMap<String, AnchorVisualAsset> = ConcurrentHashMap()

    // Assets
    private var nearbyAssets: ArrayList<Asset> = ArrayList()

    private var sceneUpdateListener: Scene.OnUpdateListener


    // Method channel handlers
    private val onSessionMethodCall = object : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "dispose" -> {
                    Log.d(TAG, call.method + "called in sessionmanager")
                    dispose()
                    result.success(null)
                }
                "pause" -> {
                    Log.d(TAG, call.method + "called in sessionmanager")
                    onPause()
                    result.success(null)
                }
                "resume" -> {
                    Log.d(TAG, call.method + "called in sessionmanager")
                    onResume()
                    result.success(null)
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

    init {
        //costruttore
        //queste operazioni vengono eseguite solo alla costruzione della view
        Log.d(TAG, "Initializing AndroidARView")
        viewContext = context
        //creo la scena
        arSceneView = ArSceneView(context)

        //setup lifecycle per gestire gli eventi della main activity(flutter activity)
        //ossia cosa deve fare il plugin se pauso/chiudo/riapro l'app
        setupLifeCycle(context)

        sessionManagerChannel.setMethodCallHandler(onSessionMethodCall)
        anchorManagerChannel.setMethodCallHandler(onAnchorMethodCall)
        //aggiungo ontouch listener sulla scena (tap sui plane, tap sul nodo)
        arSceneView.scene.setOnTouchListener { hitTestResult: HitTestResult, motionEvent: MotionEvent? ->
            onTap(hitTestResult, motionEvent)
        }
        //mostra sempre la mano che si muove fin che cerco i plane
        showAnimatedGuide = true
        val view = activity.findViewById(android.R.id.content) as ViewGroup
        animatedGuide = activity.layoutInflater.inflate(
            com.google.ar.sceneform.ux.R.layout.sceneform_instructions_plane_discovery, null
        )
        view.addView(animatedGuide)

        //inizializzo il listener sull'aggiornamento della scena
        sceneUpdateListener =
            Scene.OnUpdateListener { frameTime: FrameTime ->
                val frame = arSceneView.arFrame
                if (frame != null) {
                    if (azureSpatialAnchorsManager!=null) {
                        //se ASA session è inizializzata propago l'update
                        azureSpatialAnchorsManager!!.update(frame)
                    }
                    //tolgo la mano che si muove se ho trovato i plane
                    if (showAnimatedGuide && arSceneView.arFrame != null) {
                        for (plane in arSceneView.arFrame!!.getUpdatedTrackables(Plane::class.java)) {
                            if (plane.trackingState === TrackingState.TRACKING) {
                                val view = activity.findViewById(android.R.id.content) as ViewGroup
                                view.removeView(animatedGuide)
                                showAnimatedGuide = false
                                break
                            }
                        }
                    }
                } else {
                    Log.d(TAG, "OnUpdateListener proke e frame null")
                }
            }

        arSceneView.scene?.addOnUpdateListener(sceneUpdateListener)

        // Configure whether or not detected planes should be shown
        arSceneView.planeRenderer.isVisible = true

        //lancio onResume a mano
        onResume()
    }

    override fun getView(): View {
        return arSceneView
    }

    override fun dispose() {
        // Destroy AR session
        Log.d(TAG, "dispose called")
        try {
            onDestroy()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setupLifeCycle(context: Context) {
        Log.d(TAG, "setupLifeCycle")
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
                //onPause()
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
                onDestroy()
            }
        }

        activity.application.registerActivityLifecycleCallbacks(this.activityLifecycleCallbacks)
    }

    fun onResume() {
        //queste istruzioni sono eseguite al resume dell'activity e alla costruzione perchè richiamate in init
        Log.d(TAG, "onResume")
        // Create session if there is none
        if (arSceneView.session == null) {
            Log.d(TAG, "ARSceneView session is null. Trying to initialize")
            try {
                var session: Session?
                if (ArCoreApk.getInstance().requestInstall(
                        activity, mUserRequestedInstall
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
                    //setto la sessione arCore alla mia scena
                    val config = Config(session)
                    config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                    config.focusMode = Config.FocusMode.AUTO
                    session.configure(config)
                    arSceneView.session = session
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
            Log.d(TAG, "scene view is Started: $isStarted")
            //starto la sessione arcore se non sta già andando
            if (!isStarted) {
                isStarted = true
                arSceneView.resume()
            }
            startASASession()

        } catch (ex: CameraNotAvailableException) {
            Log.d(TAG, "Unable to get camera $ex")
            activity.finish()
            return
        } catch (e: Exception) {
            Log.d(TAG, "Something wrong in onResume")
            return
        }
    }

    private fun stopArCoreSession() {
        Log.d(TAG, "stopArCoreSession scene view is Started: $isStarted")
        if (isStarted) {
            arSceneView.pause()
            isStarted = false
        }
        if (showAnimatedGuide) {
            val view = activity.findViewById(android.R.id.content) as ViewGroup
            view.removeView(animatedGuide)
            showAnimatedGuide = false
        }

        if (showScanProgress) {
            val view = activity.findViewById(android.R.id.content) as ViewGroup
            view.removeView(scanProgress)
            showScanProgress = false
        }
    }

    private fun destroyASASession() {
        Log.d(TAG, "destroyASASession")
        if (azureSpatialAnchorsManager != null) {
            azureSpatialAnchorsManager!!.stop()
            azureSpatialAnchorsManager!!.close()
            azureSpatialAnchorsManager = null
        }
        for (visual: AnchorVisualAsset in anchorVisuals.values) {
            visual.dispose()
        }
        anchorVisuals.clear()
    }

    private fun startASASession() {
        Log.d(TAG, "startNewSession")
        destroyASASession()
        azureSpatialAnchorsManager = AzureSpatialAnchorsManager(arSceneView.session, apiKey, apiId)
        azureSpatialAnchorsManager!!.addSessionUpdatedListener(SessionUpdatedListener { event ->
            onSessionUpdate(event)
        })

        azureSpatialAnchorsManager!!.addAnchorLocatedListener(AnchorLocatedListener { event ->
            onAnchorLocated(event)
        })
        azureSpatialAnchorsManager!!.start()
    }

    fun onPause() {
        Log.d(TAG, "onPause")
        stopArCoreSession()
    }

    fun onDestroy() {
        Log.d(TAG, "onDestroy")
        try {
            stopArCoreSession()
            destroyASASession()
            arSceneView?.renderer?.dispose()
            arSceneView.destroy()
            arSceneView.scene?.removeOnUpdateListener(sceneUpdateListener)
            activity.application.unregisterActivityLifecycleCallbacks(this.activityLifecycleCallbacks)

        } catch (e: Exception) {
            e.printStackTrace();
        }
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
            activity.runOnUiThread {
                showScanProgress = true
                val view = activity.findViewById(android.R.id.content) as ViewGroup
                scanProgress = activity.layoutInflater.inflate(
                    R.layout.environment_scan, null
                )
                view.addView(scanProgress)
            }
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
            if (showScanProgress) {
                activity.runOnUiThread {
                    val view = activity.findViewById(android.R.id.content) as ViewGroup
                    view.removeView(scanProgress)
                    showScanProgress = false
                }
            }
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
        azureSpatialAnchorsManager!!.createAnchorAsync(visual.cloudAnchor!!)
            ?.exceptionally { thrown ->
                thrown.printStackTrace()
                result.success(null)
                null
            }?.thenAccept { csa ->
                if (csa != null) {
                    if (showScanProgress) {
                        activity.runOnUiThread {
                            val view = activity.findViewById(android.R.id.content) as ViewGroup
                            view.removeView(scanProgress)
                            showScanProgress = false
                        }
                    }
                    result.success(csa.identifier);
                } else {
                    result.success(null)
                }

            }

    }

    private fun removeCloudAnchor(name: String, result: MethodChannel.Result) {
        Log.d(TAG, "removeCloudAnchor $name")
        val visual: AnchorVisualAsset = anchorVisuals[name] as AnchorVisualAsset

        azureSpatialAnchorsManager!!.deleteAnchorAsync(visual.cloudAnchor!!).exceptionally { thrown ->
            thrown.printStackTrace()
            result.success(false)
            null
        }.thenAccept { _ ->
            activity.runOnUiThread {
                visual.dispose()
            }
            anchorVisuals.remove(name)
            result.success(true)
        }
    }

    private fun startLocatingNearbyAssets(ids: ArrayList<String>): Boolean {
        Log.d(TAG, "startLocatingNearbyAssets")
        val criteria = AnchorLocateCriteria()
        criteria.identifiers = ids.toTypedArray()
        return try {
            if (azureSpatialAnchorsManager!=null) {
                azureSpatialAnchorsManager!!.stopLocating()
                azureSpatialAnchorsManager!!.startLocating(criteria)
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
    private fun onSessionUpdate(event: SessionUpdatedEvent?) {
        if (event != null && showScanProgress) {
            var recommendedForCreateProgress = event.status.recommendedForCreateProgress;
            var requiredForCreateProgress = event.status.readyForCreateProgress;

            activity.runOnUiThread {
                var recommendedProgress =
                    scanProgress.findViewById(R.id.recommended_scan_progress) as ProgressBar
                var requiredProgress =
                    scanProgress.findViewById(R.id.required_scan_progress) as ProgressBar
                requiredProgress.progress = (100 * requiredForCreateProgress).toInt()
                recommendedProgress.progress = (100 * recommendedForCreateProgress).toInt()
                if (requiredForCreateProgress >= 1.0f) {
                    sessionManagerChannel.invokeMethod("readyToUpload", null)
                }
            }
        }
    }
}


