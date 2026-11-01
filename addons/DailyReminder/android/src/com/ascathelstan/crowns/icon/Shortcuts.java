package com.ascathelstan.crowns.icon;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;

/**
 * The app icon's long-press shortcuts, and what a shortcut, the widget or the
 * reminder asked the game to open.
 *
 * Each opens the game through {@link Launch} with an "open" extra ("daily",
 * "weekly" or "continue"), which Launch keeps for the game; the game calls
 * {@link #takeOpen} from GDScript through JavaClassWrapper when it starts or
 * comes back to the front, and {@link #setShortcuts} with its own words for them.
 */
public class Shortcuts {
	public static final String EXTRA_OPEN = "open";
	private static final String PREFS = "crowns_launch";

	/** Sets the shortcuts, labelled in the game's language. Needs Android 7.1. */
	public static void setShortcuts(Context context, String daily, String weekly, String resume) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) {
			return;
		}
		List<ShortcutInfo> shortcuts = new ArrayList<>();
		shortcuts.add(shortcut(context, "daily", daily, "crowns_shortcut_daily", 0));
		shortcuts.add(shortcut(context, "weekly", weekly, "crowns_shortcut_weekly", 1));
		shortcuts.add(shortcut(context, "continue", resume, "crowns_shortcut_continue", 2));
		ShortcutManager manager = context.getSystemService(ShortcutManager.class);
		if (manager != null) {
			manager.setDynamicShortcuts(shortcuts);
		}
	}

	/** An intent that opens the game at `open` ("daily", "weekly" or "continue"). */
	public static Intent openIntent(Context context, String open) {
		return new Intent(Intent.ACTION_VIEW).setClassName(context, Launch.class.getName())
				.putExtra(EXTRA_OPEN, open).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
	}

	/** What the game was last asked to open, once; "" when nothing was. */
	public static String takeOpen(Context context) {
		String open = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(EXTRA_OPEN, "");
		if (!open.isEmpty()) {
			context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(EXTRA_OPEN).apply();
		}
		return open;
	}

	/** Keeps `open` for the game to take, from Launch. */
	static void keepOpen(Context context, String open) {
		context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(EXTRA_OPEN, open).commit();
	}

	private static ShortcutInfo shortcut(Context context, String id, String label, String icon, int rank) {
		int resource = context.getResources().getIdentifier(icon, "drawable", context.getPackageName());
		return new ShortcutInfo.Builder(context, id)
				.setShortLabel(label)
				.setIcon(Icon.createWithResource(context, resource != 0 ? resource : context.getApplicationInfo().icon))
				.setIntent(openIntent(context, id))
				.setRank(rank)
				.build();
	}
}
