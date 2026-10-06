package com.example.screen_recording_app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.nio.ByteBuffer
import android.os.Environment
import android.content.ContentValues
import android.provider.MediaStore
import android.media.MediaScannerConnection
import android.media.MediaMetadataRetriever
import android.media.AudioManager
import android.media.ToneGenerator
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMuxer
import android.media.MediaFormat
import android.os.Vibrator
import android.os.VibrationEffect
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import android.app.NotificationManager
import android.app.NotificationChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "screen_recording"
    private var methodChannel: MethodChannel? = null
    private var pendingResult: Result? = null

    private val stateChangeReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "screen_recording_state_changed") {
                val isRecording = intent.getBooleanExtra("isRecording", false)
                val isPaused = intent.getBooleanExtra("isPaused", false)
                val isAudioMuted = intent.getBooleanExtra("isAudioMuted", false)
                val isVideoEnabled = intent.getBooleanExtra("isVideoEnabled", true)
                val showFacecam = intent.getBooleanExtra("showFacecam", false)
                val facecamShape = intent.getStringExtra("facecamShape")
                val lastRecordingPath = intent.getStringExtra("lastRecordingPath")

                methodChannel?.invokeMethod("onRecordingStateChanged", mapOf(
                    "isRecording" to isRecording,
                    "isPaused" to isPaused,
                    "isAudioMuted" to isAudioMuted,
                    "isVideoEnabled" to isVideoEnabled,
                    "showFacecam" to showFacecam,
                    "facecamShape" to facecamShape,
                    "lastRecordingPath" to lastRecordingPath
                ))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaProjectionHolder.applicationContext = applicationContext
        MediaProjectionHolder.mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? android.media.projection.MediaProjectionManager

        val filter = android.content.IntentFilter("screen_recording_state_changed")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stateChangeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stateChangeReceiver, filter)
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        val secondChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "screen_recording_app/recording")
        val handler = MethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> handleRequestPermission(result)
                "startRecording" -> handleStartRecording(call, result)
                "pauseRecording" -> handlePauseRecording(result)
                "resumeRecording" -> handleResumeRecording(result)
                "stopRecording" -> handleStopRecording(result)
                "getRecordingStatus" -> handleGetRecordingStatus(result)
                "setVideoEnabled" -> handleSetVideoEnabled(call, result)
                "setAudioMuted" -> handleSetAudioMuted(call, result)
                "setFacecamEnabled" -> handleSetFacecamEnabled(call, result)
                "saveToGallery" -> handleSaveToGallery(call, result)
                "saveImageToGallery" -> handleSaveImageToGallery(call, result)
                "getVideoMetadata" -> handleGetVideoMetadata(call, result)
                "getStorageInfo" -> handleGetStorageInfo(result)
                "scanFile" -> handleScanFile(call, result)
                "setConfig" -> result.success(true)
                "authenticateBiometric" -> handleAuthenticateBiometric(call, result)
                "setHideSensitiveContent" -> handleSetHideSensitiveContent(call, result)
                "openEmailClient" -> handleOpenEmailClient(call, result)
                "playAudioCue" -> handlePlayAudioCue(call, result)
                "vibrate" -> handleVibrate(call, result)
                "showSystemNotification" -> handleShowSystemNotification(call, result)
                "trimVideo" -> handleTrimVideo(call, result)
                "enableAutoSync" -> {
                    CloudSyncManager.startAutoSync(this)
                    result.success(true)
                }
                "disableAutoSync" -> {
                    CloudSyncManager.cancelAllSync(this)
                    result.success(true)
                }
                "syncRecordingNow" -> {
                    val path = call.argument<String>("filePath") ?: ""
                    CloudSyncManager.enqueueUpload(this, path)
                    result.success(true)
                }
                "isAutoSyncEnabled" -> {
                    result.success(CloudSyncManager.isAutoSyncEnabled(this))
                }
                else -> result.notImplemented()
            }
        }
        methodChannel?.setMethodCallHandler(handler)
        secondChannel.setMethodCallHandler(handler)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(stateChangeReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra("route")
        val savedPath = intent.getStringExtra("savedPath")
        if (route != null) {
            methodChannel?.invokeMethod("onNavigateRoute", mapOf(
                "route" to route,
                "savedPath" to savedPath
            ))
        }
    }

    private fun handleRequestPermission(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("UNSUPPORTED", "Screen recording requires Android 5.0+", null)
            return
        }
        pendingResult = result
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? android.media.projection.MediaProjectionManager
        val permissionIntent = mediaProjectionManager?.createScreenCaptureIntent()
        if (permissionIntent != null) {
            startActivityForResult(permissionIntent, 1001)
        } else {
            result.error("ERROR", "Failed to create screen capture intent", null)
            pendingResult = null
        }
    }

    private fun handleStartRecording(call: MethodCall, result: Result) {
        if (MediaProjectionHolder.resultData == null && MediaProjectionHolder.mediaProjection == null) {
            result.error("NO_PERMISSION", "Screen recording permission not granted. Please request permission first.", null)
            return
        }

        val config = call.arguments as? Map<String, Any?> ?: mapOf()
        val enableAudio = config["enableAudio"] as? Boolean ?: true
        val enableVideo = config["enableVideo"] as? Boolean ?: true
        val showFacecam = config["showFacecam"] as? Boolean ?: false
        val facecamShape = config["facecamShape"] as? String ?: "Square (PiP)"
        val resolution = config["resolution"] as? String ?: "1080p"
        val fps = (config["fps"] as? Number)?.toInt() ?: 30
        val bitrate = (config["bitrate"] as? Number)?.toFloat() ?: 16f
        val rawOrientation = config["orientation"] as? String ?: "Auto"
        val orientation = rawOrientation.split(" ").firstOrNull() ?: "Auto"
        val audioSource = config["audioSource"] as? String ?: "Internal + Mic"
        val showTouches = config["showTouches"] as? Boolean ?: false
        val floatingBubble = config["floatingBubble"] as? Boolean ?: false
        val shakeToStop = config["shakeToStop"] as? Boolean ?: false
        val floatingNotification = config["floatingNotification"] as? Boolean ?: true

        val hideSensitive = config["hideSensitiveContent"] as? Boolean ?: false

        // Apply / remove FLAG_SECURE based on hideSensitiveContent setting
        runOnUiThread {
            if (hideSensitive) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }

        val serviceIntent = Intent(this, ScreenRecordingService::class.java).apply {
            action = "start"
            putExtra("resultCode", MediaProjectionHolder.resultCode)
            putExtra("resultData", MediaProjectionHolder.resultData)
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
            putExtra("floatingNotification", floatingNotification)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        result.success(true)
    }

    private fun handlePauseRecording(result: Result) {
        ScreenRecordingService.currentInstance?.pauseRecording()
        val serviceIntent = Intent(this, ScreenRecordingService::class.java).apply {
            action = ScreenRecordingService.ACTION_PAUSE
        }
        startService(serviceIntent)
        result.success(true)
    }

    private fun handleResumeRecording(result: Result) {
        ScreenRecordingService.currentInstance?.resumeRecording()
        val serviceIntent = Intent(this, ScreenRecordingService::class.java).apply {
            action = ScreenRecordingService.ACTION_RESUME
        }
        startService(serviceIntent)
        result.success(true)
    }

    private fun handleStopRecording(result: Result) {
        val instance = ScreenRecordingService.currentInstance
        if (instance != null) {
            // stopRecording() is synchronous — it blocks until MediaRecorder.stop() +
            // the audio/video remux have both completed, then returns the final path.
            val path = instance.stopRecording()
            result.success(path ?: ScreenRecordingService.lastRecordingPath)
        } else if (ScreenRecordingService.lastRecordingPath != null) {
            // Service already finished (e.g. shake-to-stop or notification stop)
            result.success(ScreenRecordingService.lastRecordingPath)
        } else {
            // Service not running — send stop intent and wait briefly
            val serviceIntent = Intent(this, ScreenRecordingService::class.java).apply {
                action = ScreenRecordingService.ACTION_STOP
                putExtra("action", "stop")
            }
            startService(serviceIntent)
            Handler(Looper.getMainLooper()).postDelayed({
                result.success(ScreenRecordingService.lastRecordingPath)
            }, 1500)  // Allow mux to finish before returning
        }
    }

    private fun handleGetRecordingStatus(result: Result) {
        val service = ScreenRecordingService.currentInstance
        val status = mapOf(
            "isRecording" to ScreenRecordingService.isRecording,
            "isPaused" to (service?.isPaused ?: false),
            "isAudioMuted" to (service?.isAudioMuted ?: false),
            "isVideoEnabled" to (service?.isVideoEnabled ?: true),
            "lastRecordingPath" to ScreenRecordingService.lastRecordingPath
        )
        result.success(status)
    }

    private fun handleSetVideoEnabled(call: MethodCall, result: Result) {
        val enabled = call.arguments as? Boolean ?: true
        ScreenRecordingService.currentInstance?.setVideoEnabled(enabled)
        result.success(true)
    }

    private fun handleSetAudioMuted(call: MethodCall, result: Result) {
        val muted = call.arguments as? Boolean ?: false
        ScreenRecordingService.currentInstance?.setAudioMuted(muted)
        result.success(true)
    }

    private fun handleSetFacecamEnabled(call: MethodCall, result: Result) {
        val enabled = if (call.arguments is Map<*, *>) {
            (call.arguments as Map<*, *>)["enabled"] as? Boolean ?: true
        } else {
            call.arguments as? Boolean ?: true
        }
        val shape = if (call.arguments is Map<*, *>) {
            (call.arguments as Map<*, *>)["shape"] as? String
        } else null

        ScreenRecordingService.currentInstance?.setFacecamEnabled(enabled, shape)
        val serviceIntent = Intent(this, ScreenRecordingService::class.java).apply {
            action = "setFacecamEnabled"
            putExtra("enabled", enabled)
            if (shape != null) {
                putExtra("facecamShape", shape)
            }
        }
        sendBroadcast(serviceIntent)
        result.success(true)
    }

    private fun handleSaveToGallery(call: MethodCall, result: Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath == null) {
            result.error("INVALID_PATH", "File path cannot be null", null)
            return
        }

        val sourceFile = File(filePath)
        if (!sourceFile.exists()) {
            result.error("FILE_NOT_FOUND", "File does not exist at $filePath", null)
            return
        }

        // Extract video metadata for proper Gallery display
        var durationMs = 0L
        try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(filePath)
            durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            retriever.release()
        } catch (_: Exception) {}

        val nowMs = System.currentTimeMillis()
        val fileSizeBytes = sourceFile.length()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, sourceFile.name)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/ScreenRecordingApp")
                    put(MediaStore.Video.Media.DATE_TAKEN, nowMs)
                    put(MediaStore.Video.Media.DATE_MODIFIED, nowMs / 1000)
                    put(MediaStore.Video.Media.DATE_ADDED, nowMs / 1000)
                    if (durationMs > 0) put(MediaStore.Video.Media.DURATION, durationMs)
                    put(MediaStore.Video.Media.SIZE, fileSizeBytes)
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }

                val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val uri = contentResolver.insert(collection, values)

                if (uri != null) {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        sourceFile.inputStream().use { input ->
                            input.copyTo(out)
                        }
                    }
                    // Clear IS_PENDING so Gallery indexes it immediately
                    values.clear()
                    values.put(MediaStore.Video.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)

                    // Also trigger MediaScanner on the source for app library
                    MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(sourceFile.absolutePath),
                        arrayOf("video/mp4"),
                        null
                    )
                    result.success(true)
                } else {
                    result.error("INSERT_FAILED", "Failed to create MediaStore entry", null)
                }
            } else {
                // Android < 10: copy to public Movies directory
                val publicDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "ScreenRecordingApp")
                publicDir.mkdirs()
                val destFile = File(publicDir, sourceFile.name)
                sourceFile.copyTo(destFile, overwrite = true)
                MediaScannerConnection.scanFile(
                    applicationContext,
                    arrayOf(destFile.absolutePath),
                    arrayOf("video/mp4"),
                    null
                )
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("SAVE_FAILED", "Failed to save to gallery: ${e.message}", null)
        }
    }

    private fun handleSaveImageToGallery(call: MethodCall, result: Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val filename = call.argument<String>("filename") ?: "Screenshot_${System.currentTimeMillis()}.png"
        if (bytes == null) {
            result.error("INVALID_DATA", "Image bytes cannot be null", null)
            return
        }
        try {
            val contentResolver = applicationContext.contentResolver
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val contentValues = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/ScreenRecordingApp")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                if (uri != null) {
                    contentResolver.openOutputStream(uri)?.use { stream ->
                        stream.write(bytes)
                    }
                    contentValues.clear()
                    contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, contentValues, null, null)
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(uri.toString()), arrayOf("image/png"), null)
                    result.success(true)
                } else {
                    result.error("INSERT_FAILED", "Failed to create Image MediaStore entry", null)
                }
            } else {
                val picDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "ScreenRecordingApp")
                picDir.mkdirs()
                val destFile = File(picDir, filename)
                destFile.writeBytes(bytes)
                MediaScannerConnection.scanFile(applicationContext, arrayOf(destFile.absolutePath), arrayOf("image/png"), null)
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("SAVE_FAILED", "Failed to save screenshot: ${e.message}", null)
        }
    }

    private fun handleGetStorageInfo(result: Result) {
        try {
            var totalBytes: Long = 0L
            var availableBytes: Long = 0L

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val storageStatsManager = getSystemService(Context.STORAGE_STATS_SERVICE) as? android.app.usage.StorageStatsManager
                    if (storageStatsManager != null) {
                        val uuid = android.os.storage.StorageManager.UUID_DEFAULT
                        totalBytes = storageStatsManager.getTotalBytes(uuid)
                        availableBytes = storageStatsManager.getFreeBytes(uuid)
                    }
                } catch (e: Exception) {
                    android.util.Log.w("MainActivity", "StorageStatsManager query failed, falling back to StatFs: ${e.message}")
                }
            }

            if (totalBytes <= 0L || availableBytes <= 0L) {
                val targetPath = try {
                    if (Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED) {
                        Environment.getExternalStorageDirectory().path
                    } else {
                        Environment.getDataDirectory().path
                    }
                } catch (_: Exception) {
                    Environment.getDataDirectory().path
                }
                val stat = android.os.StatFs(targetPath)
                val blockSize = stat.blockSizeLong
                totalBytes = stat.blockCountLong * blockSize
                availableBytes = stat.availableBlocksLong * blockSize
            }

            val usedBytes = (totalBytes - availableBytes).coerceAtLeast(0)
            val availableFormatted = android.text.format.Formatter.formatFileSize(this, availableBytes)
            val totalFormatted = android.text.format.Formatter.formatFileSize(this, totalBytes)
            val usedFormatted = android.text.format.Formatter.formatFileSize(this, usedBytes)

            result.success(mapOf(
                "totalDeviceBytes" to totalBytes,
                "availableDeviceBytes" to availableBytes,
                "usedDeviceBytes" to usedBytes,
                "availableFormatted" to availableFormatted,
                "totalFormatted" to totalFormatted,
                "usedFormatted" to usedFormatted
            ))
        } catch (e: Exception) {
            result.error("STORAGE_ERROR", e.message, null)
        }
    }

    private fun handleScanFile(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path != null) {
            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
            result.success(true)
        } else {
            result.success(false)
        }
    }

    // ── Biometric Authentication ────────────────────────────────────────────
    private fun handleAuthenticateBiometric(call: MethodCall, result: Result) {
        val reason = (call.arguments as? Map<*, *>)?.get("reason") as? String
            ?: "Unlock your saved recordings"

        val biometricManager = BiometricManager.from(this)
        val canAuth = biometricManager.canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL
        )

        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            result.error("NOT_AVAILABLE",
                "Biometric authentication is not available or not enrolled on this device.",
                null)
            return
        }

        val executor = ContextCompat.getMainExecutor(this)
        var resultSent = false

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                if (!resultSent) { resultSent = true; result.success(true) }
            }
            override fun onAuthenticationFailed() {
                // Failed but not cancelled — let user retry; don't resolve yet.
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (!resultSent) {
                    resultSent = true
                    if (errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                        errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON) {
                        result.success(false)
                    } else {
                        result.error("AUTH_ERROR", errString.toString(), null)
                    }
                }
            }
        }

        val prompt = BiometricPrompt(this, executor, callback)
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("App Lock")
            .setSubtitle(reason)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
            .build()
        prompt.authenticate(promptInfo)
    }

    // ── Hide Sensitive Content (FLAG_SECURE) ────────────────────────────────
    private fun handleSetHideSensitiveContent(call: MethodCall, result: Result) {
        val hide = call.arguments as? Boolean ?: false
        runOnUiThread {
            if (hide) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
        result.success(true)
    }

    private fun handleGetVideoMetadata(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("INVALID_PATH", "Path is required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "File not found at $path", null)
            return
        }
        try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val bitrateStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
            val captureFpsStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
            val durationMs = durationStr?.toLongOrNull() ?: 0L
            val width = widthStr?.toIntOrNull() ?: 0
            val height = heightStr?.toIntOrNull() ?: 0
            val rotation = rotationStr?.toIntOrNull() ?: 0
            val bitrate = bitrateStr?.toLongOrNull() ?: if (durationMs > 0) (file.length() * 8000L / durationMs) else 0L
            val fps = captureFpsStr?.toDoubleOrNull() ?: 0.0

            var thumbnailPath: String? = null
            try {
                // Cache key includes file length so a new recording with the same name
                // always gets a fresh thumbnail instead of the stale cached one.
                val cacheKey = "${file.name}_${file.length()}".hashCode()
                val thumbFile = File(cacheDir, "thumb_${cacheKey}.jpg")
                if (thumbFile.exists() && thumbFile.length() > 0) {
                    thumbnailPath = thumbFile.absolutePath
                } else {
                    val frameTimeUs = if (durationMs > 1000) 500000L else 0L
                    val frame = retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: retriever.getFrameAtTime(0)
                    if (frame != null) {
                        java.io.FileOutputStream(thumbFile).use { outStream ->
                            frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, outStream)
                        }
                        frame.recycle()
                        thumbnailPath = thumbFile.absolutePath
                    }
                }
            } catch (_: Exception) {}

            retriever.release()

            result.success(mapOf(
                "durationMs" to durationMs,
                "width" to width,
                "height" to height,
                "rotation" to rotation,
                "bitrate" to bitrate,
                "fps" to fps,
                "thumbnailPath" to thumbnailPath
            ))
        } catch (e: Exception) {
            result.error("METADATA_ERROR", e.message, null)
        }
    }

    private fun handleOpenEmailClient(call: MethodCall, result: Result) {
        val client = call.argument<String>("client") ?: "gmail"
        val to = call.argument<String>("to") ?: "contact@ispcorp.in"
        val subject = call.argument<String>("subject") ?: "Studio Capture — Support Request"
        val body = call.argument<String>("body") ?: ""

        val uri = android.net.Uri.parse("mailto:$to?subject=${android.net.Uri.encode(subject)}&body=${android.net.Uri.encode(body)}")
        val targetPackage = if (client.equals("gmail", ignoreCase = true)) "com.google.android.gm" else "com.microsoft.office.outlook"

        var launched = false
        // Attempt 1: Direct SENDTO with target package (opens compose directly in Gmail/Outlook)
        try {
            val appIntent = Intent(Intent.ACTION_SENDTO, uri).apply {
                setPackage(targetPackage)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(appIntent)
            launched = true
        } catch (_: Exception) {}

        // Attempt 2: Direct VIEW intent with target package
        if (!launched) {
            try {
                val viewIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                    setPackage(targetPackage)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(viewIntent)
                launched = true
            } catch (_: Exception) {}
        }

        // Attempt 3: Fallback to general email intent if specific package is absent
        if (!launched) {
            try {
                val genericIntent = Intent(Intent.ACTION_SENDTO, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(genericIntent)
                launched = true
            } catch (_: Exception) {}
        }

        result.success(launched)
    }

    private fun handlePlayAudioCue(call: MethodCall, result: Result) {
        val type = call.argument<String>("type") ?: "start"
        try {
            val toneType = when (type) {
                "start" -> ToneGenerator.TONE_PROP_PROMPT
                "stop" -> ToneGenerator.TONE_PROP_ACK
                "tick" -> ToneGenerator.TONE_PROP_BEEP
                else -> ToneGenerator.TONE_PROP_BEEP
            }
            val duration = when (type) {
                "start" -> 160
                "stop" -> 180
                "tick" -> 60
                else -> 80
            }
            val toneGen = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90)
            toneGen.startTone(toneType, duration)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleVibrate(call: MethodCall, result: Result) {
        val duration = (call.argument<Int>("duration") ?: 100).toLong()
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator ?: (@Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(duration)
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleShowSystemNotification(call: MethodCall, result: Result) {
        val title = call.argument<String>("title") ?: "Video Export"
        val message = call.argument<String>("message") ?: "Operation completed"
        try {
            val channelId = "screen_recording_alerts"
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Recording & Export Alerts",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Alerts for export and trim completion"
                }
                notificationManager.createNotificationChannel(channel)
            }
            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(title)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()
            notificationManager.notify((System.currentTimeMillis() % 10000).toInt() + 200, notification)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // ── Video Trimming via MediaExtractor & MediaMuxer ─────────────────────
    private fun handleTrimVideo(call: MethodCall, result: Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val startMs = (call.argument<Number>("startMs")?.toLong() ?: 0L).coerceAtLeast(0L)
        val endMs = (call.argument<Number>("endMs")?.toLong() ?: 0L)

        if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "inputPath and outputPath are required", null)
            return
        }

        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            result.error("FILE_NOT_FOUND", "Source video not found: $inputPath", null)
            return
        }

        Thread {
            try {
                val success = trimVideoFile(inputPath, outputPath, startMs, endMs)
                if (success) {
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(outputPath), arrayOf("video/mp4"), null)
                }
                runOnUiThread {
                    result.success(success)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("TRIM_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun trimVideoFile(inputPath: String, outputPath: String, startMs: Long, endMs: Long): Boolean {
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null

        try {
            val startUs = startMs * 1000L
            val endUs = if (endMs > startMs) endMs * 1000L else Long.MAX_VALUE

            var rotation = 0
            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(inputPath)
                val rotStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                rotation = rotStr?.toIntOrNull() ?: 0
                retriever.release()
            } catch (_: Exception) {}

            videoExtractor = MediaExtractor().apply { setDataSource(inputPath) }
            audioExtractor = MediaExtractor().apply { setDataSource(inputPath) }

            var videoTrackIndex = -1
            var audioTrackIndex = -1

            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/") && videoTrackIndex < 0) {
                    videoTrackIndex = i
                } else if (mime.startsWith("audio/") && audioTrackIndex < 0) {
                    audioTrackIndex = i
                }
            }

            if (videoTrackIndex < 0) {
                return false
            }

            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()
            if (outFile.exists()) {
                outFile.delete()
            }

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer.setOrientationHint(rotation)

            videoExtractor.selectTrack(videoTrackIndex)
            val videoFormat = videoExtractor.getTrackFormat(videoTrackIndex)
            val muxerVideoTrack = muxer.addTrack(videoFormat)

            var muxerAudioTrack = -1
            if (audioTrackIndex >= 0) {
                audioExtractor.selectTrack(audioTrackIndex)
                val audioFormat = audioExtractor.getTrackFormat(audioTrackIndex)
                muxerAudioTrack = muxer.addTrack(audioFormat)
            }

            muxer.start()

            // Seek video track to startUs sync keyframe
            videoExtractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val bufferSize = 1024 * 1024 // 1MB buffer
            val buffer = ByteBuffer.allocateDirect(bufferSize)
            val bufferInfo = MediaCodec.BufferInfo()

            var firstVideoPts = -1L

            // Write video samples
            while (true) {
                bufferInfo.offset = 0
                bufferInfo.size = videoExtractor.readSampleData(buffer, 0)
                if (bufferInfo.size < 0) {
                    break
                }
                val sampleTime = videoExtractor.sampleTime
                if (sampleTime > endUs) {
                    break
                }
                if (firstVideoPts < 0) {
                    firstVideoPts = sampleTime
                }
                bufferInfo.presentationTimeUs = (sampleTime - firstVideoPts).coerceAtLeast(0L)
                bufferInfo.flags = videoExtractor.sampleFlags
                muxer.writeSampleData(muxerVideoTrack, buffer, bufferInfo)
                videoExtractor.advance()
            }

            // Write audio samples if present
            if (audioTrackIndex >= 0 && muxerAudioTrack >= 0) {
                audioExtractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                var firstAudioPts = -1L

                while (true) {
                    bufferInfo.offset = 0
                    bufferInfo.size = audioExtractor.readSampleData(buffer, 0)
                    if (bufferInfo.size < 0) {
                        break
                    }
                    val sampleTime = audioExtractor.sampleTime
                    if (sampleTime > endUs) {
                        break
                    }
                    if (firstAudioPts < 0) {
                        firstAudioPts = sampleTime
                    }
                    bufferInfo.presentationTimeUs = (sampleTime - firstAudioPts).coerceAtLeast(0L)
                    bufferInfo.flags = audioExtractor.sampleFlags
                    muxer.writeSampleData(muxerAudioTrack, buffer, bufferInfo)
                    audioExtractor.advance()
                }
            }

            try {
                muxer.stop()
            } catch (_: Exception) {}
            return true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to trim video: ${e.message}", e)
            return false
        } finally {
            try { videoExtractor?.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            if (resultCode == RESULT_OK && data != null) {
                MediaProjectionHolder.resultCode = resultCode
                MediaProjectionHolder.resultData = data
                pendingResult?.success(true)
            } else {
                pendingResult?.error("PERMISSION_DENIED", "User denied screen recording permission", null)
            }
            pendingResult = null
        }
    }
}