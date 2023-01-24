package io.carius.lars.ar_flutter_plugin

import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

import com.microsoft.CloudServices

/** ArFlutterPlugin */
class ArFlutterPlugin : FlutterPlugin, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

  override fun onAttachedToEngine(
      flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
  ) {
    this.flutterPluginBinding = flutterPluginBinding
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.flutterPluginBinding.platformViewRegistry.registerViewFactory(
        "ar_flutter_plugin_view", AndroidARViewFactory(binding.activity, flutterPluginBinding.binaryMessenger))
    CloudServices.initialize(binding.activity)
  }

  override fun onDetachedFromActivity() {
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }
}
