package com.tangtang.warm_calendar

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "warm_calendar/android").setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                try {
                    val file = File(call.argument<String>("path") ?: "").canonicalFile
                    val folder = File(cacheDir, "updates").canonicalFile
                    require(file.path.startsWith(folder.path + File.separator) && file.extension == "apk" && file.isFile)
                    if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        result.success(false)
                    } else {
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(true)
                    }
                } catch (error: Exception) { result.error("install_unavailable", error.message, null) }
            } else if (call.method == "openNotificationSettings") {
                try {
                    val intent = if (Build.VERSION.SDK_INT >= 26) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (error: Exception) { result.error("settings_unavailable", error.message, null) }
            } else { result.notImplemented() }
        }
    }
}
