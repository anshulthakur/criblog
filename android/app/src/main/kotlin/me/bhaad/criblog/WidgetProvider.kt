package me.bhaad.criblog

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf

class WidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) updateWidget(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_FEEDING -> enqueueWork(context, "feeding")
            ACTION_SLEEP -> enqueueWork(context, "sleep")
        }
        // Refresh all widgets
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(android.content.ComponentName(context, WidgetProvider::class.java))
        onUpdate(context, manager, ids)
    }

    private fun enqueueWork(context: Context, type: String) {
        val work = OneTimeWorkRequestBuilder<WidgetWorker>()
            .setInputData(workDataOf("type" to type))
            .build()
        WorkManager.getInstance(context).enqueue(work)
    }

    companion object {
        const val ACTION_FEEDING = "me.bhaad.criblog.FEEDING"
        const val ACTION_SLEEP = "me.bhaad.criblog.SLEEP"

        private fun updateWidget(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)

            val feeding = prefs.getBoolean("widget_ongoing_feeding", false)
            val sleep = prefs.getBoolean("widget_ongoing_sleep", false)

            views.setTextViewText(R.id.feeding_button, if (feeding) "End Feeding" else "Start Feeding")
            views.setInt(R.id.feeding_button, "setBackgroundResource", if (feeding) R.color.red else R.color.orange)
            views.setTextViewText(R.id.feeding_status, "Breast")

            views.setTextViewText(R.id.sleep_button, if (sleep) "End Sleep" else "Start Sleep")
            views.setInt(R.id.sleep_button, "setBackgroundResource", if (sleep) R.color.red else R.color.green)
            views.setTextViewText(R.id.sleep_status, if (sleep) "Ongoing" else "Ready")

            // Pending Intents
            val feedingIntent = Intent(context, WidgetProvider::class.java).apply { action = ACTION_FEEDING }
            val feedingPI = PendingIntent.getBroadcast(context, 0, feedingIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.feeding_button, feedingPI)

            val sleepIntent = Intent(context, WidgetProvider::class.java).apply { action = ACTION_SLEEP }
            val sleepPI = PendingIntent.getBroadcast(context, 1, sleepIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.sleep_button, sleepPI)

            manager.updateAppWidget(id, views)
        }
    }
}