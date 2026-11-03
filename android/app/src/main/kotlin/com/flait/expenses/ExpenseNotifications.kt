package com.flait.expenses

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import org.json.JSONObject

class ExpenseReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            ExpenseNotifications.restoreAlarms(context)
            return
        }
        val id = intent.getStringExtra("id") ?: return
        ExpenseNotifications.deliverAlarm(context, id)
    }
}

object ExpenseNotifications {
    private const val channelId = "expense_updates"
    private fun prefs(context: Context) =
        context.getSharedPreferences("expense_notifications", Context.MODE_PRIVATE)

    fun show(context: Context, id: String, title: String, body: String): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        if (!manager.areNotificationsEnabled()) return false
        val storage = prefs(context)
        if (storage.getBoolean("shown:$id", false)) return true
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(channelId, "Expense updates", NotificationManager.IMPORTANCE_DEFAULT)
            manager.createNotificationChannel(channel)
            if (manager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) return false
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val launch = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val openApp = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE)
        manager.notify(id, 1, builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(openApp)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .build())
        storage.edit().putBoolean("shown:$id", true).apply()
        return true
    }

    private fun pending(context: Context, id: String): PendingIntent {
        val intent = Intent(context, ExpenseReminderReceiver::class.java)
            .setData(Uri.Builder().scheme("expense-manage").authority("loan").appendPath(id).build())
            .putExtra("id", id)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun arm(context: Context, id: String, time: Long) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, time, pending(context, id)
        )
    }

    fun schedule(context: Context, id: String, title: String, body: String, time: Long) {
        val storage = prefs(context)
        if (storage.getBoolean("shown:due:$id", false)) return
        val row = JSONObject().put("title", title).put("body", body).put("time", time).toString()
        if (storage.getString("alarm:$id", null) != row) {
            storage.edit().putString("alarm:$id", row).apply()
            arm(context, id, time)
        }
        if (time <= System.currentTimeMillis()) deliverAlarm(context, id)
    }

    fun deliverAlarm(context: Context, id: String) {
        val storage = prefs(context)
        val row = storage.getString("alarm:$id", null)?.let { JSONObject(it) } ?: return
        if (show(context, "due:$id", row.getString("title"), row.getString("body"))) {
            storage.edit().remove("alarm:$id").apply()
        }
    }

    fun cancel(context: Context, id: String) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending(context, id))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel("due:$id", 1)
        prefs(context).edit().remove("alarm:$id").apply()
    }

    fun restoreAlarms(context: Context) {
        for ((key, value) in prefs(context).all) {
            if (key.startsWith("alarm:") && value is String) {
                arm(context, key.removePrefix("alarm:"), JSONObject(value).getLong("time"))
            }
        }
    }
}
