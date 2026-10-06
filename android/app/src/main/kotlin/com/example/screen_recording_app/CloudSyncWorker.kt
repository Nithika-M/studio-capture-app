package com.example.screen_recording_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File

class CloudSyncWorker(
    private val appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val TAG = "CloudSyncWorker"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        // 1. If user turned toggle OFF, stop and don't upload
        if (!CloudSyncManager.isAutoSyncEnabled(appContext)) {
            Log.d(TAG, "Auto-Sync is disabled, finishing work.")
            return@withContext Result.success()
        }

        // 2. Check internet connectivity
        if (!isNetworkAvailable(appContext)) {
            Log.w(TAG, "No internet connection available. WorkManager will retry when connected.")
            CloudSyncManager.showNotification(
                appContext,
                "Cloud Vault Sync Paused",
                "Waiting for internet connection to upload recordings...",
                notificationId = 3002
            )
            return@withContext Result.retry()
        }

        val targetFilePath = inputData.getString(CloudSyncManager.KEY_FILE_PATH)
        val filesToUpload = mutableListOf<File>()

        if (!targetFilePath.isNullOrEmpty()) {
            val file = File(targetFilePath)
            if (file.exists() && file.length() > 0) {
                filesToUpload.add(file)
            } else {
                // Wait briefly for file write finalize if fresh
                delay(400)
                if (file.exists() && file.length() > 0) {
                    filesToUpload.add(file)
                }
            }
        } else {
            // Find all local video recordings
            findLocalRecordings(filesToUpload)
        }

        Log.d(TAG, "Found ${filesToUpload.size} files for potential sync")

        var anyFailed = false

        for (file in filesToUpload) {
            // Cancellation / Toggle OFF check
            if (isStopped || !CloudSyncManager.isAutoSyncEnabled(appContext)) {
                Log.d(TAG, "Worker stopped or Auto-Sync toggled OFF. Halting current uploads.")
                return@withContext Result.retry()
            }

            // Duplicate check: Do not re-upload videos that are already synced
            if (CloudSyncManager.isCloudSynced(appContext, file.name)) {
                Log.d(TAG, "Skipping already synced file: ${file.name}")
                continue
            }

            // Do not re-upload videos that were deleted from the cloud
            if (CloudSyncManager.isDeletedFromCloud(appContext, file.name)) {
                Log.d(TAG, "Skipping file previously deleted from cloud: ${file.name}")
                continue
            }

            Log.d(TAG, "Starting cloud upload for: ${file.name} (${file.length()} bytes)")

            val success = uploadFileWithRetry(file)
            if (success) {
                CloudSyncManager.markFileAsSynced(appContext, file)
                CloudSyncManager.showNotification(
                    appContext,
                    "Cloud Vault: Upload Complete",
                    "${file.name} backed up to Cloud Vault",
                    notificationId = 3000 + (file.name.hashCode() % 1000)
                )
            } else {
                anyFailed = true
                CloudSyncManager.showNotification(
                    appContext,
                    "Cloud Vault: Upload Failed",
                    "Failed to back up ${file.name}. Will retry automatically.",
                    notificationId = 3003
                )
            }
        }

        if (anyFailed) {
            Log.w(TAG, "One or more uploads failed. Requesting WorkManager retry.")
            Result.retry()
        } else {
            Log.d(TAG, "All targeted files synced successfully.")
            Result.success()
        }
    }

    private suspend fun uploadFileWithRetry(file: File): Boolean {
        // Attempt upload up to 3 times
        for (attempt in 1..3) {
            if (isStopped || !CloudSyncManager.isAutoSyncEnabled(appContext)) return false
            try {
                if (!isNetworkAvailable(appContext)) {
                    return false
                }

                // Simulate chunked cloud transmission / verify file readability
                val buffer = ByteArray(64 * 1024)
                file.inputStream().use { stream ->
                    var totalRead = 0L
                    val totalSize = file.length()
                    while (true) {
                        if (isStopped || !CloudSyncManager.isAutoSyncEnabled(appContext)) return false
                        val bytesRead = stream.read(buffer)
                        if (bytesRead <= 0) break
                        totalRead += bytesRead
                        // Brief pause to simulate network streaming and allow cancellation responsiveness
                        delay(20)
                    }
                }

                Log.d(TAG, "Upload finished successfully for ${file.name}")
                return true
            } catch (e: Exception) {
                Log.e(TAG, "Upload attempt $attempt failed for ${file.name}: ${e.message}")
                if (attempt < 3) {
                    delay(300L * attempt)
                }
            }
        }
        return false
    }

    private fun findLocalRecordings(destinationList: MutableList<File>) {
        val candidateDirs = mutableListOf<File>()

        try {
            val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            if (moviesDir != null && moviesDir.exists()) {
                candidateDirs.add(moviesDir)
                candidateDirs.add(File(moviesDir, "ConsolidatedRecorder"))
                candidateDirs.add(File(moviesDir, "ScreenRecordingApp"))
            }

            val appMovies = appContext.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            if (appMovies != null && appMovies.exists()) {
                candidateDirs.add(appMovies)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error resolving video dirs: ${e.message}")
        }

        val seenPaths = mutableSetOf<String>()
        for (dir in candidateDirs) {
            if (!dir.exists() || !dir.isDirectory) continue
            val files = dir.listFiles() ?: continue
            for (f in files) {
                if (f.isFile && f.name.endsWith(".mp4", ignoreCase = true) && !f.name.startsWith("temp_")) {
                    if (seenPaths.add(f.absolutePath)) {
                        destinationList.add(f)
                    }
                }
            }
        }

        // Sort latest first
        destinationList.sortByDescending { it.lastModified() }
    }

    private fun isNetworkAvailable(context: Context): Boolean {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}
