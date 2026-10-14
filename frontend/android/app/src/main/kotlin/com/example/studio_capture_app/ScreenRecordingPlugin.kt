package com.example.studio_capture_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

class ScreenRecordingPlugin : MethodCallHandler, FlutterPlugin, ActivityAware {
    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    private var isRecording = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        MediaProjectionHolder.applicationContext = binding.applicationContext
        MediaProjectionHolder.mediaProjectionManager = context?.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager?
        methodChannel = MethodChannel(binding.binaryMessenger, "screen_recording")
        methodChannel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        context = null
        mediaProjectionManager = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
    }

    private val activityResultListener = object : io.flutter.plugin.common.PluginRegistry.ActivityResultListener {
        override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
            if (requestCode == 1001) {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    MediaProjectionHolder.mediaProjection = MediaProjectionHolder.mediaProjectionManager?.getMediaProjection(resultCode, data!!)
                    pendingResult?.success(true)
                } else {
                    pendingResult?.error("PERMISSION_DENIED", "User denied screen recording permission", null)
                }
                pendingResult = null
            }
            return true
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "startRecording" -> startRecording(call, result)
            "pauseRecording" -> pauseRecording(result)
            "resumeRecording" -> resumeRecording(result)
            "stopRecording" -> stopRecording(result)
            "getRecordingStatus" -> getRecordingStatus(result)
            "setVideoEnabled" -> setVideoEnabled(call, result)
            "setAudioMuted" -> setAudioMuted(call, result)
            "setFacecamEnabled" -> setFacecamEnabled(call, result)
            "setConfig" -> setConfig(call, result)
            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("UNSUPPORTED", "Screen recording requires Android 5.0+", null)
            return
        }

        val activity = activity ?: return
        pendingResult = result

        val permissionIntent = MediaProjectionHolder.mediaProjectionManager?.createScreenCaptureIntent()
        if (permissionIntent != null) {
            activity.startActivityForResult(permissionIntent, 1001)
        } else {
            result.error("ERROR", "Failed to create screen capture intent", null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun startRecording(call: MethodCall, result: Result) {
        if (MediaProjectionHolder.mediaProjection == null) {
            result.error("NO_PERMISSION", "Screen recording permission not granted", null)
            return
        }

        val config = call.arguments as? Map<String, Any?> ?: mapOf()
        val enableAudio = config["enableAudio"] as? Boolean ?: true
        val enableVideo = config["enableVideo"] as? Boolean ?: true
        val mode = config["mode"] as? String ?: ""
        val showFacecam = (config["showFacecam"] as? Boolean ?: false) || mode == "facecam"
        val facecamShape = config["facecamShape"] as? String ?: "Square (PiP)"
        val resolution = config["resolution"] as? String ?: "1080p"
        val fps = config["fps"] as? Int ?: 30
        val bitrate = (config["bitrate"] as? Double)?.toFloat() ?: 16f
        val orientation = config["orientation"] as? String ?: "Auto"
        val audioSource = config["audioSource"] as? String ?: "Internal + Mic"
        val showTouches = config["showTouches"] as? Boolean ?: false
        val floatingBubble = config["floatingBubble"] as? Boolean ?: false
        val shakeToStop = config["shakeToStop"] as? Boolean ?: false

        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            putExtra("enableAudio", enableAudio)
            putExtra("enableVideo", enableVideo)
            putExtra("showFacecam", showFacecam)
            putExtra("facecamShape", facecamShape)
            putExtra("resolution", resolution)
            putExtra("fps", fps)
            putExtra("bitrate", bitrate)
            putExtra("orientation", orientation)
            putExtra("audioSource", audioSource)
            putExtra("showTouches", showTouches)
            putExtra("floatingBubble", floatingBubble)
            putExtra("shakeToStop", shakeToStop)
            action = "start"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            MediaProjectionHolder.applicationContext?.startForegroundService(serviceIntent)
        } else {
            MediaProjectionHolder.applicationContext?.startService(serviceIntent)
        }

        result.success(true)
    }

    private fun pauseRecording(result: Result) {
        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            action = "pause"
        }
        MediaProjectionHolder.applicationContext?.sendBroadcast(serviceIntent)
        result.success(true)
    }

    private fun resumeRecording(result: Result) {
        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            action = "resume"
        }
        MediaProjectionHolder.applicationContext?.sendBroadcast(serviceIntent)
        result.success(true)
    }

    private fun stopRecording(result: Result) {
        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            action = "stop"
            putExtra("action", "stop") // For the broadcast receiver
        }
        MediaProjectionHolder.applicationContext?.sendBroadcast(serviceIntent)
        
        // Wait briefly for the service to finish stopping and saving the file
        Handler(Looper.getMainLooper()).postDelayed({
            result.success(ScreenRecordingService.lastRecordingPath)
        }, 500)
    }

    private fun getRecordingStatus(result: Result) {
        val map = java.util.HashMap<String, Any>()
        map["isRecording"] = ScreenRecordingService.isRecording
        map["hasPermission"] = MediaProjectionHolder.mediaProjection != null
        result.success(map)
    }

    private fun setVideoEnabled(call: MethodCall, result: Result) {
        val enabled = call.arguments as? Boolean ?: true
        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            action = "setVideoEnabled"
            putExtra("enabled", enabled)
        }
        MediaProjectionHolder.applicationContext?.sendBroadcast(serviceIntent)
        result.success(true)
    }

    private fun setAudioMuted(call: MethodCall, result: Result) {
        val muted = call.arguments as? Boolean ?: false
        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            action = "setAudioMuted"
            putExtra("muted", muted)
        }
        MediaProjectionHolder.applicationContext?.sendBroadcast(serviceIntent)
        result.success(true)
    }

    private fun setFacecamEnabled(call: MethodCall, result: Result) {
        val enabled = if (call.arguments is Map<*, *>) {
            (call.arguments as Map<*, *>)["enabled"] as? Boolean ?: true
        } else {
            call.arguments as? Boolean ?: true
        }
        val shape = if (call.arguments is Map<*, *>) {
            (call.arguments as Map<*, *>)["shape"] as? String
        } else null

        val serviceIntent = Intent(MediaProjectionHolder.applicationContext, ScreenRecordingService::class.java).apply {
            action = "setFacecamEnabled"
            putExtra("enabled", enabled)
            if (shape != null) {
                putExtra("facecamShape", shape)
            }
        }
        MediaProjectionHolder.applicationContext?.sendBroadcast(serviceIntent)
        ScreenRecordingService.currentInstance?.setFacecamEnabled(enabled, shape)
        result.success(true)
    }

    private fun setConfig(call: MethodCall, result: Result) {
        result.success(true)
    }
}

object MediaProjectionHolder {
    var mediaProjection: MediaProjection? = null
    var mediaProjectionManager: MediaProjectionManager? = null
    var applicationContext: Context? = null
    var resultCode: Int = 0
    var resultData: Intent? = null
}