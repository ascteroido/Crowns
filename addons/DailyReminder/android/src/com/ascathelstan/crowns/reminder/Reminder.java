package com.ascathelstan.crowns.reminder;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import java.util.Calendar;

/**
 * The daily puzzle reminder: one notification a day at a chosen local time.
 *
 * The game calls {@link #schedule} and {@link #cancel} from GDScript through
 * JavaClassWrapper. The alarm then lands here, shows the notification and sets
 * the next day's alarm, and alarms lost to a restart are set again on boot.
 */
public class Reminder extends BroadcastReceiver {
	private static final String PREFS = "crowns_reminder";
	private static final String CHANNEL = "daily_reminder";
	private static final String ACTION_REMIND = "com.ascathelstan.crowns.reminder.REMIND";
	private static final int NOTIFICATION_ID = 1;

	/**
	 * Reminds at hour:minute local time every day, starting with the first such
	 * time after notBeforeMillis (0 for none), e.g. tomorrow once today's puzzle is solved.
	 */
	public static void schedule(Context context, int hour, int minute, long notBeforeMillis, String channelName,
			String title, String text) {
		prefs(context).edit()
				.putBoolean("enabled", true)
				.putInt("hour", hour)
				.putInt("minute", minute)
				.putString("channel", channelName)
				.putString("title", title)
				.putString("text", text)
				.apply();
		setAlarm(context, Math.max(System.currentTimeMillis(), notBeforeMillis));
	}

	/** Shows the reminder right away, for checking it from debug builds. */
	public static void showNow(Context context, String channelName, String title, String text) {
		prefs(context).edit()
				.putString("channel", channelName)
				.putString("title", title)
				.putString("text", text)
				.apply();
		notify(context);
	}

	public static void cancel(Context context) {
		prefs(context).edit().putBoolean("enabled", false).apply();
		alarms(context).cancel(alarmIntent(context));
		notifications(context).cancel(NOTIFICATION_ID);
	}

	@Override
	public void onReceive(Context context, Intent intent) {
		if (!prefs(context).getBoolean("enabled", false)) {
			return;
		}
		if (ACTION_REMIND.equals(intent.getAction())) {
			notify(context);
		}
		// After a reminder, or a restart that cleared the alarm: the next one.
		setAlarm(context, System.currentTimeMillis());
	}

	/** Sets the alarm for the first reminder time after afterMillis. */
	private static void setAlarm(Context context, long afterMillis) {
		SharedPreferences prefs = prefs(context);
		Calendar next = Calendar.getInstance();
		next.setTimeInMillis(afterMillis);
		next.set(Calendar.HOUR_OF_DAY, prefs.getInt("hour", 19));
		next.set(Calendar.MINUTE, prefs.getInt("minute", 0));
		next.set(Calendar.SECOND, 0);
		next.set(Calendar.MILLISECOND, 0);
		if (next.getTimeInMillis() <= afterMillis) {
			next.add(Calendar.DAY_OF_MONTH, 1);
		}
		// Inexact, so it needs no exact-alarm permission; a few minutes late is fine.
		alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.getTimeInMillis(), alarmIntent(context));
	}

	private static void notify(Context context) {
		SharedPreferences prefs = prefs(context);
		NotificationManager manager = notifications(context);
		Notification.Builder builder;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			manager.createNotificationChannel(new NotificationChannel(CHANNEL,
					prefs.getString("channel", "Daily reminder"), NotificationManager.IMPORTANCE_DEFAULT));
			builder = new Notification.Builder(context, CHANNEL);
		} else {
			builder = new Notification.Builder(context);
		}
		int icon = context.getResources().getIdentifier("crowns_reminder_icon", "drawable", context.getPackageName());
		builder.setSmallIcon(icon != 0 ? icon : context.getApplicationInfo().icon)
				.setContentTitle(prefs.getString("title", ""))
				.setContentText(prefs.getString("text", ""))
				.setAutoCancel(true);
		Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
		if (launch != null) {
			builder.setContentIntent(PendingIntent.getActivity(context, 0, launch,
					PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT));
		}
		// Without the notification permission (Android 13+) this does nothing.
		manager.notify(NOTIFICATION_ID, builder.build());
	}

	private static PendingIntent alarmIntent(Context context) {
		Intent intent = new Intent(context, Reminder.class).setAction(ACTION_REMIND);
		return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
	}

	private static SharedPreferences prefs(Context context) {
		return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
	}

	private static AlarmManager alarms(Context context) {
		return (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
	}

	private static NotificationManager notifications(Context context) {
		return (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
	}
}
