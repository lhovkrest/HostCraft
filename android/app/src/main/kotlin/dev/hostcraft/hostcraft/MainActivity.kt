package dev.hostcraft.hostcraft

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.util.zip.ZipInputStream
import android.content.Context
import io.flutter.embedding.engine.dart.DartExecutor

class MainActivity : FlutterActivity() {
    companion object { private var hostingEngine: FlutterEngine? = null }
    // Keep the UI isolate (which owns stdin/stdout) attached to the foreground
    // process even when Android recreates the Activity or it is swiped away.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return hostingEngine ?: FlutterEngine(context.applicationContext).also {
            hostingEngine = it
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }
    override fun shouldDestroyEngineWithHost() = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.hostcraft/runtime")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "info" -> result.success(info())
                    "installRuntime" -> Thread {
                        try {
                            val abi = Build.SUPPORTED_ABIS.first()
                            require(abi == "arm64-v8a" || abi == "x86_64") { "HostCraft needs a 64-bit Android device" }
                            val runtime = File(filesDir, "java21")
                            val marker = File(runtime, ".hostcraft-runtime-v1")
                            if (!marker.exists()) {
                                val staging = File(filesDir, "java21-install")
                                staging.deleteRecursively()
                                staging.mkdirs()
                                ZipInputStream(assets.open("runtime-$abi.zip")).use { zip ->
                                    var entry = zip.nextEntry
                                    while (entry != null) {
                                        val out = File(staging, entry.name)
                                        require(out.canonicalPath.startsWith(staging.canonicalPath + File.separator)) { "Invalid archive path" }
                                        if (entry.isDirectory) out.mkdirs() else {
                                            out.parentFile!!.mkdirs()
                                            out.outputStream().use { zip.copyTo(it) }
                                        }
                                        zip.closeEntry(); entry = zip.nextEntry
                                    }
                                }
                                runtime.deleteRecursively()
                                check(staging.renameTo(runtime)) { "Cannot install Java runtime" }
                                marker.writeText("Java 21 / HostCraft 0.1")
                            }
                            val bootstrap = File(filesDir, "hostcraft-bootstrap.jar")
                            assets.open("hostcraft-bootstrap.jar").use { source -> bootstrap.outputStream().use { source.copyTo(it) } }
                            runOnUiThread { result.success(info()) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RUNTIME", e.message, null) }
                        }
                    }.start()
                    else -> result.notImplemented()
                }
            }
    }
    private fun info() = mapOf(
        "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
        "javaHome" to File(filesDir, "java21").absolutePath,
        "bootstrap" to File(filesDir, "hostcraft-bootstrap.jar").absolutePath,
        "cacheDir" to cacheDir.absolutePath,
        "abi" to Build.SUPPORTED_ABIS.first(),
        "clockTicks" to Os.sysconf(OsConstants._SC_CLK_TCK)
    )
}
