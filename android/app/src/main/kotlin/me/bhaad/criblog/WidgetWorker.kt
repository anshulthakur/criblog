package me.bhaad.criblog

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class WidgetWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            val type = inputData.getString("type") ?: return Result.failure()
            Log.d("WidgetWorker", "Processing type: $type")

            // Initialize FlutterEngine on main thread
            val result = runBlocking {
                suspendCancellableCoroutine<Result> { continuation ->
                    val handler = Handler(Looper.getMainLooper())
                    handler.post {
                        try {
                            // Get or create FlutterEngine
                            var engine = FlutterEngineCache.getInstance().get("criblog_engine")
                            if (engine == null) {
                                Log.d("WidgetWorker", "Creating new FlutterEngine")
                                engine = FlutterEngine(applicationContext)
                                engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
                                FlutterEngineCache.getInstance().put("criblog_engine", engine)
                            }

                            // Invoke MethodChannel
                            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "me.bhaad.criblog/widget")
                            channel.invokeMethod("handleAction", type, object : MethodChannel.Result {
                                override fun success(result: Any?) {
                                    Log.d("WidgetWorker", "MethodChannel success for type: $type, result: $result")
                                    // Update widget with result (expecting map with feeding, sleep, feedingSource)
                                    if (result is Map<*, *>) {
                                        val feeding = result["feeding"] as? Boolean ?: false
                                        val sleep = result["sleep"] as? Boolean ?: false
                                        val feedingSource = result["feedingSource"] as? String ?: "Breast"
                                        handler.post {
                                            updateWidgets(feeding, sleep, feedingSource)
                                            continuation.resume(Result.success())
                                        }
                                    } else {
                                        // Fallback to SharedPreferences with increased delay
                                        handler.postDelayed({
                                            updateWidgets()
                                            continuation.resume(Result.success())
                                        }, 1000) // Increased to 1000ms
                                    }
                                }
                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    Log.e("WidgetWorker", "MethodChannel error: $errorCode, $errorMessage")
                                    continuation.resume(Result.failure())
                                }
                                override fun notImplemented() {
                                    Log.e("WidgetWorker", "MethodChannel not implemented")
                                    continuation.resume(Result.failure())
                                }
                            })
                        } catch (e: Exception) {
                            Log.e("WidgetWorker", "Main thread execution failed: $e")
                            continuation.resumeWithException(e)
                        }
                    }
                }
            }

            result
        } catch (e: Exception) {
            Log.e("WidgetWorker", "Work failed: $e")
            Result.failure()
        }
    }

    private fun updateWidgets(feeding: Boolean = false, sleep: Boolean = false, feedingSource: String = "Breast") {
        try {
            val context = applicationContext
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val widgetIds = appWidgetManager.getAppWidgetIds(ComponentName(context, WidgetProvider::class.java))
            Log.d("WidgetWorker", "Updating widgets with IDs: ${widgetIds.joinToString()}, feeding=$feeding, sleep=$sleep, feedingSource=$feedingSource")
            for (id in widgetIds) {
                WidgetProvider.updateWidget(context, appWidgetManager, id, feeding, sleep, feedingSource)
            }
        } catch (e: Exception) {
            Log.e("WidgetWorker", "Failed to update widgets: $e")
        }
    }
}