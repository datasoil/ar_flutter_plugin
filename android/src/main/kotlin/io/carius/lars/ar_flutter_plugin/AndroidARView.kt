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
    private var isStarted: Boolean = false
    private var showAnimatedGuide: Boolean = false
    private lateinit var animatedGuide: View
    private var showScanProgress: Boolean = false
    private lateinit var scanProgress: View
    
    //private var scanProgressText: TextView
    //private var arFragment : ArFragment
    //private var backButton : Button
    //private var saveAnchorButton : Button
    //private var cancelAnchorButton : Button
    //private var gridSwitch : Switch
    //private var anchorEditButtons : LinearLayout = LinearLayout(context)
    //private var scanProgressText : TextView = TextView(context)
    //private var sceneView : ArSceneView
    //private var statusText : TextView = TextView(context)
    //private var reactContext : ThemedReactContext
    //private var assetselect :View

    // Setting defaults
    //private var footprintSelectionVisualizer = FootprintSelectionVisualizer()

    private lateinit var azureSpatialAnchorsManager: AzureSpatialAnchorsManager
    private val anchorVisuals: ConcurrentHashMap<String, AnchorVisualAsset> = ConcurrentHashMap()

    // Assets
    private var nearbyAssets: ArrayList<Asset> = ArrayList()

    private var sceneUpdateListener: Scene.OnUpdateListener

    //EGL variables
    companion object {
        private var savedContext: EGLContext? = null
        private var savedDisplay: EGLDisplay? = null
        private var savedReadSurface: EGLSurface? = null
        private var savedDrawSurface: EGLSurface? = null
    }

    // Method channel handlers
    private val onSessionMethodCall = object : MethodChannel.MethodCallHandler {
        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "init" -> {
                    val argShowPlanes: Boolean? = call.argument<Boolean>("showPlanes")
                    initializeARView(argShowPlanes)
                }
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
                if(frame!=null){
                    if (this::azureSpatialAnchorsManager.isInitialized) {
                        //se ASA session è inizializzata propago l'update
                        azureSpatialAnchorsManager.update(frame)
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
                }else{
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
            //onPause()
            onDestroy()
            //ArSceneView.destroyAllResources()
        } catch (e: Exception) {
            e.printStackTrace()
        }
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
                //premi il tasto home l'app va in pausa, elimini dallo stack delle app
                //aperte viene chiamato on destroy
            }
        }

        activity.application.registerActivityLifecycleCallbacks(this.activityLifecycleCallbacks)
    }

    fun onResume() {
        //queste istruzioni sono eseguite al resume dell'activity e alla costruzione perchè richiamate in init
        Log.d(TAG, "onResume")
        restoreEglContext() //restora il context
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

        //faccio direttamente questo se non sono alla prima creazione
        try {
            Log.d(TAG, "scene view is Started: $isStarted")
            //starto la sessione arcore se non sta già andando
            if (!isStarted) {
                isStarted = true
                arSceneView.resume() //questo è uno start
            }
            //startNewSession()
            //azureSpatialAnchorsManager.start()

        } catch (ex: CameraNotAvailableException) {
            Log.d(TAG, "Unable to get camera $ex")
            activity.finish()
            return
        } catch (e: Exception) {
            Log.d(TAG, "Something wrong in onResume")
            return
        }
    }

    private fun restoreEglContext() {
        if (Looper.getMainLooper().thread != Thread.currentThread()) {
            throw IllegalStateException("restoreEglContext called from non-UI thread")
        }
        Log.d(TAG, "Restoring EGL context")
        if (savedContext != null && savedContext != EGL14.EGL_NO_CONTEXT) {
            if (!EGL14.eglMakeCurrent(savedDisplay, savedDrawSurface, savedReadSurface, savedContext)) {
                Log.d(TAG, "Failed to restore")
            }else{
                Log.d(TAG, "EGL context restored")
            }
        } else {
            Log.d(TAG, "Nothing to restore")
        }
    }

    private fun saveEglContext() {
        if (Looper.getMainLooper().thread != Thread.currentThread()) {
            throw IllegalStateException("saveEglContext called from non-UI thread")
        }
        Log.d(TAG, "Saving EGL context")
        val currentContext = EGL14.eglGetCurrentContext()
        if (currentContext == null || currentContext == EGL14.EGL_NO_CONTEXT) {
            Log.d(TAG, "Nothing to save")
        } else {
            savedContext = currentContext
            savedDisplay = EGL14.eglGetCurrentDisplay()
            savedDrawSurface = EGL14.eglGetCurrentSurface(EGL14.EGL_DRAW)
            savedReadSurface = EGL14.eglGetCurrentSurface(EGL14.EGL_READ)
            EGL14.eglMakeCurrent( //backuppare il contesto
                savedDisplay,
                savedDrawSurface,
                savedReadSurface,
                savedContext
            )
            Log.d(TAG, "EGL context saved")
        }
    }

    private fun stopArCoreSession (){ 
        //secondo la issue si dovrebbe fare : 
        // "every time my app gets paused:"
        //on surface texture destroyed ->
        //(
        //    A TextureView can be used to display a content stream, such as that coming from a camera preview, a video, or an OpenGL scene. The content stream can come from the application's process as well as a remote process.
        //)
        //mCamera.setPreviewCallback(null);
        //mCamera.stopPreview();
        //mCamera.release();

        //però noi abbiamo solo surfaceView 
        Log.d(TAG, "stopArCoreSession scene view is Started: $isStarted")
        saveEglContext() //salvo sempre il contesto e lo restoro nell' [onresume]
        if (isStarted) {
            //quindi forse qui dobbiamo rilasciare le risorse
            
            arSceneView.pause() //con destroy bugga uguale
            isStarted=false
            Log.d(TAG, "arSceneView.destroy() lanciata, isStared = $isStarted")
        }
        if (showAnimatedGuide) {
            val view = activity.findViewById(android.R.id.content) as ViewGroup
            view.removeView(animatedGuide)
            showAnimatedGuide = false
        }
    }

    private fun destroySession() {
        Log.d(TAG, "destroySession ${this::azureSpatialAnchorsManager.isInitialized}")
        if (this::azureSpatialAnchorsManager.isInitialized) {
            azureSpatialAnchorsManager.stop();
        }
        for (visual: AnchorVisualAsset in anchorVisuals.values) {
            visual.dispose()
            //chiama il destroy
        }
        anchorVisuals.clear()
    }

    private fun startNewSession() {
        Log.d(TAG, "startNewSession")
        //destroySession()
        azureSpatialAnchorsManager = AzureSpatialAnchorsManager(arSceneView.session)
        azureSpatialAnchorsManager.addSessionUpdatedListener(SessionUpdatedListener { event ->
            onSessionUpdate(event)
        })

        azureSpatialAnchorsManager.addAnchorLocatedListener(AnchorLocatedListener { event ->
            onAnchorLocated(event)
        })
        azureSpatialAnchorsManager.start()
    }

    //non entra mai qua
    fun onPause() {// in realtà va in stop e non in pause
        //o andando nella home, phone block, o chiamandola manualmente
        //se apri e fai "indietro" viene fatto on destroy
        Log.d(TAG, "onPause") //facciamo pause, facciamo direttamente destroy
        stopArCoreSession()
        if (showScanProgress) {
            val view = activity.findViewById(android.R.id.content) as ViewGroup
            view.removeView(scanProgress)
            showScanProgress = false
        }
        //se tu blocchi e risblocchi il cellulare non riparti dalla costruzione
        //

        /*if (this::azureSpatialAnchorsManager.isInitialized) {
            azureSpatialAnchorsManager.stop();
        }*/
    }

    fun onDestroy() {
        Log.d(TAG, "onDestroy")
        try {
            stopArCoreSession()
            //arSceneView?.renderer?.dispose()
            arSceneView.destroy()  
            arSceneView.scene?.removeOnUpdateListener(sceneUpdateListener)
            activity.application.unregisterActivityLifecycleCallbacks(this.activityLifecycleCallbacks)
            //destroySession()
        }
        catch (e: Exception) {
            e.printStackTrace();
        }
    }

    private fun initializeARView(argShowPlanes: Boolean?) {

        /*arSceneView.scene.setOnTouchListener { hitTestResult: HitTestResult, motionEvent: MotionEvent? ->
            onTap(
                hitTestResult, motionEvent
            )
        }

        showAnimatedGuide = true
        val view = activity.findViewById(R.id.content) as ViewGroup
        animatedGuide = activity.layoutInflater.inflate(
            com.google.ar.sceneform.ux.R.layout.sceneform_plane_discovery_layout, null
        )
        view.addView(animatedGuide)


        sceneUpdateListener =
            com.google.ar.sceneform.Scene.OnUpdateListener { frameTime: FrameTime ->
                if (this::azureSpatialAnchorsManager.isInitialized) {
                    azureSpatialAnchorsManager.update(arSceneView.arFrame)
                }
                if (showAnimatedGuide && arSceneView.arFrame != null) {
                    for (plane in arSceneView.arFrame!!.getUpdatedTrackables(Plane::class.java)) {
                        if (plane.trackingState === TrackingState.TRACKING) {
                            val view = activity.findViewById(R.id.content) as ViewGroup
                            view.removeView(animatedGuide)
                            showAnimatedGuide = false
                            break
                        }
                    }
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
        arSceneView.planeRenderer.isVisible = argShowPlanes == true*/
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
        azureSpatialAnchorsManager.createAnchorAsync(visual.cloudAnchor!!)
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

        azureSpatialAnchorsManager.deleteAnchorAsync(visual.cloudAnchor!!).exceptionally { thrown ->
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


