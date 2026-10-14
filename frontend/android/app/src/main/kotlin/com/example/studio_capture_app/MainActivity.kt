package com.example.studio_capture_app

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
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ActivityCompat
import android.Manifest
import android.provider.Settings
import android.app.Notification
import android.app.PendingIntent
import android.app.NotificationManager
import android.app.NotificationChannel
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.security.MessageDigest
import android.content.pm.PackageManager
import android.accounts.AccountManager
import android.accounts.Account
import android.media.MediaCodecInfo

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "screen_recording"
    private var methodChannel: MethodChannel? = null
    private var pendingResult: Result? = null
    private var pendingNotificationPermissionResult: Result? = null
    private val REQUEST_POST_NOTIFICATIONS = 1002
    private var initialRouteInfo: Map<String, String?>? = null

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
                "openGooglePhotos" -> handleOpenGooglePhotos(result)
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
                "cancelNotification" -> handleCancelNotification(call, result)
                "areNotificationsEnabled" -> handleAreNotificationsEnabled(result)
                "openNotificationSettings" -> handleOpenNotificationSettings(result)
                "requestNotificationPermission" -> handleRequestNotificationPermission(result)
                "getInitialRoute" -> result.success(initialRouteInfo)
                "trimVideo" -> handleTrimVideo(call, result)
                "transcodeVideo" -> handleTranscodeVideo(call, result)
                "enableAutoSync" -> result.success(true)
                "disableAutoSync" -> result.success(true)
                "syncRecordingNow" -> result.success(true)
                "isAutoSyncEnabled" -> result.success(false)
                "isWifiConnected" -> {
                    try {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                        val isWifi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val network = cm?.activeNetwork
                            val capabilities = cm?.getNetworkCapabilities(network)
                            capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                        } else {
                            @Suppress("DEPRECATION")
                            cm?.activeNetworkInfo?.type == ConnectivityManager.TYPE_WIFI
                        }
                        result.success(isWifi)
                    } catch (_: Exception) {
                        result.success(true)
                    }
                }
                "getAppBuildInfo" -> {
                    val sha1 = getAppSha1(applicationContext)
                    result.success(mapOf(
                        "packageName" to applicationContext.packageName,
                        "sha1" to sha1
                    ))
                }
                "pickDeviceAccount" -> handlePickDeviceAccount(result)
                "getDeviceAccounts" -> handleGetDeviceAccounts(result)
                else -> result.notImplemented()
            }
        }
        methodChannel?.setMethodCallHandler(handler)
        secondChannel.setMethodCallHandler(handler)

        createAllNotificationChannels()

        if (initialRouteInfo != null) {
            Handler(Looper.getMainLooper()).postDelayed({
                initialRouteInfo?.let { methodChannel?.invokeMethod("onNavigateRoute", it) }
            }, 600)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val route = intent?.getStringExtra("route")
        val savedPath = intent?.getStringExtra("savedPath") ?: intent?.getStringExtra("filePath")
        if (route != null) {
            initialRouteInfo = mapOf("route" to route, "filePath" to savedPath, "savedPath" to savedPath)
        }
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
        val savedPath = intent.getStringExtra("savedPath") ?: intent.getStringExtra("filePath")
        if (route != null) {
            val routeMap = mapOf(
                "route" to route,
                "filePath" to savedPath,
                "savedPath" to savedPath
            )
            initialRouteInfo = routeMap
            methodChannel?.invokeMethod("onNavigateRoute", routeMap)
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
        val lowStorageWarning = config["lowStorageWarning"] as? Boolean ?: true
        val vibrationFeedback = config["vibrationFeedback"] as? Boolean ?: true

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
            putExtra("lowStorageWarning", lowStorageWarning)
            putExtra("vibrationFeedback", vibrationFeedback)
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

    companion object {
        fun saveVideoToPublicGallery(context: Context, sourceFile: File): Boolean {
            if (!sourceFile.exists()) return false

            var durationMs = 0L
            var videoWidth = 0
            var videoHeight = 0
            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(sourceFile.absolutePath)
                durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                videoWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                videoHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                retriever.release()
            } catch (_: Exception) {}

            val nowMs = System.currentTimeMillis()
            val fileSizeBytes = sourceFile.length()

            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val contentResolver = context.contentResolver
                    val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

                    // Check if already indexed with matching name and size to avoid duplicate entries
                    val projection = arrayOf(MediaStore.Video.Media._ID, MediaStore.Video.Media.SIZE)
                    val selection = "${MediaStore.Video.Media.DISPLAY_NAME} = ? AND ${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?"
                    val selectionArgs = arrayOf(sourceFile.name, "%Movies/Studio Capture%")
                    val cursor = contentResolver.query(collection, projection, selection, selectionArgs, null)
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val existingSize = it.getLong(it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE))
                            if (existingSize == fileSizeBytes) {
                                return true
                            }
                        }
                    }

                    val values = ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME, sourceFile.name)
                        put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                        put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Studio Capture")
                        put(MediaStore.Video.Media.DATE_TAKEN, nowMs)
                        put(MediaStore.Video.Media.DATE_MODIFIED, nowMs / 1000)
                        put(MediaStore.Video.Media.DATE_ADDED, nowMs / 1000)
                        if (durationMs > 0) put(MediaStore.Video.Media.DURATION, durationMs)
                        if (videoWidth > 0) put(MediaStore.Video.Media.WIDTH, videoWidth)
                        if (videoHeight > 0) put(MediaStore.Video.Media.HEIGHT, videoHeight)
                        put(MediaStore.Video.Media.SIZE, fileSizeBytes)
                        put(MediaStore.Video.Media.IS_PENDING, 1)
                    }

                    val uri = contentResolver.insert(collection, values)
                    if (uri != null) {
                        contentResolver.openOutputStream(uri)?.use { out ->
                            sourceFile.inputStream().use { input ->
                                input.copyTo(out)
                            }
                        }
                        values.clear()
                        values.put(MediaStore.Video.Media.IS_PENDING, 0)
                        contentResolver.update(uri, values, null, null)

                        // Scan public file path so Gallery and Google Photos index it immediately
                        val publicFile = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Studio Capture/${sourceFile.name}")
                        MediaScannerConnection.scanFile(
                            context.applicationContext,
                            arrayOf(publicFile.absolutePath, sourceFile.absolutePath),
                            arrayOf("video/mp4"),
                            null
                        )
                        true
                    } else {
                        false
                    }
                } else {
                    val publicDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Studio Capture")
                    publicDir.mkdirs()
                    val destFile = File(publicDir, sourceFile.name)
                    sourceFile.copyTo(destFile, overwrite = true)
                    MediaScannerConnection.scanFile(
                        context.applicationContext,
                        arrayOf(destFile.absolutePath),
                        arrayOf("video/mp4"),
                        null
                    )
                    true
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to save video to Studio Capture gallery: ${e.message}", e)
                false
            }
        }
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

        val success = saveVideoToPublicGallery(applicationContext, sourceFile)
        if (success) {
            result.success(true)
        } else {
            result.error("SAVE_FAILED", "Failed to save to gallery", null)
        }
    }

    private fun handleOpenGooglePhotos(result: Result) {
        val packageName = "com.google.android.apps.photos"
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                result.success(true)
            } else {
                try {
                    val storeIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("market://details?id=$packageName")).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(storeIntent)
                    result.success(true)
                } catch (e: Exception) {
                    val webIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://play.google.com/store/apps/details?id=$packageName")).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(webIntent)
                    result.success(true)
                }
            }
        } catch (e: Exception) {
            result.error("OPEN_FAILED", "Failed to open Google Photos: ${e.message}", null)
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
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Studio Capture")
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
                val picDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Studio Capture")
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

    private fun createAllNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val recordingChannel = NotificationChannel(
                "channel_recording",
                "Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Screen recording in progress"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val recordingMinimalChannel = NotificationChannel(
                "channel_recording_minimal",
                "Recording (Minimal)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Minimal service notification when quick controls are disabled"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }

            val exportTrimChannel = NotificationChannel(
                "channel_export_trim",
                "Export & Trim",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Video trim and export completion alerts"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val storageChannel = NotificationChannel(
                "channel_storage",
                "Storage Warnings",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when available device storage drops below 1 GB"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val cloudBackupChannel = NotificationChannel(
                "channel_cloud_backup",
                "Cloud Backup",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Google Drive cloud upload progress and sync alerts"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            manager.createNotificationChannels(listOf(
                recordingChannel,
                recordingMinimalChannel,
                exportTrimChannel,
                storageChannel,
                cloudBackupChannel
            ))
        }
    }

    private fun handleShowSystemNotification(call: MethodCall, result: Result) {
        val id = call.argument<Int>("id") ?: 1005
        val channelId = call.argument<String>("channelId") ?: "channel_export_trim"
        val title = call.argument<String>("title") ?: "Video Export"
        val message = call.argument<String>("message") ?: "Operation completed"
        val progress = call.argument<Int>("progress")
        val maxProgress = call.argument<Int>("maxProgress") ?: 100
        val ongoing = call.argument<Boolean>("ongoing") ?: false
        val filePath = call.argument<String>("filePath")

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val iconRes = resources.getIdentifier("ic_stat_recording", "drawable", packageName).let {
                if (it != 0) it else android.R.drawable.stat_sys_download_done
            }

            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(iconRes)
                .setColor(0xFF6366F1.toInt())
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setOngoing(ongoing)
                .setAutoCancel(!ongoing)

            if (channelId == "channel_storage") {
                builder.setPriority(NotificationCompat.PRIORITY_HIGH)
            } else if (channelId == "channel_cloud_backup") {
                builder.setPriority(NotificationCompat.PRIORITY_LOW)
            } else {
                builder.setPriority(NotificationCompat.PRIORITY_DEFAULT)
            }

            if (progress != null && progress >= 0) {
                builder.setProgress(maxProgress, progress, false)
            }

            if (filePath != null && filePath.isNotEmpty()) {
                val appIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("route", "/recording-completed")
                    putExtra("filePath", filePath)
                    putExtra("savedPath", filePath)
                }
                val pendingIntent = PendingIntent.getActivity(
                    this, id, appIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                builder.setContentIntent(pendingIntent)
            }

            notificationManager.notify(id, builder.build())
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleCancelNotification(call: MethodCall, result: Result) {
        val id = call.argument<Int>("id") ?: 1005
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(id)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleAreNotificationsEnabled(result: Result) {
        try {
            val manager = NotificationManagerCompat.from(this)
            result.success(manager.areNotificationsEnabled())
        } catch (e: Exception) {
            result.success(true)
        }
    }

    private fun handleOpenNotificationSettings(result: Result) {
        try {
            val intent = Intent()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                intent.action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                intent.action = "android.settings.APP_NOTIFICATION_SETTINGS"
                intent.putExtra("app_package", packageName)
                intent.putExtra("app_uid", applicationInfo.uid)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }

    private fun handleRequestNotificationPermission(result: Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
            } else {
                pendingNotificationPermissionResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_POST_NOTIFICATIONS
                )
            }
        } else {
            val manager = NotificationManagerCompat.from(this)
            result.success(manager.areNotificationsEnabled())
        }
    }

    // ── Video Transcoding via MediaCodec (Quick Export Profile) ────────────
    private fun handleTranscodeVideo(call: MethodCall, result: Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val targetWidth = call.argument<Int>("targetWidth") ?: 0
        val targetHeight = call.argument<Int>("targetHeight") ?: 0
        val targetBitrate = call.argument<Int>("targetBitrate") ?: 8000000
        val targetFps = call.argument<Int>("targetFps") ?: 30

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
                val success = transcodeVideoFile(inputPath, outputPath, targetWidth, targetHeight, targetBitrate, targetFps)
                if (success) {
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(outputPath), arrayOf("video/mp4"), null)
                }
                runOnUiThread {
                    result.success(success)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("TRANSCODE_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun transcodeVideoFile(
        inputPath: String,
        outputPath: String,
        targetWidth: Int,
        targetHeight: Int,
        targetBitrate: Int,
        targetFps: Int
    ): Boolean {
        var retriever: MediaMetadataRetriever? = null
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var inputSurface: android.view.Surface? = null

        try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(inputPath)
            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val origWidthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val origHeightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)

            val durationMs = durationStr?.toLongOrNull() ?: 1000L
            val totalDurationUs = durationMs * 1000L
            val origWidth = origWidthStr?.toIntOrNull() ?: 1080
            val origHeight = origHeightStr?.toIntOrNull() ?: 1920
            val rotation = rotationStr?.toIntOrNull() ?: 0

            // If target dimensions specified, maintain aspect ratio
            var outW = if (targetWidth > 0) targetWidth else origWidth
            var outH = if (targetHeight > 0) targetHeight else origHeight

            if (targetWidth > 0 && targetHeight <= 0) {
                outH = (targetWidth * origHeight) / origWidth
            } else if (targetHeight > 0 && targetWidth <= 0) {
                outW = (targetHeight * origWidth) / origHeight
            }

            // Align to multiple of 16 for H.264 hardware encoders
            outW = ((outW + 15) / 16) * 16
            outH = ((outH + 15) / 16) * 16
            if (outW <= 0) outW = 720
            if (outH <= 0) outH = 1280

            val fps = if (targetFps in 15..120) targetFps else 30
            val bitrate = if (targetBitrate in 500_000..50_000_000) targetBitrate else 8_000_000

            // 1. Setup extractors
            videoExtractor = MediaExtractor().apply { setDataSource(inputPath) }
            audioExtractor = MediaExtractor().apply { setDataSource(inputPath) }

            var videoTrackIndex = -1
            var audioTrackIndex = -1
            var videoFormat: MediaFormat? = null
            var audioFormat: MediaFormat? = null

            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/") && videoTrackIndex < 0) {
                    videoTrackIndex = i
                    videoFormat = format
                    videoExtractor.selectTrack(i)
                } else if (mime.startsWith("audio/") && audioTrackIndex < 0) {
                    audioTrackIndex = i
                    audioFormat = format
                    audioExtractor.selectTrack(i)
                }
            }

            if (videoTrackIndex < 0 || videoFormat == null) {
                return false
            }

            // 2. Setup encoder
            val encFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, outW, outH).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = encoder.createInputSurface()
            encoder.start()

            // 3. Setup decoder
            val decoderMime = videoFormat.getString(MediaFormat.KEY_MIME) ?: MediaFormat.MIMETYPE_VIDEO_AVC
            decoder = MediaCodec.createDecoderByType(decoderMime)
            decoder.configure(videoFormat, inputSurface, null, 0)
            decoder.start()

            // 4. Setup muxer
            val outputFile = File(outputPath)
            outputFile.parentFile?.mkdirs()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            if (rotation > 0) {
                muxer.setOrientationHint(rotation)
            }

            var muxerVideoTrack = -1
            var muxerAudioTrack = -1
            var muxerStarted = false

            if (audioTrackIndex >= 0 && audioFormat != null) {
                muxerAudioTrack = muxer.addTrack(audioFormat)
            }

            // 5. Transcoding loop
            val TIMEOUT_US = 5000L
            var sawInputEOS = false
            var sawDecoderEOS = false
            var sawEncoderEOS = false
            var lastProgressReportMs = 0L

            val decoderBufferInfo = MediaCodec.BufferInfo()
            val encoderBufferInfo = MediaCodec.BufferInfo()

            while (!sawEncoderEOS) {
                // Feed decoder
                if (!sawInputEOS) {
                    val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputIndex)
                        if (inputBuffer != null) {
                            val sampleSize = videoExtractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                sawInputEOS = true
                            } else {
                                val pts = videoExtractor.sampleTime
                                decoder.queueInputBuffer(inputIndex, 0, sampleSize, pts, 0)
                                videoExtractor.advance()
                            }
                        }
                    }
                }

                // Drain decoder
                if (!sawDecoderEOS) {
                    val decStatus = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                    if (decStatus >= 0) {
                        val isEOS = (decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        val doRender = decoderBufferInfo.size > 0
                        decoder.releaseOutputBuffer(decStatus, if (doRender) decoderBufferInfo.presentationTimeUs * 1000L else 0L)
                        if (isEOS) {
                            sawDecoderEOS = true
                            encoder.signalEndOfInputStream()
                        }
                    }
                }

                // Drain encoder
                val encStatus = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_US)
                if (encStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (muxerStarted) {
                        throw RuntimeException("Format changed after muxer started")
                    }
                    val newFormat = encoder.outputFormat
                    muxerVideoTrack = muxer.addTrack(newFormat)
                    muxer.start()
                    muxerStarted = true
                } else if (encStatus >= 0) {
                    val encodedBuffer = encoder.getOutputBuffer(encStatus)
                    if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        encoderBufferInfo.size = 0
                    }
                    if (encoderBufferInfo.size > 0 && muxerStarted && muxerVideoTrack >= 0) {
                        muxer.writeSampleData(muxerVideoTrack, encodedBuffer!!, encoderBufferInfo)

                        val nowMs = System.currentTimeMillis()
                        if (nowMs - lastProgressReportMs > 250 && totalDurationUs > 0) {
                            lastProgressReportMs = nowMs
                            val prog = (encoderBufferInfo.presentationTimeUs.toDouble() / totalDurationUs.toDouble()).coerceIn(0.0, 0.98)
                            runOnUiThread {
                                methodChannel?.invokeMethod("onTranscodeProgress", mapOf("progress" to prog))
                            }
                        }
                    }
                    if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        sawEncoderEOS = true
                    }
                    encoder.releaseOutputBuffer(encStatus, false)
                }
            }

            // 6. Copy audio track if present
            if (audioTrackIndex >= 0 && muxerAudioTrack >= 0 && muxerStarted) {
                audioExtractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                val audioBuf = ByteBuffer.allocateDirect(1024 * 1024)
                val audioBufInfo = MediaCodec.BufferInfo()
                while (true) {
                    val sampleSize = audioExtractor.readSampleData(audioBuf, 0)
                    if (sampleSize < 0) break
                    audioBufInfo.offset = 0
                    audioBufInfo.size = sampleSize
                    audioBufInfo.presentationTimeUs = audioExtractor.sampleTime
                    audioBufInfo.flags = audioExtractor.sampleFlags
                    muxer.writeSampleData(muxerAudioTrack, audioBuf, audioBufInfo)
                    audioExtractor.advance()
                }
            }

            runOnUiThread {
                methodChannel?.invokeMethod("onTranscodeProgress", mapOf("progress" to 1.0))
            }

            try {
                if (muxerStarted) {
                    muxer.stop()
                }
            } catch (_: Exception) {}

            return true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Transcode error: ${e.message}", e)
            try {
                if (File(outputPath).exists()) File(outputPath).delete()
                return trimVideoFile(inputPath, outputPath, 0L, 0L)
            } catch (_: Exception) {
                return false
            }
        } finally {
            try { retriever?.release() } catch (_: Exception) {}
            try { videoExtractor?.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
            try { decoder?.stop(); decoder?.release() } catch (_: Exception) {}
            try { encoder?.stop(); encoder?.release() } catch (_: Exception) {}
            try { inputSurface?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
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

    private fun getAppSha1(context: Context): String {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNATURES
                )
            }
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }
            val cert = signatures?.firstOrNull()?.toByteArray() ?: return "Unknown"
            val md = MessageDigest.getInstance("SHA-1")
            val digest = md.digest(cert)
            digest.joinToString(":") { "%02X".format(it) }
        } catch (e: Exception) {
            "Unavailable: ${e.message}"
        }
    }

    private var pickAccountResult: Result? = null
    private val REQUEST_CODE_PICK_ACCOUNT = 1002

    private fun handlePickDeviceAccount(result: Result) {
        try {
            pickAccountResult = result
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                AccountManager.newChooseAccountIntent(
                    null,
                    null,
                    arrayOf("com.google"),
                    null,
                    null,
                    null,
                    null
                )
            } else {
                @Suppress("DEPRECATION")
                AccountManager.newChooseAccountIntent(
                    null,
                    null,
                    arrayOf("com.google"),
                    false,
                    null,
                    null,
                    null,
                    null
                )
            }
            startActivityForResult(intent, REQUEST_CODE_PICK_ACCOUNT)
        } catch (e: Exception) {
            pickAccountResult = null
            result.error("ACCOUNT_PICKER_ERROR", e.message, null)
        }
    }

    private fun handleGetDeviceAccounts(result: Result) {
        try {
            val am = AccountManager.get(this)
            val list = mutableListOf<Map<String, String>>()
            
            // 1. Google accounts
            try {
                for (acc in am.getAccountsByType("com.google")) {
                    val email = acc.name
                    if (email.contains("@") && list.none { it["email"].equals(email, ignoreCase = true) }) {
                        val name = email.substringBefore("@")
                            .replace(".", " ")
                            .split(" ")
                            .joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
                        list.add(mapOf("email" to email, "name" to name))
                    }
                }
            } catch (_: Exception) {}

            // 2. All accounts on device
            try {
                for (acc in am.accounts) {
                    val email = acc.name
                    if (email.contains("@") && list.none { it["email"].equals(email, ignoreCase = true) }) {
                        val name = email.substringBefore("@")
                            .replace(".", " ")
                            .split(" ")
                            .joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
                        list.add(mapOf("email" to email, "name" to name))
                    }
                }
            } catch (_: Exception) {}

            result.success(list)
        } catch (e: Exception) {
            result.success(emptyList<Map<String, String>>())
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
        } else if (requestCode == REQUEST_CODE_PICK_ACCOUNT) {
            if (resultCode == RESULT_OK && data != null) {
                val accountName = data.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
                pickAccountResult?.success(accountName)
            } else {
                pickAccountResult?.success(null)
            }
            pickAccountResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
        }
    }
}