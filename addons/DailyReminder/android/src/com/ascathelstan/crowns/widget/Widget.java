package com.ascathelstan.crowns.widget;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.util.SizeF;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.view.View;
import android.widget.RemoteViews;

import com.ascathelstan.crowns.icon.Shortcuts;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;

/**
 * The home screen widget: today's daily puzzle's board, solved or ready to play,
 * and the streak while it lasts. Tapping it opens the daily.
 *
 * The game calls {@link #update} from GDScript through JavaClassWrapper with its
 * words for each line and the dates they hold for, and draws the coming days'
 * boards into a folder: daily-YYYY-MM-DD.png, with its size and difficulty in
 * daily-YYYY-MM-DD.txt. The widget works out the day itself, so it turns over
 * to the next daily at the right moment with the game closed: an alarm redraws
 * it when the daily changes. Without a board for the day, it shows the crown.
 *
 * It can be resized: small, it's just the board; wide, the board with the text
 * beside it; tall, the text beneath it. See {@link #LAYOUTS}.
 */
public class Widget extends AppWidgetProvider {
	private static final String PREFS = "crowns_widget";
	private static final String ACTION_NEXT_DAY = "com.ascathelstan.crowns.widget.NEXT_DAY";
	private static final long DAY = 24 * 60 * 60 * 1000L;
	/**
	 * Layouts and the least room each needs, in dp: the widget uses the roomiest
	 * one that fits (by area), as Android 12's size-mapped RemoteViews do.
	 */
	private static final String[] LAYOUTS = {"crowns_widget_small", "crowns_widget", "crowns_widget_tall"};
	private static final float[][] SIZES = {{40f, 40f}, {170f, 56f}, {100f, 170f}};

	/**
	 * Shows `solvedText` while `solvedDate` is today's daily, else `readyText`, and
	 * `streakText` while the streak lasts: its last daily, `streakDate`, is today's
	 * or yesterday's. Dates are "YYYY-MM-DD" on the daily calendar, which turns over
	 * at midnight `offsetSeconds` from UTC. `boardFolder` holds the boards.
	 */
	public static void update(Context context, String title, String readyText, String solvedDate, String solvedText,
			String streakDate, String streakText, int offsetSeconds, String boardFolder) {
		prefs(context).edit()
				.putString("boards", boardFolder)
				.putString("title", title)
				.putString("ready", readyText)
				.putString("solved_date", solvedDate)
				.putString("solved", solvedText)
				.putString("streak_date", streakDate)
				.putString("streak", streakText)
				.putInt("offset", offsetSeconds)
				.apply();
		redraw(context);
	}

