package club.geekpie.techpie.island

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Rebuilds absolute island alarms after boot, clock, timezone, or date changes. */
object IslandTimelineRefreshScheduler {
    private const val WORK_NAME = "techpie-island-timeline-rebuild"

    fun enqueue(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<IslandTimelineRefreshWorker>().build(),
        )
    }
}

/** Runs the cache-only Dart island scheduler in a short-lived Flutter engine. */
class IslandTimelineRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    private val main = Handler(Looper.getMainLooper())
    private val finished = CountDownLatch(1)
    private val completed = AtomicBoolean(false)
    private var engine: FlutterEngine? = null
    private var completion: MethodChannel? = null

    override fun doWork(): Result {
        main.post {
            if (isStopped) {
                finished.countDown()
                return@post
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val running = FlutterEngine(applicationContext)
                engine = running
                val messenger = running.dartExecutor.binaryMessenger
                completion = MethodChannel(messenger, CHANNEL).also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        if (call.method == "done") {
                            completed.set(call.argument<Boolean>("success") == true)
                            result.success(true)
                            finished.countDown()
                        } else {
                            result.notImplemented()
                        }
                    }
                }
                running.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        ENTRYPOINT,
                    ),
                )
            } catch (_: Exception) {
                finished.countDown()
            }
        }

        try {
            finished.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            main.post { cleanup() }
        }
        return when {
            completed.get() -> Result.success()
            runAttemptCount < MAX_ATTEMPTS -> Result.retry()
            else -> Result.failure()
        }
    }

    override fun onStopped() {
        finished.countDown()
        main.post { cleanup() }
        super.onStopped()
    }

    private fun cleanup() {
        completion?.setMethodCallHandler(null)
        completion = null
        engine?.destroy()
        engine = null
    }

    private companion object {
        const val CHANNEL = "techpie/background"
        const val ENTRYPOINT = "islandTimelineRebuild"
        const val TIMEOUT_SECONDS = 60L
        const val MAX_ATTEMPTS = 3
    }
}
