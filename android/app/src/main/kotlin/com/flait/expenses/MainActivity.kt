package com.flait.expenses

import android.Manifest
import android.os.Build
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "expense_manage/notifications")
            .setMethodCallHandler { call, result ->
                val id = call.argument<String>("id")
                val title = call.argument<String>("title")
                val body = call.argument<String>("body")
                when {
                    call.method == "permission" -> {
                        val prefs = getSharedPreferences("expense_notifications", MODE_PRIVATE)
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                            !prefs.getBoolean("requested", false)
                        ) {
                            prefs.edit().putBoolean("requested", true).apply()
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
                        }
                        result.success(null)
                    }
                    call.method == "show" && id != null && title != null && body != null -> {
                        ExpenseNotifications.show(this, id, title, body)
                        result.success(null)
                    }
                    call.method == "schedule" && id != null && title != null && body != null -> {
                        val time = call.argument<Number>("when")?.toLong()
                        if (time == null) result.error("date", "Return date is required.", null)
                        else {
                            ExpenseNotifications.schedule(this, id, title, body, time)
                            result.success(null)
                        }
                    }
                    call.method == "cancel" && id != null -> {
                        ExpenseNotifications.cancel(this, id)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