	@Override
	public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
		redraw(context);
	}

	@Override
	public void onReceive(Context context, Intent intent) {
		super.onReceive(context, intent);
		if (ACTION_NEXT_DAY.equals(intent.getAction())) {
			redraw(context);
		}
	}

	@Override
	public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, Bundle options) {
		redraw(context);
	}

	@Override
	public void onDisabled(Context context) {
		alarms(context).cancel(nextDayIntent(context));
	}

	private static void redraw(Context context) {
		AppWidgetManager manager = AppWidgetManager.getInstance(context);
		int[] ids = manager.getAppWidgetIds(new ComponentName(context, Widget.class));
		if (ids.length == 0) {
			return;
		}
		SharedPreferences prefs = prefs(context);
		long offset = prefs.getInt("offset", -7 * 3600) * 1000L;
		long now = System.currentTimeMillis();
		String today = date(now + offset);
		String yesterday = date(now + offset - DAY);
		boolean solved = today.equals(prefs.getString("solved_date", ""));
		String streakDate = prefs.getString("streak_date", "");
		String streak = prefs.getString("streak", "");
		boolean streakAlive = !streak.isEmpty() && (streakDate.equals(today) || streakDate.equals(yesterday));

		File folder = new File(prefs.getString("boards", ""));
		Bitmap board = BitmapFactory.decodeFile(new File(folder, "daily-" + today + ".png").getPath());
		String detail = read(new File(folder, "daily-" + today + ".txt"));
		String status = solved ? prefs.getString("solved", "") : prefs.getString("ready", "Ready to play");
		RemoteViews[] layouts = new RemoteViews[LAYOUTS.length];
		for (int i = 0; i < LAYOUTS.length; i++) {
			layouts[i] = fill(context, LAYOUTS[i], prefs.getString("title", "Daily puzzle"), detail, status,
					streakAlive ? streak : "", solved, board);
		}
		for (int id : ids) {
			manager.updateAppWidget(id, pick(manager, id, layouts));
		}

		// Redraw when the next daily comes out. Inexact, so it needs no exact-alarm permission.
		long nextDay = ((now + offset) / DAY + 1) * DAY - offset;
		alarms(context).set(AlarmManager.RTC, nextDay + 1000, nextDayIntent(context));
	}

	/** One of LAYOUTS filled in: empty texts are hidden, and the crown stands in for a missing board. */
	private static RemoteViews fill(Context context, String layout, String title, String detail, String status,
			String streak, boolean solved, Bitmap board) {
		RemoteViews views = new RemoteViews(context.getPackageName(), resource(context, layout, "layout"));
		views.setTextViewText(resource(context, "crowns_widget_title", "id"), title);
		views.setTextViewText(resource(context, "crowns_widget_status", "id"), status);
		int detailView = resource(context, "crowns_widget_detail", "id");
		views.setTextViewText(detailView, detail);
		views.setViewVisibility(detailView, detail.isEmpty() ? View.GONE : View.VISIBLE);
		int streakView = resource(context, "crowns_widget_streak", "id");
		views.setTextViewText(streakView, streak);
		views.setViewVisibility(streakView, streak.isEmpty() ? View.GONE : View.VISIBLE);
		views.setViewVisibility(resource(context, "crowns_widget_check", "id"), solved ? View.VISIBLE : View.GONE);
		int boardView = resource(context, "crowns_widget_board", "id");
		if (board != null) {
			views.setImageViewBitmap(boardView, board);
		}
		views.setViewVisibility(boardView, board != null ? View.VISIBLE : View.GONE);
		views.setViewVisibility(resource(context, "crowns_widget_crown", "id"), board != null ? View.GONE : View.VISIBLE);
		PendingIntent open = PendingIntent.getActivity(context, 1, Shortcuts.openIntent(context, "daily"),
				PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
		views.setOnClickPendingIntent(resource(context, "crowns_widget_root", "id"), open);
		return views;
	}

	/**
	 * The views for widget `id`: on Android 12 and up, all the layouts by the room
	 * they need, for the launcher to choose as it's resized; before that, the one
	 * for the size it reports now.
	 */
	private static RemoteViews pick(AppWidgetManager manager, int id, RemoteViews[] layouts) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			Map<SizeF, RemoteViews> bySize = new LinkedHashMap<>();
			for (int i = 0; i < layouts.length; i++) {
				bySize.put(new SizeF(SIZES[i][0], SIZES[i][1]), layouts[i]);
			}
			return new RemoteViews(bySize);
		}
		Bundle options = manager.getAppWidgetOptions(id);
		// Portrait: the narrowest width and the tallest height.
		float width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180);
		float height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 110);
		int best = 0;
		for (int i = 1; i < layouts.length; i++) {
			boolean fits = SIZES[i][0] <= width && SIZES[i][1] <= height;
			if (fits && SIZES[i][0] * SIZES[i][1] > SIZES[best][0] * SIZES[best][1]) {
				best = i;
			}
		}
		return layouts[best];
	}

	/** A small text file's contents, or "" when there's none. */
	private static String read(File file) {
		byte[] bytes = new byte[(int) Math.min(file.length(), 256)];
		try (FileInputStream in = new FileInputStream(file)) {
			int length = in.read(bytes);
			return length > 0 ? new String(bytes, 0, length, StandardCharsets.UTF_8).trim() : "";
		} catch (IOException e) {
			return "";
		}
	}

	/** "YYYY-MM-DD" of a moment already shifted onto the daily calendar. */
	private static String date(long shiftedMillis) {
		SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd", Locale.US);
		format.setTimeZone(TimeZone.getTimeZone("UTC"));
		return format.format(new Date(shiftedMillis));
	}

	/** Resources are looked up by name: the plugin is built without an R class. */
	private static int resource(Context context, String name, String type) {
		return context.getResources().getIdentifier(name, type, context.getPackageName());
	}

	private static PendingIntent nextDayIntent(Context context) {
		Intent intent = new Intent(context, Widget.class).setAction(ACTION_NEXT_DAY);
		return PendingIntent.getBroadcast(context, 2, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
	}

	private static SharedPreferences prefs(Context context) {
		return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
	}

	private static AlarmManager alarms(Context context) {
		return (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
	}
}
