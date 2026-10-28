package com.ascathelstan.crowns.icon;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.PackageManager;

/**
 * Switches the launcher icon between the classic one and the variants in the
 * plugin's manifest. Each icon is a launcher entry (activity alias) leading to
 * {@link Launch}; the classic one starts enabled and the variants disabled, and
 * switching enables one entry and disables the rest. Since the game never runs
 * in a task opened from an entry, switching doesn't close it.
 *
 * The game calls {@link #setIcon} from GDScript through JavaClassWrapper.
 */
public class AppIcon {
	/** The classic icon's entry, which replaces Godot's own (disabled in the manifest). */
	private static final String CLASSIC = "com.ascathelstan.crowns.icon.classic";
	/** Variant names, as the aliases com.ascathelstan.crowns.icon.<name> in the manifest. */
	private static final String[] VARIANTS = {"dark", "midnight", "forest", "contrast"};

	/**
	 * Shows the `name` icon: a variant, or "classic" (or anything else) for the
	 * classic one. Only entries in the wrong state change.
	 */
	public static void setIcon(Context context, String name) {
		PackageManager manager = context.getPackageManager();
		String chosen = CLASSIC;
		for (String variant : VARIANTS) {
			if (variant.equals(name)) {
				chosen = alias(variant);
			}
		}
		// The new entry first, so the launcher never has none.
		setEnabled(context, manager, chosen, true);
		if (!chosen.equals(CLASSIC)) {
			setEnabled(context, manager, CLASSIC, false);
		}
		for (String variant : VARIANTS) {
			if (!alias(variant).equals(chosen)) {
				setEnabled(context, manager, alias(variant), false);
			}
		}
	}

	private static String alias(String variant) {
		return "com.ascathelstan.crowns.icon." + variant;
	}

	/** Enabled, or back to the manifest's default: on for the classic entry, off for variants. */
	private static void setEnabled(Context context, PackageManager manager, String name, boolean enabled) {
		boolean byDefault = name.equals(CLASSIC);
		int state = enabled == byDefault ? PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
				: enabled ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED : PackageManager.COMPONENT_ENABLED_STATE_DISABLED;
		ComponentName component = new ComponentName(context, name);
		if (manager.getComponentEnabledSetting(component) != state) {
			manager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP);
		}
	}
}
