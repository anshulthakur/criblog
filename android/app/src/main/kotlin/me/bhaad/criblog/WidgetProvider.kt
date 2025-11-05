package me.bhaad.criblog

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import androidx.work.ExistingWorkPolicy

class WidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        Log.d("WidgetProvider", "onUpdate called with appWidgetIds: ${appWidgetIds.joinToString()}")
        for (id in appWidgetIds) {
            try {
                updateWidget(context, appWidgetManager, id)
            } catch (e: Exception) {
                Log.e("WidgetProvider", "Failed to update widget ID $id: $e")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("WidgetProvider", "onReceive called with action: ${intent.action}")
        super.onReceive(context, intent)
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, WidgetProvider::class.java))
        when (intent.action) {
            ACTION_FEEDING -> enqueueWork(context, "feeding")
            ACTION_SLEEP -> enqueueWork(context, "sleep")
            "me.bhaad.criblog.UPDATE_WIDGET" -> {
                Log.d("WidgetProvider", "Received UPDATE_WIDGET broadcast")
                onUpdate(context, manager, ids)
            }
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                Log.d("WidgetProvider", "Received APPWIDGET_UPDATE, checking state")
                for (id in ids) {
                    val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                    val currentFeeding = prefs.getBoolean("ongoing_feeding", false)
                    val currentSleep = prefs.getBoolean("ongoing_sleep", false)
                    val currentSource = prefs.getString("feeding_source", "Breast") ?: "Breast"
                    Log.d("WidgetProvider", "Current state for ID $id: feeding=$currentFeeding, sleep=$currentSleep, source=$currentSource")
                    updateWidget(context, manager, id, currentFeeding, currentSleep, currentSource)
                }
            }
        }
    }

    private fun enqueueWork(context: Context, type: String) {
        Log.d("WidgetProvider", "Enqueuing work for type: $type")
        val workRequest = OneTimeWorkRequestBuilder<WidgetWorker>()
            .setInputData(workDataOf("type" to type))
            .addTag("widget_action_$type")
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork("widget_action_$type", ExistingWorkPolicy.REPLACE, workRequest)
    }

    companion object {
        const val ACTION_FEEDING = "me.bhaad.criblog.FEEDING"
        const val ACTION_SLEEP = "me.bhaad.criblog.SLEEP"

        fun updateWidget(context: Context, manager: AppWidgetManager, id: Int, feeding: Boolean? = null, sleep: Boolean? = null, feedingSource: String? = null) {
            Log.d("WidgetProvider", "Updating widget ID: $id")
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            try {
                val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                val finalFeeding = feeding ?: prefs.getBoolean("ongoing_feeding", false)
                val finalSleep = sleep ?: prefs.getBoolean("ongoing_sleep", false)
                val finalFeedingSource = feedingSource ?: prefs.getString("feeding_source", "Breast") ?: "Breast"
                Log.d("WidgetProvider", "Widget state: feeding=$finalFeeding, sleep=$finalSleep, feedingSource=$finalFeedingSource")

                // Update feeding button
                views.setTextViewText(R.id.feeding_button, if (finalFeeding) "End Feeding" else "Start Feeding")
                views.setInt(R.id.feeding_button, "setBackgroundResource", if (finalFeeding) R.color.red else R.color.orange)
                views.setTextViewText(R.id.feeding_status, finalFeedingSource)

                // Update sleep button
                views.setTextViewText(R.id.sleep_button, if (finalSleep) "End Sleep" else "Start Sleep")
                views.setInt(R.id.sleep_button, "setBackgroundResource", if (finalSleep) R.color.red else R.color.green)
                views.setTextViewText(R.id.sleep_status, if (finalSleep) "Ongoing" else "Ready")

                // Pending Intents for button clicks
                val feedingIntent = Intent(context, WidgetProvider::class.java).apply { action = ACTION_FEEDING }
                val feedingPI = PendingIntent.getBroadcast(context, 0, feedingIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.feeding_button, feedingPI)

                val sleepIntent = Intent(context, WidgetProvider::class.java).apply { action = ACTION_SLEEP }
                val sleepPI = PendingIntent.getBroadcast(context, 1, sleepIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.sleep_button, sleepPI)

                manager.updateAppWidget(id, views)
                Log.d("WidgetProvider", "Widget ID $id updated successfully")
            } catch (e: Exception) {
                Log.e("WidgetProvider", "Error updating widget ID $id: $e")
            }
        }
    }
}
