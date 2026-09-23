extends RefCounted
## Registers the game's translations with Godot's TranslationServer.
## Source strings in code are Russian; English (default) and Ukrainian are translation tables.
## To add a language: create scripts/i18n/<code>.gd with `const T := {...}` and list it below.

const EN = preload("res://scripts/i18n/en.gd")
const UK = preload("res://scripts/i18n/uk.gd")

## [code, native name] in the order shown in Settings.
const LANGS := [["en", "English"], ["uk", "Українська"], ["ru", "Русский"]]

static var _installed := false


static func install() -> void:
	if _installed:
		return
	_installed = true
	for spec in [["en", EN.T], ["uk", UK.T]]:
		var tr := Translation.new()
		tr.locale = spec[0]
		var table: Dictionary = spec[1]
		for k in table:
			tr.add_message(k, table[k])
		TranslationServer.add_translation(tr)
	# Russian is the source language, but it still needs a table of its own: without one the
	# server falls back to another locale (English) instead of returning the source string.
	var ru := Translation.new()
	ru.locale = "ru"
	for table in [EN.T, UK.T]:
		for k in table:
			ru.add_message(k, k)
	TranslationServer.add_translation(ru)


static func index_of(code: String) -> int:
	for i in LANGS.size():
		if LANGS[i][0] == code:
			return i
	return 0


## True when the current locale actually has an entry for this source string. The runtime i18n
## test uses it instead of comparing the result with the source: words spelled the same in
## Russian and Ukrainian ("БАЗА", "ПУСК", "ПРОМАХ") are translated, just not different.
static func has_entry(locale: String, s: String) -> bool:
	match locale.substr(0, 2):
		"en":
			return EN.T.has(s)
		"uk":
			return UK.T.has(s)
	return true


static func has_cyrillic(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false
