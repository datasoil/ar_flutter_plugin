package io.carius.lars.ar_flutter_plugin

import android.app.Activity
import android.content.Context
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import com.google.ar.sceneform.*
import com.microsoft.azure.spatialanchors.* //import all ASA stuff
import io.carius.lars.ar_flutter_plugin.Serialization.deserializeMatrix4
import io.carius.lars.ar_flutter_plugin.Serialization.serializeHitResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.collections.set


internal class AndroidARView(
    private val activity: Activity,
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView {
    private val apiKey: String = creationParams!!["apiKey"] as String
    private val apiId: String = creationParams!!["apiId"] as String

    // constants
    private val TAG: String = AndroidARView::class.java.name

    // Lifecycle variables
    private var mUserRequestedInstall = true
    private val viewContext: Context

    // Platform channels
    private val sessionManagerChannel: MethodChannel = MethodChannel(messenger, "arsession_$id")
    private val anchorManagerChannel: MethodChannel = MethodChannel(messenger, "aranchors_$id")

    // UI variables
    private var arSceneView: ArSceneView
    private var isStarted: Boolean = false
    private var showAnimatedGuide: Boolean = false
    private var animatedGuide: View
    private var contentView: ViewGroup


    private var azureSpatialAnchorsManager: AzureSpatialAnchorsManager? = null
    private val anchorVisuals: ConcurrentHashMap<String, AnchorVisual> = ConcurrentHashMap()
    private val nearbyAssets: ConcurrentHashMap<String, AnchorInfo> = ConcurrentHashMap()
    private val nearbyTickets: ConcurrentHashMap<String, AnchorInfo> = ConcurrentHashMap()
    private var pendingAnchorVisual: AnchorVisual? = null
    private val hideAssetTickets: ConcurrentHashMap<String, Boolean> = ConcurrentHashMap()
    private var hideTickets = false
    private var enableTapToAdd = false


    private var sceneUpdateListener: Scene.OnUpdateListener

    // Method channel handlers
    private val onSessionMethodCall =
        MethodChannel.MethodCallHandler { call, result ->
            Log.d(TAG, call.method + "called in sessionmanager")
            when (call.method) {
                "dispose" -> {
                    onDestroy()
                    result.success(null)
                }
                "pause" -> {
                    onPause()
                    result.success(null)
                }
                "resume" -> {
                    onResume()
                    result.success(null)
                }
                "updateNearbyObjects" -> {
                    val assetsDict: List<Map<String, Any>>? = call.argument("assets")
                    val ticketsDict: List<Map<String, Any>>? = call.argument("tickets")
                    val assets = assetsDict?.map { map -> AnchorInfo(map) }
                    val tickets = ticketsDict?.map { map -> AnchorInfo(map) }
                    updateNearbyObjects(assets, tickets)
                    result.success(null)
                }
                else -> {
                    Log.d(TAG, call.method + "not supported on sessionManager")
                }
            }
        }

    private val onAnchorMethodCall =
        MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "startPositioning" -> {
                    val toHide: List<String>? = call.argument("toHideIds")
                    startPositioning(toHide)
                    result.success(null)
                }
                "createAnchor" -> {
                    val dictInfo = call.argument("info") as HashMap<String, Any>?
                    val transform = call.argument("transformation") as ArrayList<Double>?
                    createAnchor(transform!!, AnchorInfo(dictInfo!!))
                    result.success(null)
                }
                "uploadAnchor" -> {
                    uploadAnchor(result)
                }
                "successPositioning" -> {
                    val toShow: List<String>? = call.argument("toShowIds")
                    successPositioning(toShow)
                    result.success(null)
                }
                "abortPositioning" -> {
                    val toShow: List<String>? = call.argument("toShowIds")
                    abortPositioning(toShow)
                    result.success(null)
                }
                "deleteAnchor" -> {
                    val infoId = call.argument("id") as String?
                    deleteAnchor(infoId!!)
                    result.success(null)
                }
                "deleteCloudAnchor" -> {
                    val infoId = call.argument("id") as String?
                    deleteCloudAnchor(infoId!!, result)
                }
                "showAssetTicketsAnchors" -> {
                    val assetId = call.argument("assetId") as String?
                    val nA = nearbyAssets[assetId]
                    val naT = nearbyAssets[assetId]?.tickets
                    if (nA != null && naT?.isNotEmpty() == true) {
                        showAnchors(naT.map { t -> t.id })
                        hideAssetTickets[assetId!!] = false
                    }
                    result.success(null)
                }
                "hideAssetTicketsAnchors" -> {
                    val assetId = call.argument("assetId") as String?
                    val nA = nearbyAssets[assetId]
                    val naT = nearbyAssets[assetId]?.tickets
                    if (nA != null && naT?.isNotEmpty() == true) {
                        hideAnchors(naT.map { t -> t.id })
                        hideAssetTickets[assetId!!] = true
                    }
                    result.success(null)
                }
                "showTicketsAnchors" -> {
                    val toShow = call.argument("toShowIds") as List<String>?
                    showAnchors(toShow!!)
                    hideTickets = false
                    result.success(null)
                }
                "hideTicketsAnchors" -> {
                    val toHide = call.argument("toHideIds") as List<String>?
                    hideAnchors(toHide!!)
                    hideTickets = true
                    result.success(null)
                }
                else -> {
                    Log.d(TAG, call.method + "not supported on anchorManager")
                }
            }
        }

    init {
        Log.d(TAG, "Initializing AndroidARView")
        val assets = creationParams!!["assets"] as? List<Map<String, Any>>
        val tickets = creationParams["tickets"] as? List<Map<String, Any>>
        if (assets != null && assets.isNotEmpty()) {
            for (map in assets.toTypedArray()) {
                nearbyAssets[map["id"].toString()] = AnchorInfo(map)
            }
        }
        if (tickets != null && tickets.isNotEmpty()) {
            for (map in tickets.toTypedArray()) {
                nearbyTickets[map["id"].toString()] = AnchorInfo(map)
            }
        }

        viewContext = context
        //creo la scena
        arSceneView = ArSceneView(context)

        sessionManagerChannel.setMethodCallHandler(onSessionMethodCall)
        anchorManagerChannel.setMethodCallHandler(onAnchorMethodCall)
        //aggiungo ontouch listener sulla scena (tap sui plane, tap sul nodo)
        arSceneView.scene.setOnTouchListener { hitTestResult: HitTestResult, motionEvent: MotionEvent? ->
            onTap(hitTestResult, motionEvent)
        }
        //mostra sempre la mano che si muove fin che cerco i plane
        showAnimatedGuide = true
        contentView = activity.findViewById(android.R.id.content) as ViewGroup
        animatedGuide = activity.layoutInflater.inflate(
            com.google.ar.sceneform.ux.R.layout.sceneform_instructions_plane_discovery, null
        )
        contentView.addView(animatedGuide)

        //inizializzo il listener sull'aggiornamento della scena
        sceneUpdateListener =
            Scene.OnUpdateListener {
                val frame = arSceneView.arFrame
                if (frame != null) {
                    if (azureSpatialAnchorsManager != null) {
                        //se ASA session è inizializzata propago l'update
                        azureSpatialAnchorsManager!!.update(frame)
                    }
                    //tolgo la mano che si muove se ho trovato i plane
                    if (showAnimatedGuide && arSceneView.arFrame != null) {
                        for (plane in arSceneView.arFrame!!.getUpdatedTrackables(Plane::class.java)) {
                            if (plane.trackingState === TrackingState.TRACKING) {
                                contentView.removeView(animatedGuide)
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
        arSceneView.planeRenderer.isVisible = false

        //lancio onResume a mano
        onResume()
    }




    private fun showAnchors(ids: List<String>) {
        ids.forEach { id -> anchorVisuals[id]?.show() }
    }

    private fun hideAnchors(ids: List<String>) {
        ids.forEach { id -> anchorVisuals[id]?.hide() }
    }

    private fun abortPositioning(toShowIds: List<String>?) {
        if (toShowIds != null) {
            showAnchors(toShowIds)
        }
        enableTapToAdd = false
        if (pendingAnchorVisual != null) {
            activity.runOnUiThread {
                pendingAnchorVisual!!.dispose()
            }
            pendingAnchorVisual = null
        }
    }

    private fun successPositioning(toShowIds: List<String>?) {
        if (toShowIds != null) {
            showAnchors(toShowIds)
        }
        enableTapToAdd = false
        if (pendingAnchorVisual != null) {
            val id = pendingAnchorVisual!!.id
            if (anchorVisuals[id] != null) {
                azureSpatialAnchorsManager?.deleteAnchorAsync(anchorVisuals[id]!!.cloudAnchor!!)
                anchorVisuals[id]!!.dispose()
            }
            val newArAnchorId = pendingAnchorVisual!!.cloudAnchor!!.identifier
            if (nearbyAssets[id] != null) {
                nearbyAssets[id]!!.ARanchorId = newArAnchorId
            } else if (nearbyTickets[id] != null) {
                nearbyTickets[id]!!.ARanchorId = newArAnchorId
            } else {
                val assetTicket = nearbyAssets.values.mapNotNull { a -> a.tickets }.flatten()
                    .firstOrNull { t -> t.id == id }
                if (assetTicket != null) {
                    assetTicket.ARanchorId = newArAnchorId
                }
            }
            anchorVisuals[id] = pendingAnchorVisual!!
            pendingAnchorVisual = null
        }
    }

    private fun startPositioning(toHideIds: List<String>?) {
        if (toHideIds != null) {
            hideAnchors(toHideIds)
        }
        enableTapToAdd = true
    }

    private fun updateNearbyObjects(newAssets: List<AnchorInfo>?, newTickets: List<AnchorInfo>?) {
        if (newTickets?.isNotEmpty() == true) {
            for (nt in newTickets) {
                nearbyTickets[nt.id] = nt
                if (anchorVisuals[nt.id] != null) {
                    if (nt.ARanchorId != null) {
                        anchorVisuals[nt.id]!!.info = nt
                        anchorVisuals[nt.id]!!.updateVisual(viewContext)
                    } else {
                        deleteAnchor(nt.id)
                    }
                }
            }
            if (newTickets.size < nearbyTickets.size) {
                for (ot in nearbyTickets.values) {
                    if (newTickets.none { nt -> nt.id == ot.id }) {
                        val id = ot.id
                        nearbyTickets.remove(id)
                        deleteAnchor(id)
                    }
                }
            }
        }
        if (newAssets?.isNotEmpty() == true) {
            //ho dei nuovi ticket
            for (na in newAssets) {
                if (anchorVisuals[na.id] != null) {
                    if (na.ARanchorId != null) {
                        anchorVisuals[na.id]!!.info = na
                        anchorVisuals[na.id]!!.updateVisual(viewContext)
                    } else {
                        deleteAnchor(na.id)
                    }
                }
                val nats = na.tickets
                val oa = nearbyAssets[na.id]
                val oats = oa?.tickets
                if (nats != null) {
                    for (nat in nats) {
                        if (anchorVisuals[nat.id] != null) {
                            if (nat.ARanchorId != null) {
                                anchorVisuals[nat.id]!!.info = nat
                                anchorVisuals[nat.id]!!.updateVisual(viewContext)
                            } else {
                                deleteAnchor(nat.id)
                            }
                        }
                    }
                    if (oa != null && oats != null && nats.size < oats.size) {
                        for (oat in oats) {
                            if (nats.none { nat -> nat.id == oat.id }) {
                                val id = oat.id
                                oa.tickets!!.removeIf { t -> t.id != id }
                                deleteAnchor(id)

                            }
                        }
                    }
                }
                nearbyAssets[na.id] = na
            }
            if (newAssets.size < nearbyAssets.size) {
                for (oa in nearbyAssets.values) {
                    if (newAssets.none { na -> na.id == oa.id }) {
                        val id = oa.id
                        oa.tickets?.forEach { t -> deleteAnchor(t.id) }
                        nearbyAssets.remove(id)
                        deleteAnchor(id)
                    }
                }
            }
        }
        lookForNearbyAnchors()
    }



    override fun getView(): View {
        return arSceneView
    }

    override fun dispose() {
    }

    fun onResume() {
        //queste istruzioni sono eseguite al resume dell'activity e alla costruzione perchè richiamate in init
        Log.d(TAG, "onResume")
        // Create session if there is none
        if (arSceneView.session == null) {
            Log.d(TAG, "ARSceneView session is null. Trying to initialize")
            try {
                val session: Session?
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
            contentView.removeView(animatedGuide)
            showAnimatedGuide = false
        }
    }

    private fun destroyASASession() {
        Log.d(TAG, "destroyASASession")
        if (azureSpatialAnchorsManager != null) {
            azureSpatialAnchorsManager!!.stop()
            azureSpatialAnchorsManager!!.close()
            azureSpatialAnchorsManager = null
        }
        for (visual: AnchorVisual in anchorVisuals.values) {
            activity.runOnUiThread {
                visual.dispose()
            }
        }
        anchorVisuals.clear()
    }

    private fun startASASession() {
        Log.d(TAG, "startNewSession")
        destroyASASession()
        azureSpatialAnchorsManager = AzureSpatialAnchorsManager(arSceneView.session, apiKey, apiId)
        azureSpatialAnchorsManager!!.addSessionUpdatedListener { event ->
            onSessionUpdate(event)
        }

        azureSpatialAnchorsManager!!.addAnchorLocatedListener { event ->
            onAnchorLocated(event)
        }
        azureSpatialAnchorsManager!!.start()
        lookForNearbyAnchors()
    }

    //non entra mai qua
    private fun onPause() {// in realtà va in stop e non in pause
        Log.d(TAG, "onPause") //facciamo pause, facciamo direttamente destroy
        stopArCoreSession()
    }

    private fun onDestroy() {
        Log.d(TAG, "onDestroy")
        try {
            stopArCoreSession()
            destroyASASession()
            arSceneView.renderer?.dispose()
            arSceneView.destroy()
            arSceneView.scene?.removeOnUpdateListener(sceneUpdateListener)

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun onTap(hitTestResult: HitTestResult, motionEvent: MotionEvent?): Boolean {
        val frame = arSceneView.arFrame

        if (hitTestResult.node != null && motionEvent?.action == MotionEvent.ACTION_DOWN) {
            Log.d(TAG, "onTapNode")
            val nodeName = hitTestResult.node!!.name
            val visual = anchorVisuals[nodeName]
            Log.d(TAG, nodeName)
            Log.d(TAG, anchorVisuals.keys.toString())
            if (visual != null) {
                if (visual.info.type == "asset") {
                    anchorManagerChannel.invokeMethod("onAssetTap", nodeName)
                } else if (visual.info.type == "ticket") {
                    anchorManagerChannel.invokeMethod("onTicketTap", nodeName)
                }
            }
            return true
        }
        if (enableTapToAdd && motionEvent != null && motionEvent.action == MotionEvent.ACTION_DOWN) {
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

    private fun createAnchor(transform: ArrayList<Double>, info: AnchorInfo) {
        Log.d(TAG, "addAnchor ${info.id}")
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
        val anchor = arSceneView.session!!.createAnchor(Pose(position, rotation))
        pendingAnchorVisual = AnchorVisual(anchor, info)
        pendingAnchorVisual!!.render(viewContext, arSceneView.scene, false)

    }

    private fun deleteAnchor(infoId: String) {
        val visual = anchorVisuals[infoId]
        if (visual != null) {
            activity.runOnUiThread {
                visual.dispose()
            }
            anchorVisuals.remove(infoId)
        }
    }

    private fun uploadAnchor(result: MethodChannel.Result) {
        Log.d(TAG, "uploadAnchor")
        if (pendingAnchorVisual != null) {
            val cloudAnchor = CloudSpatialAnchor()
            cloudAnchor.localAnchor = pendingAnchorVisual!!.localAnchor
            val now = Date()
            val cal = Calendar.getInstance()
            cal.time = now
            cal.add(Calendar.DATE, 7)
            val oneWeekFromNow = cal.time
            cloudAnchor.expiration = oneWeekFromNow
            //here we use ASA's tools
            azureSpatialAnchorsManager!!.createAnchorAsync(cloudAnchor)
                ?.exceptionally { thrown ->
                    thrown.printStackTrace()
                    result.success(null) as Nothing?
                }?.thenAccept { csa ->
                    this.pendingAnchorVisual!!.cloudAnchor = csa
                    result.success(csa.identifier)
                }
        } else {
            result.success(null)
        }
    }

    private fun deleteCloudAnchor(infoId: String, result: MethodChannel.Result) {
        Log.d(TAG, "removeCloudAnchor $infoId")
        val visual = anchorVisuals[infoId]
        if (visual?.cloudAnchor != null) {
            azureSpatialAnchorsManager!!.deleteAnchorAsync(visual.cloudAnchor!!)
                .exceptionally { thrown ->
                    thrown.printStackTrace()
                    result.success(false) as Nothing?
                }.thenAccept { _ ->
                    activity.runOnUiThread {
                        visual.dispose()
                    }
                    anchorVisuals.remove(infoId)
                    if (nearbyAssets[infoId] != null) {
                        nearbyAssets[infoId]!!.ARanchorId = null
                    } else if (nearbyTickets[infoId] != null) {
                        nearbyTickets[infoId]!!.ARanchorId = null
                    } else {
                        val assetTicket =
                            nearbyAssets.values.mapNotNull { a -> a.tickets }.flatten()
                                .firstOrNull { t -> t.id == infoId }
                        if (assetTicket != null) {
                            assetTicket.ARanchorId = null
                        }
                    }
                    result.success(true)
                }
        }
    }

    private fun lookForNearbyAnchors() {
        if ((nearbyAssets.isEmpty() && nearbyTickets.isEmpty()) || azureSpatialAnchorsManager == null) {
            return
        }
        val ids: ArrayList<String> = ArrayList()
        for (a in nearbyAssets.values) {
            if (a.ARanchorId != null && a.ARanchorId != "") {
                ids.add(a.ARanchorId!!)
            }
            if (a.tickets?.isNotEmpty() == true) {
                ids.addAll(a.tickets!!.mapNotNull { t -> t.ARanchorId })
            }
        }
        for (t in nearbyTickets.values) {
            if (t.ARanchorId != null && t.ARanchorId != "") {
                ids.add(t.ARanchorId!!)
            }
        }
        val criteria = AnchorLocateCriteria()
        Log.d(TAG, "lookForNearbyAnchors ${ids.toString()}")
        criteria.identifiers = ids.toTypedArray()
        azureSpatialAnchorsManager!!.startLocating(criteria)

    }

    private fun onAnchorLocated(event: AnchorLocatedEvent) {
        val status = event.status
        Log.d(TAG, "VISUAL: ${anchorVisuals.values.map { v -> v.cloudAnchor?.identifier }}")
        if (status == LocateAnchorStatus.Located || status == LocateAnchorStatus.AlreadyTracked) {
            Log.d(TAG, "onAnchorLocated ${ event.anchor.identifier} STATUS: ${event.status}")
            val cloudAnchor = event.anchor
            val asset =
                nearbyAssets.values.firstOrNull { a -> a.ARanchorId == cloudAnchor.identifier }
            val ticket =
                nearbyTickets.values.firstOrNull { a -> a.ARanchorId == cloudAnchor.identifier }
            if (asset != null) {
                if (anchorVisuals[asset.id] == null) {
                    activity.runOnUiThread {
                        val visual = AnchorVisual(cloudAnchor.localAnchor, asset)
                        visual.cloudAnchor = cloudAnchor
                        anchorVisuals[asset.id] = visual
                        visual.render(viewContext, arSceneView.scene, false)
                    }
                }
            } else if (ticket != null) {
                if (anchorVisuals[ticket.id] == null) {
                    activity.runOnUiThread {
                        val visual = AnchorVisual(cloudAnchor.localAnchor, ticket)
                        visual.cloudAnchor = cloudAnchor
                        anchorVisuals[ticket.id] = visual
                        visual.render(viewContext, arSceneView.scene, hideTickets)
                    }
                }
            } else {
                val assetTicket = nearbyAssets.values.mapNotNull { a -> a.tickets }.flatten()
                    .firstOrNull { t -> t.ARanchorId == cloudAnchor.identifier }
                val parentAsset =
                    nearbyAssets.values.firstOrNull { a -> a.tickets != null && a.tickets!!.any { t -> t.ARanchorId == cloudAnchor.identifier } }
                if (assetTicket != null && parentAsset != null) {
                    activity.runOnUiThread {
                        val visual = AnchorVisual(cloudAnchor.localAnchor, assetTicket)
                        visual.cloudAnchor = cloudAnchor
                        anchorVisuals[assetTicket.id] = visual
                        visual.render(
                            viewContext,
                            arSceneView.scene,
                            hideAssetTickets[parentAsset.id] ?: true
                        )
                    }
                }
            }
        }
        else{
            Log.d(TAG, "onAnchorLocated NULL STATUS: ${event.status}")
        }
    }

    //makes sure there are enough frames
    //SessionUpdatedEvent is from ASA cloud
    private fun onSessionUpdate(event: SessionUpdatedEvent?) {
        if (event != null) {
            val recommendedForCreateProgress = event.status.recommendedForCreateProgress
            //var requiredForCreateProgress = event.status.readyForCreateProgress;
            if (recommendedForCreateProgress >= 1.0f) {
                activity.runOnUiThread {
                    sessionManagerChannel.invokeMethod("readyToUpload", null)
                }
            }
        }
    }
}


