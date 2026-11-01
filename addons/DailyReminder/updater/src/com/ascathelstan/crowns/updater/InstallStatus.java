package com.ascathelstan.crowns.updater;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;

/**
 * Hears back from Android's installer. When it needs the player's confirmation,
 * which it always does for an app installing an update to itself, this shows it.
 * If the player installs the update, Android restarts the game on the new version.
 */
public class InstallStatus extends BroadcastReceiver {
	@Override
	public void onReceive(Context context, Intent intent) {
		if (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
				== PackageInstaller.STATUS_PENDING_USER_ACTION) {
			Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
			if (confirm != null) {
				context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
			}
		}
	}
}
