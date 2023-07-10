package io.carius.lars.ar_flutter_plugin

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import android.util.Log

class AndroidARViewFactory(private val activity: Activity, private val messenger: BinaryMessenger) :
        PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private var TAG: String = "AndroidARViewFactory"
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        Log.d(TAG, "create AndroidARView")
        val creationParams = args as Map<String?, Any?>?
        return AndroidARView(activity, context, messenger, viewId, creationParams)
    }
}
