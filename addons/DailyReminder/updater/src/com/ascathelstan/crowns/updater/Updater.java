package com.ascathelstan.crowns.updater;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Installs an update the game has downloaded, through Android's own installer,
 * which always asks the player to confirm. Only in the APK published outside
 * Google Play.
 *
 * The game calls these from GDScript through JavaClassWrapper.
 */
public class Updater {
	/** Whether the player has let Crowns install apps ("Install unknown apps"). */
	public static boolean canInstall(Context context) {
		return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.getPackageManager().canRequestPackageInstalls();
	}

	/** Opens the system setting to let Crowns install apps. */
	public static void openInstallSettings(Context context) {
		Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.getPackageName()))
				.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		context.startActivity(intent);
	}

	/**
	 * Hands the APK at `path` to Android's installer, which shows its confirmation
	 * (see {@link InstallStatus}). Returns "" once handed over, or what went wrong.
	 */
	public static String install(Context context, String path) {
		PackageInstaller installer = context.getPackageManager().getPackageInstaller();
		PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
		params.setAppPackageName(context.getPackageName());
		try {
			int id = installer.createSession(params);
			try (PackageInstaller.Session session = installer.openSession(id)) {
				try (InputStream in = new FileInputStream(path); OutputStream out = session.openWrite("update.apk", 0, -1)) {
					byte[] buffer = new byte[65536];
					int read;
					while ((read = in.read(buffer)) != -1) {
						out.write(buffer, 0, read);
					}
					session.fsync(out);
				}
				// Mutable so the installer can add its status; explicit, so that's allowed.
				int flags = PendingIntent.FLAG_UPDATE_CURRENT
						| (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0);
				PendingIntent status = PendingIntent.getBroadcast(context, id, new Intent(context, InstallStatus.class), flags);
				session.commit(status.getIntentSender());
			}
			return "";
		} catch (IOException | RuntimeException e) {
			return String.valueOf(e.getMessage());
		}
	}
}
