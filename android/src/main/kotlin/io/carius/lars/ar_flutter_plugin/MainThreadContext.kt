package io.carius.lars.ar_flutter_plugin

import android.os.Looper
import android.os.Handler

class MainThreadContext {
    private val mainHandler: Handler = Handler(Looper.getMainLooper())
    private val mainLooper = Looper.getMainLooper()

    fun runOnUiThread(runnable: Runnable) {
        if (mainLooper.isCurrentThread) {
            runnable.run()
        } else {
            mainHandler.post(runnable)
        }
    }
}