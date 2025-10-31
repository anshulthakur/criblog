// android/app/src/main/kotlin/me/bhaad/criblog/WidgetWorker.kt
package me.bhaad.criblog

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache


class WidgetWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            val type = inputData.getString("type") ?: return Result.failure()

            val engine = FlutterEngineCache.getInstance().get("criblog_engine")
            if (engine == null) {
                // Fallback: create a new engine if cache is empty
                val fallbackEngine = FlutterEngine(applicationContext)
                fallbackEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
                // Optionally cache it again
                FlutterEngineCache.getInstance().put("criblog_engine", fallbackEngine)
                return Result.failure() // or use fallbackEngine if safe
            }

            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "me.bhaad.criblog/widget")
            channel.invokeMethod("handleAction", type)

            Result.success()
        } catch (e: Exception) {
            Result.failure()
        }
    }
}