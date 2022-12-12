// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.
package io.carius.lars.ar_flutter_plugin

import android.util.Log
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.microsoft.azure.spatialanchors.*
import java.util.*
import java.util.List
import java.util.concurrent.*
import java.util.function.Supplier

internal class AzureSpatialAnchorsManager(arCoreSession: Session?) {
    private val executorService: ExecutorService = Executors.newFixedThreadPool(2)
    var isRunning = false
    private val spatialAnchorsSession: CloudSpatialAnchorSession

    companion object {
        // Set this string to the account ID provided for the Azure Spatial Anchors account resource.
        const val SpatialAnchorsAccountId = "dd0d9d8a-b72c-41ba-9075-36071c430b17"

        // Set this string to the account key provided for the Azure Spatial Anchors account resource.
        const val SpatialAnchorsAccountKey = "Yz0+xeuZmCBu7QQ3coFF12Sg7N7nh52QXj9dfJVX0F0="

        // Set this string to the account domain provided for the Azure Spatial Anchors account resource.
        const val SpatialAnchorsAccountDomain = "westeurope.mixedreality.azure.com"

        // Log message tag
        private const val TAG = "ASACloud"
    }

    init {
        if (arCoreSession == null) {
            throw IllegalArgumentException("The arCoreSession may not be null.")
        }
        spatialAnchorsSession = CloudSpatialAnchorSession()
        spatialAnchorsSession.configuration.accountId = SpatialAnchorsAccountId
        spatialAnchorsSession.configuration.accountKey = SpatialAnchorsAccountKey
        spatialAnchorsSession.configuration.accountDomain = SpatialAnchorsAccountDomain
        spatialAnchorsSession.session = arCoreSession
        spatialAnchorsSession.logLevel = SessionLogLevel.All
        spatialAnchorsSession.addOnLogDebugListener { args: OnLogDebugEvent? ->
            if (args != null) {
                onLogDebugListener(args)
            }
        }
        spatialAnchorsSession.addErrorListener { event: SessionErrorEvent? ->
            if (event != null) {
                onErrorListener(event)
            }
        }
    }

    //region Listener Handling
    fun addSessionUpdatedListener(listener: SessionUpdatedListener?) {
        spatialAnchorsSession.addSessionUpdatedListener(listener)
    }

    fun removeSessionUpdatedListener(listener: SessionUpdatedListener?) {
        spatialAnchorsSession.removeSessionUpdatedListener(listener)
    }

    fun addAnchorLocatedListener(listener: AnchorLocatedListener?) {
        spatialAnchorsSession.addAnchorLocatedListener(listener)
    }

    fun removeAnchorLocatedListener(listener: AnchorLocatedListener?) {
        spatialAnchorsSession.removeAnchorLocatedListener(listener)
    }

    fun addLocateAnchorsCompletedListener(listener: LocateAnchorsCompletedListener?) {
        spatialAnchorsSession.addLocateAnchorsCompletedListener(listener)
    }

    fun removeLocateAnchorsCompletedListener(listener: LocateAnchorsCompletedListener?) {
        spatialAnchorsSession.removeLocateAnchorsCompletedListener(listener)
    }

    //endregion
    fun setLocationProvider(locationProvider: PlatformLocationProvider?) {
        spatialAnchorsSession.locationProvider = locationProvider
    }

    // creates an asynchronous operation that creates a cloud anchor and then returns 
    //the same anchor once the operation is complete
    fun createAnchorAsync(anchor: CloudSpatialAnchor): CompletableFuture<CloudSpatialAnchor>? {
        return toEmptyCompletableFuture(spatialAnchorsSession.createAnchorAsync(anchor))
                .thenApply { anchor }
    }

    fun deleteAnchorAsync(anchor: CloudSpatialAnchor?): CompletableFuture<*>? {
        return toEmptyCompletableFuture(spatialAnchorsSession.deleteAnchorAsync(anchor))
    }

    fun reset() {
        stopLocating()
        spatialAnchorsSession.reset()
    }

    fun start() {
        spatialAnchorsSession.start()
        isRunning = true
    }

    fun startLocating(criteria: AnchorLocateCriteria?): CloudSpatialAnchorWatcher {
        // Only 1 active watcher at a time is permitted.
        stopLocating()
        return spatialAnchorsSession.createWatcher(criteria)
    }

    val isLocating: Boolean
        get() = spatialAnchorsSession.activeWatchers.isNotEmpty()

    fun stopLocating() {
        val watchers: MutableList<CloudSpatialAnchorWatcher>? = spatialAnchorsSession.activeWatchers
        if (watchers != null) {
            if (watchers.isEmpty()) {
                return
            }
        }

        // Only 1 watcher is at a time is currently permitted.
        val watcher: CloudSpatialAnchorWatcher = watchers!![0]
        watcher.stop()
    }

    fun stop() {
        spatialAnchorsSession.stop()
        stopLocating()
        isRunning = false
    }

    fun update(frame: Frame?) {
        spatialAnchorsSession.processFrame(frame)
    }

    private fun toEmptyCompletableFuture(future: Future<*>): CompletableFuture<*> {
        return CompletableFuture.runAsync(Runnable {
            try {
                future.get()
            } catch (e: InterruptedException) {
                e.printStackTrace()
                throw RuntimeException(e)
            } catch (e: ExecutionException) {
                e.printStackTrace()
                throw RuntimeException(e)
            }
        }, executorService)
    }

    private fun onErrorListener(event: SessionErrorEvent) {
        Log.e(TAG, event.errorMessage)
    }

    private fun onLogDebugListener(args: OnLogDebugEvent) {
        Log.d(TAG, args.message)
    }
}