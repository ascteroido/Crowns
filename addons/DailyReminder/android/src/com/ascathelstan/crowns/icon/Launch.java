package com.ascathelstan.crowns.icon;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * Where every app icon, shortcut, the widget and the reminder notification lead:
 * opens the game in its own task and closes at once, unseen.
 *
 * Android closes a task whose launcher entry is disabled, so the game must never
 * run in a task opened from an icon, or switching icons would close it. The game's
 * activity is singleInstancePerTask, so it always gets a task of its own here,
 * and an icon tapped while it's running brings that task back.
 */
public class Launch extends Activity {
	/** The game's own activity. */
	public static final String GAME = "com.godot.game.GodotApp";

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		// From a shortcut, the widget or the reminder: what to open, for the game to take.
		String open = getIntent().getStringExtra(Shortcuts.EXTRA_OPEN);
		if (open != null) {
			Shortcuts.keepOpen(this, open);
		}
		Intent game = new Intent().setClassName(this, GAME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		startActivity(game);
		finish();
		overridePendingTransition(0, 0);
	}
}
