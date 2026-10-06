package com.example.screen_recording_app

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.os.Build
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Arrays
import java.util.concurrent.atomic.AtomicBoolean

/**
 * High-performance audio engine capable of capturing:
 * 1. Internal phone audio via AudioPlaybackCapture API (Android 10+)
 * 2. Microphone audio via AudioRecord
 * 3. Simultaneous internal + mic mixing with headroom control
 * 4. True zero-sample muting (true silence during muted period)
 * 5. Seamless pause/resume with timestamp continuity
 * 6. AAC hardware encoding to M4A and remuxing into final MP4
 */
class AudioCaptureEngine(
    private val mediaProjection: MediaProjection?,
    private val audioSource: String, // "Internal Audio only", "Microphone only", "Internal + Mic", "Mute/None"
    private val audioOutputFile: File
) {
    private val isRunning = AtomicBoolean(false)
    private val isPaused = AtomicBoolean(false)
    private val isMuted = AtomicBoolean(false)

    private var internalAudioRecord: AudioRecord? = null
    private var micAudioRecord: AudioRecord? = null
    private var audioThread: Thread? = null

    private var mediaCodec: MediaCodec? = null
    private var mediaMuxer: MediaMuxer? = null
    private var audioTrackIndex = -1
    private var isMuxerStarted = false

    private val sampleRate = 44100
    private val channelConfig = AudioFormat.CHANNEL_IN_STEREO
    private val channelCount = 2
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val bitrate = 192000

    private var pauseOffsetUs = 0L
    private var pauseStartUs = 0L

    companion object {
        private const val TAG = "AudioCaptureEngine"

        /**
         * Remuxes a video-only MP4 file and an AAC M4A audio file into a single complete MP4.
         */
        fun muxVideoAndAudio(videoFile: File, audioFile: File, finalOutputFile: File): Boolean {
            if (!videoFile.exists()) {
                Log.e(TAG, "Video file does not exist: ${videoFile.absolutePath}")
                return false
            }

            if (!audioFile.exists() || audioFile.length() == 0L) {
                // If audio file doesn't exist or is empty, just rename/copy video file
                Log.w(TAG, "Audio file missing or empty, keeping video-only MP4")
                return videoFile.renameTo(finalOutputFile)
            }

            var videoExtractor: MediaExtractor? = null
            var audioExtractor: MediaExtractor? = null
            var muxer: MediaMuxer? = null

            return try {
                videoExtractor = MediaExtractor().apply { setDataSource(videoFile.absolutePath) }
                audioExtractor = MediaExtractor().apply { setDataSource(audioFile.absolutePath) }

                muxer = MediaMuxer(finalOutputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

                var videoTrackIndex = -1
                for (i in 0 until videoExtractor.trackCount) {
                    val format = videoExtractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/")) {
                        videoExtractor.selectTrack(i)
                        videoTrackIndex = muxer.addTrack(format)
                        break
                    }
                }

                var audioTrackIndex = -1
                for (i in 0 until audioExtractor.trackCount) {
                    val format = audioExtractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        audioExtractor.selectTrack(i)
                        audioTrackIndex = muxer.addTrack(format)
                        break
                    }
                }

                if (videoTrackIndex == -1) {
                    Log.e(TAG, "No video track found in ${videoFile.absolutePath}")
                    return false
                }

                // Preserve original video orientation/rotation hint so playback is upright
                try {
                    val retriever = MediaMetadataRetriever()
                    retriever.setDataSource(videoFile.absolutePath)
                    val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    val rotation = rotationStr?.toIntOrNull() ?: 0
                    muxer.setOrientationHint(rotation)
                    retriever.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to read or preserve video rotation hint: ${e.message}")
                }

                muxer.start()

                val buffer = ByteBuffer.allocate(1024 * 1024)
                val bufferInfo = MediaCodec.BufferInfo()

                // Copy video samples
                while (true) {
                    val sampleSize = videoExtractor.readSampleData(buffer, 0)
                    if (sampleSize < 0) break
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = videoExtractor.sampleTime
                    bufferInfo.flags = videoExtractor.sampleFlags
                    muxer.writeSampleData(videoTrackIndex, buffer, bufferInfo)
                    videoExtractor.advance()
                }

                // Copy audio samples if audio track exists
                if (audioTrackIndex != -1) {
                    while (true) {
                        val sampleSize = audioExtractor.readSampleData(buffer, 0)
                        if (sampleSize < 0) break
                        bufferInfo.offset = 0
                        bufferInfo.size = sampleSize
                        bufferInfo.presentationTimeUs = audioExtractor.sampleTime
                        bufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(audioTrackIndex, buffer, bufferInfo)
                        audioExtractor.advance()
                    }
                }

                muxer.stop()
                Log.d(TAG, "Successfully remuxed video and audio into ${finalOutputFile.absolutePath}")

                // Cleanup temporary files
                try { videoFile.delete() } catch (_: Exception) {}
                try { audioFile.delete() } catch (_: Exception) {}
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error remuxing video and audio: ${e.message}", e)
                try {
                    videoFile.renameTo(finalOutputFile)
                } catch (_: Exception) {
                    false
                }
            } finally {
                try { videoExtractor?.release() } catch (_: Exception) {}
                try { audioExtractor?.release() } catch (_: Exception) {}
                try { muxer?.release() } catch (_: Exception) {}
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (audioSource == "Mute/None") {
            Log.d(TAG, "Audio source is Mute/None, skipping audio capture")
            return false
        }

        val needInternal = audioSource.contains("Internal")
        val needMic = audioSource.contains("Mic") || audioSource == "Microphone only"

        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            channelConfig,
            audioFormat
        ).coerceAtLeast(8192)

        // 1. Initialize Internal AudioRecord if needed (Android 10+)
        if (needInternal) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && mediaProjection != null) {
                try {
                    val config = AudioPlaybackCaptureConfiguration.Builder(mediaProjection)
                        .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                        .addMatchingUsage(AudioAttributes.USAGE_GAME)
                        .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                        .build()

                    internalAudioRecord = AudioRecord.Builder()
                        .setAudioPlaybackCaptureConfig(config)
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(audioFormat)
                                .setSampleRate(sampleRate)
                                .setChannelMask(channelConfig)
                                .build()
                        )
                        .setBufferSizeInBytes(minBufferSize * 2)
                        .build()

                    if (internalAudioRecord?.state == AudioRecord.STATE_INITIALIZED) {
                        internalAudioRecord?.startRecording()
                        Log.d(TAG, "AudioPlaybackCapture (Internal Audio) started successfully")
                    } else {
                        Log.e(TAG, "Failed to initialize AudioPlaybackCapture AudioRecord")
                        internalAudioRecord?.release()
                        internalAudioRecord = null
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error setting up AudioPlaybackCapture: ${e.message}", e)
                }
            } else {
                Log.w(TAG, "Internal audio capture requires Android 10+ and valid MediaProjection")
            }
        }

        // 2. Initialize Microphone AudioRecord if needed
        if (needMic) {
            try {
                micAudioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    minBufferSize * 2
                )
                if (micAudioRecord?.state == AudioRecord.STATE_INITIALIZED) {
                    micAudioRecord?.startRecording()
                    Log.d(TAG, "Microphone AudioRecord started successfully")
                } else {
                    Log.e(TAG, "Failed to initialize Microphone AudioRecord")
                    micAudioRecord?.release()
                    micAudioRecord = null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error setting up Microphone AudioRecord: ${e.message}", e)
            }
        }

        if (internalAudioRecord == null && micAudioRecord == null) {
            Log.e(TAG, "No audio record sources could be initialized")
            return false
        }

        // 3. Initialize MediaCodec & MediaMuxer for AAC output
        try {
            val codecFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_CHANNEL_COUNT, channelCount)
                setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            }

            mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                configure(codecFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                start()
            }

            mediaMuxer = MediaMuxer(audioOutputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing AAC MediaCodec/MediaMuxer: ${e.message}", e)
            cleanupRecords()
            return false
        }

        isRunning.set(true)
        isPaused.set(false)

        // 4. Start audio recording & encoding worker thread
        audioThread = Thread({ processAudioLoop(minBufferSize) }, "ScreenRecorder-AudioThread").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }

        return true
    }

    private fun processAudioLoop(chunkSize: Int) {
        val internalBuffer = ShortArray(chunkSize / 2)
        val micBuffer = ShortArray(chunkSize / 2)
        val mixedBuffer = ShortArray(chunkSize / 2)
        val byteBuffer = ByteBuffer.allocate(chunkSize).order(ByteOrder.LITTLE_ENDIAN)

        val bufferInfo = MediaCodec.BufferInfo()
        var totalSamplesRecorded = 0L

        while (isRunning.get()) {
            if (isPaused.get()) {
                try {
                    Thread.sleep(20)
                } catch (_: InterruptedException) {
                    break
                }
                continue
            }

            var readCount = 0

            val hasInternal = internalAudioRecord != null
            val hasMic = micAudioRecord != null

            if (hasInternal && hasMic) {
                // Read both streams
                val readInt = internalAudioRecord?.read(internalBuffer, 0, internalBuffer.size) ?: 0
                val readMic = micAudioRecord?.read(micBuffer, 0, micBuffer.size) ?: 0
                readCount = kotlin.math.max(readInt, readMic)

                if (readCount > 0) {
                    if (isMuted.get()) {
                        // TRUE SILENCE when muted
                        Arrays.fill(mixedBuffer, 0, readCount, 0.toShort())
                    } else {
                        // Clean dual mixing with headroom: internal 85%, mic 100%
                        val intWeight = 0.85f
                        val micWeight = 1.0f
                        for (i in 0 until readCount) {
                            val intSample = if (i < readInt) internalBuffer[i] else 0
                            val micSample = if (i < readMic) micBuffer[i] else 0
                            val mix = (intSample * intWeight + micSample * micWeight).toInt()
                            mixedBuffer[i] = mix.coerceIn(-32768, 32767).toShort()
                        }
                    }
                }
            } else if (hasInternal) {
                readCount = internalAudioRecord?.read(internalBuffer, 0, internalBuffer.size) ?: 0
                if (readCount > 0) {
                    if (isMuted.get()) {
                        Arrays.fill(mixedBuffer, 0, readCount, 0.toShort())
                    } else {
                        System.arraycopy(internalBuffer, 0, mixedBuffer, 0, readCount)
                    }
                }
            } else if (hasMic) {
                readCount = micAudioRecord?.read(micBuffer, 0, micBuffer.size) ?: 0
                if (readCount > 0) {
                    if (isMuted.get()) {
                        Arrays.fill(mixedBuffer, 0, readCount, 0.toShort())
                    } else {
                        System.arraycopy(micBuffer, 0, mixedBuffer, 0, readCount)
                    }
                }
            }

            if (readCount <= 0) {
                continue
            }

            // Convert mixed shorts to little-endian bytes
            byteBuffer.clear()
            for (i in 0 until readCount) {
                byteBuffer.putShort(mixedBuffer[i])
            }
            byteBuffer.flip()

            val bytesToSend = readCount * 2
            val presentationTimeUs = (totalSamplesRecorded * 1_000_000L / (sampleRate * channelCount))
            totalSamplesRecorded += readCount

            // Feed to MediaCodec
            val codec = mediaCodec ?: break
            val inIndex = codec.dequeueInputBuffer(10_000)
            if (inIndex >= 0) {
                val inputBuf = codec.getInputBuffer(inIndex)
                inputBuf?.clear()
                inputBuf?.put(byteBuffer)
                codec.queueInputBuffer(inIndex, 0, bytesToSend, presentationTimeUs, 0)
            }

            drainEncoder(bufferInfo, false)
        }

        // Drain end of stream
        drainEncoder(bufferInfo, true)
    }

    private fun drainEncoder(bufferInfo: MediaCodec.BufferInfo, endOfStream: Boolean) {
        val codec = mediaCodec ?: return
        val muxer = mediaMuxer ?: return

        if (endOfStream) {
            try {
                val inIndex = codec.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error sending EOS to audio codec: ${e.message}")
            }
        }

        while (true) {
            val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!endOfStream) break
            } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (!isMuxerStarted) {
                    val newFormat = codec.outputFormat
                    audioTrackIndex = muxer.addTrack(newFormat)
                    muxer.start()
                    isMuxerStarted = true
                    Log.d(TAG, "Audio MediaMuxer started with format: $newFormat")
                }
            } else if (outIndex >= 0) {
                val encodedData = codec.getOutputBuffer(outIndex)
                if (encodedData != null && bufferInfo.size > 0 && isMuxerStarted) {
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        encodedData.position(bufferInfo.offset)
                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(audioTrackIndex, encodedData, bufferInfo)
                    }
                }
                codec.releaseOutputBuffer(outIndex, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    break
                }
            }
        }
    }

    fun setMuted(muted: Boolean) {
        isMuted.set(muted)
        Log.d(TAG, "Audio muted state set to: $muted (True silence = $muted)")
    }

    fun pause() {
        if (!isPaused.getAndSet(true)) {
            pauseStartUs = System.nanoTime() / 1000
            Log.d(TAG, "Audio capture paused")
        }
    }

    fun resume() {
        if (isPaused.getAndSet(false)) {
            val nowUs = System.nanoTime() / 1000
            pauseOffsetUs += (nowUs - pauseStartUs)
            Log.d(TAG, "Audio capture resumed")
        }
    }

    fun stop() {
        if (!isRunning.getAndSet(false)) return

        try {
            audioThread?.join(1500)
        } catch (_: Exception) {}
        audioThread = null

        cleanupRecords()

        try {
            mediaCodec?.stop()
            mediaCodec?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing audio codec: ${e.message}")
        }
        mediaCodec = null

        try {
            if (isMuxerStarted) {
                mediaMuxer?.stop()
            }
            mediaMuxer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing audio muxer: ${e.message}")
        }
        mediaMuxer = null
        isMuxerStarted = false

        Log.d(TAG, "AudioCaptureEngine stopped completely")
    }

    private fun cleanupRecords() {
        try {
            internalAudioRecord?.stop()
            internalAudioRecord?.release()
        } catch (_: Exception) {}
        internalAudioRecord = null

        try {
            micAudioRecord?.stop()
            micAudioRecord?.release()
        } catch (_: Exception) {}
        micAudioRecord = null
    }
}
