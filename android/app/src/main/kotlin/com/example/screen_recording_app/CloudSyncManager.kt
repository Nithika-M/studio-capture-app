package com.example.screen_recording_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

object CloudSyncManager {
    const val TAG = "CloudSyncManager"
    const val WORK_TAG = "cloud_vault_sync_work"
    const val UNIQUE_SYNC_ALL = "CloudVaultAutoSync"
    const val KEY_FILE_PATH = "key_file_path"
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val PREF_AUTO_SYNC_KEY = "flutter.pref_auto_sync"
    const val PREF_SYNCED_TITLES_KEY = "flutter.pref_synced_cloud_titles"
    const val PREF_DELETED_TITLES_KEY = "flutter.pref_deleted_cloud_titles"
    const val PREF_VAULT_RECORDS_KEY = "flutter.pref_cloud_vault_records"
    const val NOTIFICATION_CHANNEL_ID = "cloud_vault_notifications"

    fun isAutoSyncEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(PREF_AUTO_SYNC_KEY, false)
    }

    fun setAutoSyncEnabled(context: Context, enabled: Boolean) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(PREF_AUTO_SYNC_KEY, enabled).apply()
    }

    fun isCloudSynced(context: Context, filename: String): Boolean {
        val cleanName = filename.substringAfterLast(File.separator).substringAfterLast("/").trim()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val deletedJson = prefs.getString(PREF_DELETED_TITLES_KEY, "[]") ?: "[]"
        val syncedJson = prefs.getString(PREF_SYNCED_TITLES_KEY, "[]") ?: "[]"

        try {
            val deletedArray = JSONArray(deletedJson)
            for (i in 0 until deletedArray.length()) {
                if (deletedArray.optString(i).equals(cleanName, ignoreCase = true)) {
                    return false
                }
            }
            val syncedArray = JSONArray(syncedJson)
            for (i in 0 until syncedArray.length()) {
                if (syncedArray.optString(i).equals(cleanName, ignoreCase = true)) {
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking isCloudSynced: ${e.message}")
        }
        return false
    }

    fun isDeletedFromCloud(context: Context, filename: String): Boolean {
        val cleanName = filename.substringAfterLast(File.separator).substringAfterLast("/").trim()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val deletedJson = prefs.getString(PREF_DELETED_TITLES_KEY, "[]") ?: "[]"
        try {
            val deletedArray = JSONArray(deletedJson)
            for (i in 0 until deletedArray.length()) {
                if (deletedArray.optString(i).equals(cleanName, ignoreCase = true)) {
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking isDeletedFromCloud: ${e.message}")
        }
        return false
    }

    fun markFileAsSynced(context: Context, file: File) {
        val cleanName = file.name.trim()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        try {
            // 1. Remove from deleted titles if present
            val deletedJson = prefs.getString(PREF_DELETED_TITLES_KEY, "[]") ?: "[]"
            val deletedArray = JSONArray(deletedJson)
            val newDeleted = JSONArray()
            for (i in 0 until deletedArray.length()) {
                val item = deletedArray.optString(i)
                if (!item.equals(cleanName, ignoreCase = true)) {
                    newDeleted.put(item)
                }
            }

            // 2. Add to synced titles
            val syncedJson = prefs.getString(PREF_SYNCED_TITLES_KEY, "[]") ?: "[]"
            val syncedArray = JSONArray(syncedJson)
            var alreadyPresent = false
            for (i in 0 until syncedArray.length()) {
                if (syncedArray.optString(i).equals(cleanName, ignoreCase = true)) {
                    alreadyPresent = true
                    break
                }
            }
            if (!alreadyPresent) {
                syncedArray.put(cleanName)
            }

            // 3. Add to cloud vault records
            val recordsJson = prefs.getString(PREF_VAULT_RECORDS_KEY, "[]") ?: "[]"
            val recordsArray = JSONArray(recordsJson)
            val newRecords = JSONArray()
            for (i in 0 until recordsArray.length()) {
                val raw = recordsArray.optString(i)
                try {
                    val obj = JSONObject(raw)
                    if (!obj.optString("title").equals(cleanName, ignoreCase = true)) {
                        newRecords.put(raw)
                    }
                } catch (_: Exception) {
                    newRecords.put(raw)
                }
            }

            val now = Date()
            val dateFormat = SimpleDateFormat("MMM d, yyyy • HH:mm", Locale.US)
            val sizeStr = if (file.exists()) {
                val bytes = file.length()
                if (bytes >= 1024 * 1024 * 1024) {
                    String.format(Locale.US, "%.1f GB", bytes.toDouble() / (1024 * 1024 * 1024))
                } else {
                    String.format(Locale.US, "%.1f MB", bytes.toDouble() / (1024 * 1024))
                }
            } else "15.0 MB"

            val recordObj = JSONObject().apply {
                put("title", cleanName)
                put("filePath", file.absolutePath)
                put("size", sizeStr)
                put("date", dateFormat.format(now))
                put("duration", "01:00")
                put("status", "Synced")
                put("provider", "Cloud Vault")
                put("resolution", "1080p 60fps")
                put("uploadedAt", now.time)
            }
            newRecords.put(recordObj.toString())

            prefs.edit()
                .putString(PREF_DELETED_TITLES_KEY, newDeleted.toString())
                .putString(PREF_SYNCED_TITLES_KEY, syncedArray.toString())
                .putString(PREF_VAULT_RECORDS_KEY, newRecords.toString())
                .apply()
            Log.d(TAG, "Marked $cleanName as synced in SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to markFileAsSynced: ${e.message}", e)
        }
    }

    /**
     * Starts auto-sync with WorkManager to upload all unsynced local videos.
     * Enqueues with network constraint CONNECTED so if there is no internet,
     * WorkManager queues it and retries automatically when connection returns.
     */
    fun startAutoSync(context: Context) {
        setAutoSyncEnabled(context, true)

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val workRequest = OneTimeWorkRequestBuilder<CloudSyncWorker>()
            .setConstraints(constraints)
            .addTag(WORK_TAG)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_SYNC_ALL,
            ExistingWorkPolicy.REPLACE,
            workRequest
        )
        Log.d(TAG, "WorkManager auto-sync started (sync all videos)")
    }

    /**
     * Enqueues a single recording to be uploaded in background as soon as it is saved.
     * Only enqueues if auto-sync is enabled.
     */
    fun enqueueUpload(context: Context, filePath: String) {
        if (!isAutoSyncEnabled(context)) {
            Log.d(TAG, "Skipping enqueueUpload because Auto-Sync is OFF")
            return
        }

        val file = File(filePath)
        if (!file.exists() && !filePath.endsWith(".mp4")) {
            Log.w(TAG, "Cannot enqueue non-existent file: $filePath")
            return
        }

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val workRequest = OneTimeWorkRequestBuilder<CloudSyncWorker>()
            .setInputData(workDataOf(KEY_FILE_PATH to filePath))
            .setConstraints(constraints)
            .addTag(WORK_TAG)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
            .build()

        val uniqueName = "upload_${file.name}"
        WorkManager.getInstance(context).enqueueUniqueWork(
            uniqueName,
            ExistingWorkPolicy.KEEP,
            workRequest
        )
        Log.d(TAG, "WorkManager upload enqueued for: ${file.name}")
    }

    /**
     * Cancels all running and queued uploads when toggle is turned OFF.
     * Does NOT delete already uploaded videos in the cloud.
     */
    fun cancelAllSync(context: Context) {
        setAutoSyncEnabled(context, false)
        try {
            val workManager = WorkManager.getInstance(context)
            workManager.cancelUniqueWork(UNIQUE_SYNC_ALL)
            workManager.cancelAllWorkByTag(WORK_TAG)
            Log.d(TAG, "Cancelled all WorkManager sync jobs")
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling sync jobs: ${e.message}")
        }
    }

    fun showNotification(context: Context, title: String, message: String, notificationId: Int = 3001) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Cloud Vault Sync",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Notifications for Cloud Vault uploads and status"
                }
                manager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setContentTitle(title)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .build()

            manager.notify(notificationId, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to show notification: ${e.message}")
        }
    }
}
