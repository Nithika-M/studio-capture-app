package com.example.studio_capture_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.MediaScannerConnection
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.os.StatFs
import android.os.Vibrator
import android.os.VibrationEffect
import android.os.VibratorManager
import android.provider.Settings
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Matrix
import android.graphics.Outline
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class ScreenRecordingService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var audioCaptureEngine: AudioCaptureEngine? = null
    private var isRecording = false
    var isPaused = false
    @set:JvmName("setIsAudioMuted")
    var isAudioMuted = false
    @set:JvmName("setIsVideoEnabled")
    var isVideoEnabled = true
    private var tempVideoFile: File? = null
    private var tempAudioFile: File? = null
    private var outputFile: File? = null
    private val isRecordingFlag = AtomicBoolean(false)

    private var recordingWidth = 1080
    private var recordingHeight = 1920
    private var recordingStartTime = 0L

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var pauseButtonView: ImageView? = null
    private var muteButtonView: ImageView? = null
    private var videoButtonView: ImageView? = null

    // Live Facecam PiP Overlay
    private var facecamView: View? = null
    private var facecamTextureView: TextureView? = null
    private var facecamCameraDevice: CameraDevice? = null
    private var facecamCaptureSession: CameraCaptureSession? = null
    private var facecamThread: HandlerThread? = null
    private var facecamHandler: Handler? = null
    private var facecamPreviewSize: Size? = null
    private var facecamSensorOrientation = 270
    private var isFacecamFront = true
    private var isFacecamRunning = false
    private var currentFacecamShape = "Square (PiP)"
    private var showFacecamSetting = false

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var acceleration = 0f
    private var currentAcceleration = 0f
    private var lastAcceleration = 0f

    private var previousShowTouchesState: Int = -1
    private var showFloatingNotification: Boolean = true
    private var vibrationFeedbackEnabled: Boolean = true

    private fun performHapticFeedback(durationMs: Long = 100) {
        if (!vibrationFeedbackEnabled) return
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator ?: (@Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs)
            }
        } catch (_: Exception) {}
    }

    // CRITICAL FIX: Register MediaProjection.Callback immediately after obtaining the token.
    // Without it, Android 14+ revokes "Entire Screen" projections after ~2 seconds.
    private val mediaProjectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.w("ScreenRecording", "MediaProjection.onStop() - projection revoked by system")
            if (isRecordingFlag.get()) {
                Handler(Looper.getMainLooper()).post {
                    stopRecording()
                    stopSelf()
                }
            }
        }
    }

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]
            lastAcceleration = currentAcceleration
            currentAcceleration = kotlin.math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()
            val delta = currentAcceleration - lastAcceleration
            acceleration = acceleration * 0.9f + delta

            if (acceleration > 11.5f) {
                // Physical shake detected reliably
                Log.d("ScreenRecording", "Physical shake detected, stopping recording")
                stopRecording()
                stopSelf()
            }
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    companion object {
        const val CHANNEL_ID = "channel_recording"
        const val CHANNEL_ID_MINIMAL = "channel_recording_minimal"
        const val CHANNEL_EXPORT_TRIM = "channel_export_trim"
        const val CHANNEL_STORAGE = "channel_storage"
        const val CHANNEL_CLOUD_BACKUP = "channel_cloud_backup"
        const val NOTIFICATION_ID = 1001
        const val NOTIFICATION_ID_SAVED = 1002
        const val NOTIFICATION_ID_STORAGE = 1003
        const val ACTION_START = "start"
        const val ACTION_PAUSE = "pause"
        const val ACTION_RESUME = "resume"
        const val ACTION_STOP = "stop"
        var isRecording = false
        var lastRecordingPath: String? = null
        var currentInstance: ScreenRecordingService? = null
    }

    override fun onCreate() {
        super.onCreate()
        currentInstance = this
        createNotificationChannel()
        val filter = IntentFilter().apply {
            addAction("screen_recording_action")
            addAction("pause")
            addAction("resume")
            addAction("stop")
            addAction("setVideoEnabled")
            addAction("setAudioMuted")
            addAction("setFacecamEnabled")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(broadcastReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(broadcastReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_STICKY

        val action = intent.getStringExtra("action") ?: intent.action ?: ACTION_START

        when (action) {
            ACTION_START -> {
                createNotificationChannel()
                val notification = createNotification("Screen Recorder", "Recording in progress...")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                        if (intent.getBooleanExtra("showFacecam", false)) {
                            serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                        }
                    }
                    startForeground(NOTIFICATION_ID, notification, serviceType)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }

                if (!isRecordingFlag.get()) {
                    if (this.mediaProjection == null) {
                        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? android.media.projection.MediaProjectionManager
                        val resultCode = intent.getIntExtra("resultCode", android.app.Activity.RESULT_OK)
                        val resultData: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra("resultData", Intent::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra("resultData")
                        } ?: MediaProjectionHolder.resultData

                        if (resultData != null && mpManager != null) {
                            try {
                                this.mediaProjection = mpManager.getMediaProjection(resultCode, resultData)
                                // CRITICAL: Register callback immediately to keep Entire Screen alive on Android 14+
                                this.mediaProjection?.registerCallback(
                                    mediaProjectionCallback,
                                    Handler(Looper.getMainLooper())
                                )
                                MediaProjectionHolder.mediaProjection = this.mediaProjection
                                Log.d("ScreenRecording", "MediaProjection created + callback registered")
                            } catch (e: Exception) {
                                Log.e("ScreenRecording", "Error obtaining MediaProjection: ${e.message}", e)
                            }
                        } else if (MediaProjectionHolder.mediaProjection != null) {
                            this.mediaProjection = MediaProjectionHolder.mediaProjection
                            try {
                                this.mediaProjection?.registerCallback(
                                    mediaProjectionCallback,
                                    Handler(Looper.getMainLooper())
                                )
                            } catch (e: Exception) {
                                Log.w("ScreenRecording", "Callback re-register: ${e.message}")
                            }
                        }
                    }

                    startRecording(intent)
                }
            }
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> {
                stopRecording()
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun startRecording(intent: Intent) {
        if (isRecordingFlag.getAndSet(true)) return

        if (this.mediaProjection == null) {
            this.mediaProjection = MediaProjectionHolder.mediaProjection
        }

        if (this.mediaProjection == null) {
            Log.e("ScreenRecording", "MediaProjection is null")
            isRecordingFlag.set(false)
            ScreenRecordingService.isRecording = false
            stopForeground(true)
            stopSelf()
            return
        }

        isRecording = true
        isPaused = false
        isAudioMuted = false
        isVideoEnabled = intent.getBooleanExtra("enableVideo", true)
        ScreenRecordingService.isRecording = true

        createOutputFile()
        setupMediaRecorder(intent)

        val audioSource = intent.getStringExtra("audioSource") ?: "Internal + Mic"
        val enableAudio = intent.getBooleanExtra("enableAudio", true)
        showFloatingNotification = intent.getBooleanExtra("floatingNotification", true)
        lowStorageWarningEnabled = intent.getBooleanExtra("lowStorageWarning", true)
        vibrationFeedbackEnabled = intent.getBooleanExtra("vibrationFeedback", true)
        hasShownStorageWarning = false
        showFacecamSetting = intent.getBooleanExtra("showFacecam", false)
        currentFacecamShape = intent.getStringExtra("facecamShape") ?: "Square (PiP)"

        performHapticFeedback(140)
        checkStorageAvailable()
        startStorageMonitor()

        if (enableAudio && audioSource != "Mute/None" && tempAudioFile != null) {
            try {
                audioCaptureEngine = AudioCaptureEngine(mediaProjection, audioSource, tempAudioFile!!)
                audioCaptureEngine?.start()
                Log.d("ScreenRecording", "AudioCaptureEngine started with source: $audioSource")
            } catch (e: Exception) {
                Log.e("ScreenRecording", "Failed to start AudioCaptureEngine: ${e.message}", e)
            }
        }

        if (intent.getBooleanExtra("shakeToStop", false)) {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            accelerometer?.let {
                sensorManager?.registerListener(sensorListener, it, SensorManager.SENSOR_DELAY_NORMAL)
                acceleration = 10f
                currentAcceleration = SensorManager.GRAVITY_EARTH
                lastAcceleration = SensorManager.GRAVITY_EARTH
            }
        }

        if (intent.getBooleanExtra("showTouches", false)) {
            try {
                previousShowTouchesState = Settings.System.getInt(contentResolver, "show_touches", 0)
                Settings.System.putInt(contentResolver, "show_touches", 1)
            } catch (e: Exception) {
                Log.e("ScreenRecording", "Failed to enable show touches (requires WRITE_SECURE_SETTINGS): ${e.message}")
            }
        }

        try {
            recordingStartTime = System.currentTimeMillis()
            val notification = createNotification("Recording in progress", "Tap to return to app")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    if (showFacecamSetting) {
                        serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                    }
                }
                startForeground(NOTIFICATION_ID, notification, serviceType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            mediaRecorder?.prepare()
            mediaRecorder?.start()
            isRecording = true

            val displayMetrics = DisplayMetrics()
            val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val defaultDisplay = displayManager.getDisplay(0)
            defaultDisplay?.getRealMetrics(displayMetrics)
            val displayDensity = displayMetrics.densityDpi

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenRecording",
                recordingWidth,
                recordingHeight,
                displayDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                if (isVideoEnabled) mediaRecorder?.surface else null,
                null,
                Handler(Looper.getMainLooper())
            )

            Log.d("ScreenRecording", "Recording started successfully")

            if (intent.getBooleanExtra("floatingBubble", false)) {
                Handler(Looper.getMainLooper()).post {
                    showFloatingBubble()
                }
            }

            // Live facecam is handled exclusively by Flutter's ActiveRecordingScreen (FacecamWindow),
            // which captures the real front camera feed directly onto the display recording.
            // Do not spawn a redundant native WindowManager overlay.

            notifyStateChanged()
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error starting recording", e)
            isRecordingFlag.set(false)
            ScreenRecordingService.isRecording = false
            stopSelf()
        }
    }

    fun pauseRecording() {
        if (isRecording && !isPaused) {
            try {
                mediaRecorder?.pause()
            } catch (e: Exception) {
                Log.e("ScreenRecording", "Error pausing MediaRecorder: ${e.message}")
            }
            audioCaptureEngine?.pause()
            isPaused = true
            performHapticFeedback(90)
            updateNotification("Recording Paused")
            updateBubbleUi()
            notifyStateChanged()
        }
    }

    fun resumeRecording() {
        if (isRecording && isPaused) {
            try {
                mediaRecorder?.resume()
            } catch (e: Exception) {
                Log.e("ScreenRecording", "Error resuming MediaRecorder: ${e.message}")
            }
            audioCaptureEngine?.resume()
            isPaused = false
            performHapticFeedback(90)
            updateNotification("Recording in progress")
            updateBubbleUi()
            notifyStateChanged()
        }
    }

    fun stopRecording(): String? {
        if (!isRecordingFlag.getAndSet(false)) {
            return lastRecordingPath
        }

        performHapticFeedback(180)
        isRecording = false
        isPaused = false
        ScreenRecordingService.isRecording = false

        // Unregister callback BEFORE stopping to avoid spurious onStop() re-entrancy
        try { mediaProjection?.unregisterCallback(mediaProjectionCallback) } catch (_: Exception) {}

        try {
            mediaRecorder?.stop()
            mediaRecorder?.reset()
            mediaRecorder?.release()
            mediaRecorder = null
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error stopping media recorder", e)
        }

        try {
            audioCaptureEngine?.stop()
            audioCaptureEngine = null
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error stopping audio capture engine", e)
        }

        val vid = tempVideoFile
        val aud = tempAudioFile
        val out = outputFile
        if (vid != null && out != null) {
            if (aud != null && aud.exists() && aud.length() > 0) {
                AudioCaptureEngine.muxVideoAndAudio(vid, aud, out)
            } else {
                vid.renameTo(out)
            }
            // Automatically save every finished recording into the phone's public gallery (MediaStore, Movies/Studio Capture)
            MainActivity.saveVideoToPublicGallery(applicationContext, out)
            // Set BEFORE stopSelf so MainActivity fallback path always sees it
            lastRecordingPath = out.absolutePath
        }

        sensorManager?.unregisterListener(sensorListener)

        if (previousShowTouchesState != -1) {
            try {
                Settings.System.putInt(contentResolver, "show_touches", previousShowTouchesState)
            } catch (_: Exception) {}
        }

        virtualDisplay?.release()
        virtualDisplay = null

        mediaProjection?.stop()
        mediaProjection = null
        MediaProjectionHolder.mediaProjection = null
        MediaProjectionHolder.resultData = null  // Force fresh permission on next session

        stopStorageMonitor()

        // Scan BEFORE stopSelf to prevent OS from killing us mid-scan
        outputFile?.let { file ->
            try {
                MediaScannerConnection.scanFile(
                    applicationContext,
                    arrayOf(file.absolutePath),
                    arrayOf("video/mp4"),
                    null
                )
            } catch (e: Exception) {
                Log.e("ScreenRecording", "MediaScanner error: ${e.message}")
            }

            if (file.exists() && file.length() > 0) {
                showRecordingSavedNotification(file)
            }
        }

        notifyStateChanged()

        stopForeground(true)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
        recordingStartTime = 0L

        Handler(Looper.getMainLooper()).post {
            removeFacecamOverlay()
            removeFloatingBubble()
        }

        // stopSelf last so all cleanup is committed before the process may exit
        stopSelf()
        Log.d("ScreenRecording", "Recording stopped. Output: $lastRecordingPath")
        return lastRecordingPath
    }

    private fun createOutputFile() {
        val dir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getExternalFilesDir(Environment.DIRECTORY_MOVIES)
        } else {
            File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Studio Capture")
        }

        dir?.mkdirs()

        val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        tempVideoFile = File(dir, "temp_vid_${timeStamp}.mp4")
        tempAudioFile = File(dir, "temp_aud_${timeStamp}.m4a")
        outputFile = File(dir, "SCR_${timeStamp}.mp4")
    }

    private fun setupMediaRecorder(intent: Intent) {
        val displayMetrics = DisplayMetrics()
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val defaultDisplay = displayManager.getDisplay(0)
        defaultDisplay?.getRealMetrics(displayMetrics)

        val screenW = displayMetrics.widthPixels
        val screenH = displayMetrics.heightPixels
        val deviceShort = kotlin.math.min(screenW, screenH)
        val deviceLong = kotlin.math.max(screenW, screenH)
        val aspectRatio = if (deviceShort > 0) deviceLong.toDouble() / deviceShort.toDouble() else (16.0 / 9.0)

        // Parse resolution from intent ("144p", "240p", "720p", "1080p", "1440p", "4K")
        val resolution = intent.getStringExtra("resolution") ?: "1080p"
        val targetShort = when (resolution) {
            "144p" -> 144
            "240p" -> 240
            "720p" -> 720
            "1080p" -> 1080
            "1440p" -> 1440
            "4K" -> 2160
            else -> 1080
        }
        var calcShort = (targetShort / 2) * 2
        var calcLong = ((calcShort * aspectRatio).toInt() / 2) * 2

        // Clamp max dimension to 3840 for 4K UHD compatibility with hardware AVC/H.264 encoders
        if (calcLong > 3840) {
            calcLong = 3840
            calcShort = ((calcLong / aspectRatio).toInt() / 2) * 2
        }

        // Parse orientation from intent ("Auto", "Portrait", "Landscape")
        val rawOrientation = intent.getStringExtra("orientation") ?: "Auto"
        val orientation = rawOrientation.split(" ").firstOrNull() ?: "Auto"
        val isPortrait = when (orientation) {
            "Portrait" -> true
            "Landscape" -> false
            else -> screenH >= screenW
        }

        if (isPortrait) {
            recordingWidth = calcShort
            recordingHeight = calcLong
        } else {
            recordingWidth = calcLong
            recordingHeight = calcShort
        }

        val fps = intent.getIntExtra("fps", 30)
        val bitrateMbps = intent.getFloatExtra("bitrate", 16f)
        val bitrateBps = (bitrateMbps * 1_000_000).toInt()

        Log.i("ScreenRecording", "Configuring MediaRecorder: resolution=$resolution (${recordingWidth}x${recordingHeight}), fps=$fps, bitrate=${bitrateMbps}Mbps (${bitrateBps}bps), orientation=$orientation")

        mediaRecorder = MediaRecorder()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mediaProjection?.let { _ ->
                mediaRecorder?.setVideoSource(MediaRecorder.VideoSource.SURFACE)
                mediaRecorder?.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                mediaRecorder?.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                mediaRecorder?.setVideoSize(recordingWidth, recordingHeight)
                mediaRecorder?.setVideoFrameRate(fps)
                try {
                    mediaRecorder?.setCaptureRate(fps.toDouble())
                } catch (e: Exception) {
                    Log.w("ScreenRecording", "setCaptureRate not supported or failed: ${e.message}")
                }
                mediaRecorder?.setVideoEncodingBitRate(bitrateBps)
                mediaRecorder?.setOrientationHint(0)

                tempVideoFile?.let { file ->
                    mediaRecorder?.setOutputFile(file.absolutePath)
                }
            }
        }
    }

    private var storageCheckHandler: Handler? = null
    private var lowStorageWarningEnabled = true
    private var hasShownStorageWarning = false

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Screen recording in progress"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)

            val minimalChannel = NotificationChannel(
                CHANNEL_ID_MINIMAL,
                "Recording (Minimal)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Minimal service notification when quick controls are disabled"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            manager.createNotificationChannel(minimalChannel)

            val exportTrimChannel = NotificationChannel(
                CHANNEL_EXPORT_TRIM,
                "Export & Trim",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Video trim and export completion alerts"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(exportTrimChannel)

            val storageChannel = NotificationChannel(
                CHANNEL_STORAGE,
                "Storage Warnings",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when available device storage drops below 1 GB"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(storageChannel)

            val cloudBackupChannel = NotificationChannel(
                CHANNEL_CLOUD_BACKUP,
                "Cloud Backup",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Google Drive cloud upload progress and sync alerts"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(cloudBackupChannel)
        }
    }

    private fun createNotification(title: String, content: String): Notification {
        val appIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("route", "/active-recording")
        }
        val appPendingIntent = PendingIntent.getActivity(
            this, 0, appIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val pauseResumeIntent = Intent("screen_recording_action").apply {
            action = if (isPaused) "resume" else "pause"
            putExtra("action", if (isPaused) "resume" else "pause")
            setPackage(packageName)
        }
        val pauseResumePendingIntent = PendingIntent.getBroadcast(
            this, 1, pauseResumeIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent("screen_recording_action").apply {
            action = "stop"
            putExtra("action", "stop")
            setPackage(packageName)
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, 2, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val targetChannelId = if (showFloatingNotification) CHANNEL_ID else CHANNEL_ID_MINIMAL
        val iconRes = resources.getIdentifier("ic_stat_recording", "drawable", packageName).let {
            if (it != 0) it else android.R.drawable.ic_media_play
        }

        val displayTitle = if (!showFloatingNotification) {
            "Recording in progress"
        } else if (isPaused) {
            "Recording paused"
        } else {
            "Recording in progress"
        }

        val displayContent = if (!showFloatingNotification) {
            "Studio Capture is recording in background"
        } else if (isPaused) {
            "Recording paused • Tap to resume"
        } else {
            "Tap to open active recording screen"
        }

        val builder = NotificationCompat.Builder(this, targetChannelId)
            .setContentTitle(displayTitle)
            .setContentText(displayContent)
            .setSmallIcon(iconRes)
            .setColor(0xFF6366F1.toInt())
            .setContentIntent(appPendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(if (showFloatingNotification) NotificationCompat.VISIBILITY_PUBLIC else NotificationCompat.VISIBILITY_SECRET)
            .setAutoCancel(false)

        if (showFloatingNotification) {
            if (recordingStartTime > 0L && !isPaused) {
                builder.setUsesChronometer(true)
                builder.setWhen(recordingStartTime)
            } else {
                builder.setUsesChronometer(false)
            }

            builder.addAction(
                if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                if (isPaused) "Resume" else "Pause",
                pauseResumePendingIntent
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
        } else {
            builder.setUsesChronometer(false)
        }

        return builder.build()
    }

    private fun updateNotification(title: String) {
        val content = if (isPaused) "Recording paused • Tap to resume" else "Tap to open active recording screen"
        val notification = createNotification(title, content)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun showRecordingSavedNotification(savedFile: File) {
        try {
            val appIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("route", "/recording-completed")
                putExtra("filePath", savedFile.absolutePath)
                putExtra("savedPath", savedFile.absolutePath)
            }
            val appPendingIntent = PendingIntent.getActivity(
                this, NOTIFICATION_ID_SAVED, appIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val iconRes = resources.getIdentifier("ic_stat_recording", "drawable", packageName).let {
                if (it != 0) it else android.R.drawable.stat_sys_download_done
            }
            val notification = NotificationCompat.Builder(this, CHANNEL_EXPORT_TRIM)
                .setSmallIcon(iconRes)
                .setColor(0xFF6366F1.toInt())
                .setContentTitle("Recording saved")
                .setContentText("Tap to review and edit your recording")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(appPendingIntent)
                .setAutoCancel(true)
                .build()
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID_SAVED, notification)
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Failed to show recording saved notification: ${e.message}")
        }
    }

    private fun startStorageMonitor() {
        storageCheckHandler = Handler(Looper.getMainLooper())
        val checkRunnable = object : Runnable {
            override fun run() {
                if (isRecordingFlag.get()) {
                    checkStorageAvailable()
                    storageCheckHandler?.postDelayed(this, 15000L)
                }
            }
        }
        storageCheckHandler?.postDelayed(checkRunnable, 3000L)
    }

    private fun stopStorageMonitor() {
        storageCheckHandler?.removeCallbacksAndMessages(null)
        storageCheckHandler = null
    }

    private fun checkStorageAvailable() {
        try {
            val checkDir = outputFile?.parentFile ?: getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir
            val stat = StatFs(checkDir.absolutePath)
            val availableBytes = stat.availableBytes
            val oneGb = 1024L * 1024L * 1024L
            val criticalLimit = 200L * 1024L * 1024L

            if (availableBytes < criticalLimit) {
                Log.e("ScreenRecording", "Storage critically low ($availableBytes bytes). Safe stop triggered.")
                showStorageNotification(
                    "Storage Critically Low",
                    "Recording stopped automatically and saved to prevent data loss."
                )
                Handler(Looper.getMainLooper()).post {
                    stopRecording()
                    stopSelf()
                }
            } else if (availableBytes < oneGb && lowStorageWarningEnabled && !hasShownStorageWarning) {
                hasShownStorageWarning = true
                val remainingMb = availableBytes / (1024L * 1024L)
                Log.w("ScreenRecording", "Low storage warning: $remainingMb MB remaining")
                showStorageNotification(
                    "Low Storage Warning",
                    "Less than 1 GB storage remaining ($remainingMb MB). Free up space soon."
                )
            }
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error checking storage: ${e.message}")
        }
    }

    private fun showStorageNotification(title: String, message: String) {
        if (!lowStorageWarningEnabled) return
        try {
            val appIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val appPendingIntent = PendingIntent.getActivity(
                this, NOTIFICATION_ID_STORAGE, appIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val iconRes = resources.getIdentifier("ic_stat_recording", "drawable", packageName).let {
                if (it != 0) it else android.R.drawable.stat_sys_warning
            }
            val notif = NotificationCompat.Builder(this, CHANNEL_STORAGE)
                .setSmallIcon(iconRes)
                .setColor(0xFFF59E0B.toInt())
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(appPendingIntent)
                .setAutoCancel(true)
                .build()
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID_STORAGE, notif)
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Failed to show storage notification: ${e.message}")
        }
    }

    fun setVideoEnabled(enabled: Boolean) {
        isVideoEnabled = enabled
        try {
            if (enabled) {
                virtualDisplay?.surface = mediaRecorder?.surface
            } else {
                virtualDisplay?.surface = null
            }
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error setting video surface: ${e.message}")
        }
        updateBubbleUi()
        notifyStateChanged()
    }

    fun setAudioMuted(muted: Boolean) {
        isAudioMuted = muted
        audioCaptureEngine?.setMuted(muted)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
        try {
            audioManager?.isMicrophoneMute = muted
        } catch (_: Exception) {}
        updateBubbleUi()
        notifyStateChanged()
    }

    fun notifyStateChanged() {
        val intent = Intent("screen_recording_state_changed").apply {
            putExtra("isRecording", isRecording)
            putExtra("isPaused", isPaused)
            putExtra("isAudioMuted", isAudioMuted)
            putExtra("isVideoEnabled", isVideoEnabled)
            putExtra("showFacecam", showFacecamSetting)
            putExtra("facecamShape", currentFacecamShape)
            putExtra("lastRecordingPath", lastRecordingPath)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    fun updateBubbleUi() {
        Handler(Looper.getMainLooper()).post {
            pauseButtonView?.let { btn ->
                if (isPaused) {
                    btn.setImageResource(R.drawable.ic_rec_play)
                    btn.setColorFilter(Color.parseColor("#F59E0B"))
                } else {
                    btn.setImageResource(R.drawable.ic_rec_pause)
                    btn.setColorFilter(Color.WHITE)
                }
            }
            muteButtonView?.let { btn ->
                if (isAudioMuted) {
                    btn.setImageResource(R.drawable.ic_mic_off)
                    btn.setColorFilter(Color.parseColor("#EF4444"))
                } else {
                    btn.setImageResource(R.drawable.ic_mic_on)
                    btn.setColorFilter(Color.WHITE)
                }
            }
            videoButtonView?.let { btn ->
                if (isVideoEnabled) {
                    btn.setImageResource(R.drawable.ic_video_on)
                    btn.setColorFilter(Color.WHITE)
                } else {
                    btn.setImageResource(R.drawable.ic_video_off)
                    btn.setColorFilter(Color.parseColor("#EF4444"))
                }
            }
        }
    }

    private val broadcastReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: intent?.getStringExtra("action") ?: return
            when (action) {
                "pause" -> pauseRecording()
                "resume" -> resumeRecording()
                "stop" -> stopRecording()
                "setVideoEnabled" -> {
                    val enabled = intent?.getBooleanExtra("enabled", true) ?: true
                    setVideoEnabled(enabled)
                }
                "setAudioMuted" -> {
                    val muted = intent?.getBooleanExtra("muted", false) ?: false
                    setAudioMuted(muted)
                }
                "setFacecamEnabled" -> {
                    val enabled = intent?.getBooleanExtra("enabled", true) ?: true
                    val shape = intent?.getStringExtra("facecamShape") ?: currentFacecamShape
                    setFacecamEnabled(enabled, shape)
                }
            }
        }
    }

    private fun showFloatingBubble() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w("ScreenRecording", "Cannot show floating bubble: SYSTEM_ALERT_WINDOW permission not granted")
            return
        }

        try {
            if (floatingView != null) return
            windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 40
                y = 300
            }

            val density = resources.displayMetrics.density
            fun dp(value: Float): Int = (value * density + 0.5f).toInt()

            val root = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(10f), dp(6f), dp(10f), dp(6f))

                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(24f).toFloat()
                    setColor(Color.parseColor("#EE111827"))
                    setStroke(dp(1f), Color.parseColor("#4B5563"))
                }
                background = bg
                elevation = dp(8f).toFloat()
            }

            val recBadge = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4f), dp(4f), dp(8f), dp(4f))
            }
            val redDot = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(10f), dp(10f))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#EF4444"))
                }
            }
            recBadge.addView(redDot)

            val recText = TextView(this).apply {
                text = "REC"
                setTextColor(Color.WHITE)
                textSize = 11f
                typeface = Typeface.DEFAULT_BOLD
                setPadding(dp(5f), 0, 0, 0)
            }
            recBadge.addView(recText)
            root.addView(recBadge)

            val divider1 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(1f), dp(18f)).apply {
                    setMargins(dp(2f), 0, dp(6f), 0)
                }
                setBackgroundColor(Color.parseColor("#4B5563"))
            }
            root.addView(divider1)

            fun createButton(iconRes: Int, onClick: (ImageView) -> Unit): ImageView {
                return ImageView(this).apply {
                    layoutParams = LinearLayout.LayoutParams(dp(42f), dp(42f))
                    setImageResource(iconRes)
                    setColorFilter(Color.WHITE)
                    scaleType = ImageView.ScaleType.CENTER_INSIDE
                    setPadding(dp(9f), dp(9f), dp(9f), dp(9f))
                    
                    val ripple = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(Color.parseColor("#1F2937"))
                    }
                    background = ripple

                    setOnClickListener { onClick(this) }
                }
            }

            pauseButtonView = createButton(if (isPaused) R.drawable.ic_rec_play else R.drawable.ic_rec_pause) { _ ->
                if (isPaused) {
                    resumeRecording()
                } else {
                    pauseRecording()
                }
            }
            root.addView(pauseButtonView)

            muteButtonView = createButton(if (isAudioMuted) R.drawable.ic_mic_off else R.drawable.ic_mic_on) { _ ->
                setAudioMuted(!isAudioMuted)
            }
            root.addView(muteButtonView)

            videoButtonView = createButton(if (isVideoEnabled) R.drawable.ic_video_on else R.drawable.ic_video_off) { _ ->
                setVideoEnabled(!isVideoEnabled)
            }
            root.addView(videoButtonView)

            val divider2 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(1f), dp(18f)).apply {
                    setMargins(dp(4f), 0, dp(6f), 0)
                }
                setBackgroundColor(Color.parseColor("#4B5563"))
            }
            root.addView(divider2)

            val stopButton = createButton(R.drawable.ic_rec_stop) { _ ->
                val finalPath = stopRecording()
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("route", "/recording-completed")
                    putExtra("savedPath", finalPath)
                }
                if (launchIntent != null) {
                    startActivity(launchIntent)
                }
            }.apply {
                setColorFilter(Color.parseColor("#EF4444"))
                val redBg = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#371B1B"))
                }
                background = redBg
            }
            root.addView(stopButton)

            updateBubbleUi()

            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f

            recBadge.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        params.x = initialX + dx.toInt()
                        params.y = initialY + dy.toInt()
                        windowManager?.updateViewLayout(root, params)
                        true
                    }
                    else -> false
                }
            }

            floatingView = root
            windowManager?.addView(floatingView, params)
            Log.d("ScreenRecording", "Floating bubble added to window manager")
        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error showing floating bubble: ${e.message}", e)
        }
    }

    private fun removeFloatingBubble() {
        floatingView?.let { view ->
            try {
                windowManager?.removeView(view)
                floatingView = null
                pauseButtonView = null
                muteButtonView = null
                videoButtonView = null
                Log.d("ScreenRecording", "Floating bubble removed from window manager")
            } catch (e: Exception) {
                Log.e("ScreenRecording", "Error removing floating bubble: ${e.message}")
            }
        }
    }

    fun setFacecamEnabled(enabled: Boolean, shape: String? = null) {
        showFacecamSetting = enabled
        if (shape != null) {
            currentFacecamShape = shape
        }
        Handler(Looper.getMainLooper()).post {
            removeFacecamOverlay()
        }
        notifyStateChanged()
    }

    private fun showFacecamOverlay(shape: String = "Square (PiP)") {
        // Redundant overlay completely removed to prevent duplicate/empty "LIVE" boxes.
        // Flutter's FacecamWindow displays the actual live camera feed.
        removeFacecamOverlay()
    }


    private fun startFacecamCamera(surfaceTexture: SurfaceTexture, viewWidth: Int, viewHeight: Int) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            Log.w("ScreenRecording", "Cannot start facecam camera: CAMERA permission not granted")
            return
        }

        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
            var selectedCameraId: String? = null
            var selectedCharacteristics: CameraCharacteristics? = null

            for (id in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                    selectedCameraId = id
                    selectedCharacteristics = chars
                    isFacecamFront = true
                    break
                }
            }

            if (selectedCameraId == null && cameraManager.cameraIdList.isNotEmpty()) {
                selectedCameraId = cameraManager.cameraIdList[0]
                selectedCharacteristics = cameraManager.getCameraCharacteristics(selectedCameraId)
                isFacecamFront = false
            }

            if (selectedCameraId == null || selectedCharacteristics == null) {
                Log.e("ScreenRecording", "No camera available for facecam")
                return
            }

            facecamSensorOrientation = selectedCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 270

            val map = selectedCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val outputSizes = map?.getOutputSizes(SurfaceTexture::class.java) ?: emptyArray()

            val chosenSize = outputSizes.firstOrNull { it.width == 640 && it.height == 480 }
                ?: outputSizes.firstOrNull { it.width == 480 && it.height == 640 }
                ?: outputSizes.firstOrNull { it.width <= 1280 && it.height <= 720 && it.width >= 480 }
                ?: outputSizes.firstOrNull() ?: Size(640, 480)

            facecamPreviewSize = chosenSize
            surfaceTexture.setDefaultBufferSize(chosenSize.width, chosenSize.height)

            adjustFacecamTransform(viewWidth, viewHeight)

            facecamThread = HandlerThread("FacecamCameraThread").apply { start() }
            val handler = Handler(facecamThread!!.looper)
            facecamHandler = handler

            cameraManager.openCamera(selectedCameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    facecamCameraDevice = camera
                    try {
                        val surface = Surface(surfaceTexture)
                        val captureRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(surface)
                            set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                        }

                        camera.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                            override fun onConfigured(session: CameraCaptureSession) {
                                if (facecamCameraDevice == null) return
                                facecamCaptureSession = session
                                try {
                                    session.setRepeatingRequest(captureRequestBuilder.build(), null, handler)
                                    isFacecamRunning = true
                                    Log.d("ScreenRecording", "Facecam camera preview running smoothly")
                                } catch (e: Exception) {
                                    Log.e("ScreenRecording", "Error starting repeating facecam request: ${e.message}")
                                }
                            }

                            override fun onConfigureFailed(session: CameraCaptureSession) {
                                Log.e("ScreenRecording", "Facecam capture session configuration failed")
                            }
                        }, handler)
                    } catch (e: Exception) {
                        Log.e("ScreenRecording", "Error creating facecam preview session: ${e.message}", e)
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    facecamCameraDevice = null
                    isFacecamRunning = false
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e("ScreenRecording", "Facecam camera open error: $error")
                    camera.close()
                    facecamCameraDevice = null
                    isFacecamRunning = false
                }
            }, handler)

        } catch (e: Exception) {
            Log.e("ScreenRecording", "Error opening facecam camera: ${e.message}", e)
        }
    }

    private fun adjustFacecamTransform(viewWidth: Int, viewHeight: Int) {
        val texture = facecamTextureView ?: return
        val previewSize = facecamPreviewSize ?: return
        if (viewWidth <= 0 || viewHeight <= 0) return

        val matrix = Matrix()
        val cx = viewWidth / 2f
        val cy = viewHeight / 2f

        val displayRotation = (getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        val deviceDegrees = when (displayRotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }

        // Standard Camera2 rotation formula
        val sensorDegrees = facecamSensorOrientation
        val degreesToRotate = if (isFacecamFront) {
            (sensorDegrees + deviceDegrees) % 360
        } else {
            (sensorDegrees - deviceDegrees + 360) % 360
        }

        matrix.postRotate(degreesToRotate.toFloat(), cx, cy)

        // Determine orientation after rotation to calculate correct aspect scale without distortion
        val isRotatedSideways = (degreesToRotate == 90 || degreesToRotate == 270)
        val rotatedBufferWidth = if (isRotatedSideways) previewSize.height else previewSize.width
        val rotatedBufferHeight = if (isRotatedSideways) previewSize.width else previewSize.height

        val scaleX = viewWidth.toFloat() / rotatedBufferWidth.toFloat()
        val scaleY = viewHeight.toFloat() / rotatedBufferHeight.toFloat()
        val maxScale = maxOf(scaleX, scaleY)

        matrix.postScale(
            maxScale * (rotatedBufferWidth.toFloat() / viewWidth.toFloat()),
            maxScale * (rotatedBufferHeight.toFloat() / viewHeight.toFloat()),
            cx,
            cy
        )

        // Mirror front camera horizontally for natural mirror selfie view
        if (isFacecamFront) {
            matrix.postScale(-1f, 1f, cx, cy)
        }

        texture.setTransform(matrix)
    }

    private fun stopFacecamCamera() {
        try {
            facecamCaptureSession?.stopRepeating()
            facecamCaptureSession?.close()
        } catch (_: Exception) {}
        facecamCaptureSession = null

        try {
            facecamCameraDevice?.close()
        } catch (_: Exception) {}
        facecamCameraDevice = null

        try {
            facecamThread?.quitSafely()
            facecamThread?.join(500)
        } catch (_: Exception) {}
        facecamThread = null
        facecamHandler = null
        isFacecamRunning = false
    }

    private fun removeFacecamOverlay() {
        stopFacecamCamera()
        facecamView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {}
        }
        facecamView = null
        facecamTextureView = null
    }

    override fun onDestroy() {
        if (currentInstance === this) {
            currentInstance = null
        }
        stopStorageMonitor()
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
        Handler(Looper.getMainLooper()).post {
            removeFacecamOverlay()
            removeFloatingBubble()
        }
        try {
            unregisterReceiver(broadcastReceiver)
        } catch (_: Exception) {}
        stopRecording()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (!isRecordingFlag.get()) {
            try {
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.cancel(NOTIFICATION_ID)
            } catch (_: Exception) {}
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}