# Translating Crowns

Crowns is written in English. Each other language is one `.po` file in this folder,
named after its language code: `de.po` for German, `pt_BR.po` for Brazilian Portuguese.
The game finds the files by itself, so there's nothing else to register.

## Adding a language

1. Make a new `.po` file from `crowns.pot`. [Poedit](https://poedit.net) does this with
   *File → New from POT/PO file*, then asks for the language; any other gettext editor works too.
2. Translate the strings and save the file here as `<code>.po`.
3. Run the game and pick the language in **Settings → Language**. The language list
   shows each language by its own name, which is the first string in the file
   (context "language name"): translate "English" to your language's name, e.g. "Deutsch".

The game also follows the device's language when the player hasn't chosen one.

## Notes for translators

- Keep `%d` and `%s` as they are. They're filled with numbers and text in order.
- Words in braces, like `{group}` or `{month}`, are filled in by name. Keep them
  spelled the same, but move them wherever your grammar needs them.
- Hints build sentences from parts. `{group}` is a row, column or region, made
  from "row %d", "column %d" and "the %s region", where `%s` is a colour name.
  Choose wording for those parts that fits each sentence they appear in.
- Lines starting with `#.` in the file are notes about where a string appears.
- Strings with a plural form (`msgid_plural`) need every plural form your language
  has. Set the *Plural-Forms* header for your language; Poedit fills it in for you.
- Text that runs too long can overflow buttons on phones. If a word won't fit,
  a shorter one is better than an exact one.
- Godot draws letters from the device's fonts when the game's font lacks them, so
  most scripts display as they are. Arabic and Hebrew letters are bundled too, for
  the web build, which can't use the device's fonts.
- Right-to-left languages (Arabic, Hebrew, Persian, Urdu…) mirror the layout
  automatically: buttons, rows and the archive calendar run right to left. The
  puzzle board itself isn't mirrored, so "column 1" in hints is always the
  leftmost column, and a puzzle code shows the same board in every language.

## When the game's text changes

Rebuild the template, then update each language from it (Poedit: *Translation → Update from POT file*):

```
godot --headless --path . --script res://tools/update_pot.gd
```

A test fails when `crowns.pot` is out of date with the code.
