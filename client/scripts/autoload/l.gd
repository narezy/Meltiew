extends Node
## Localization: L.t("key") or L.t("key", [arg1, arg2]) using "{0}", "{1}" placeholders.
## English is the default; Russian is picked in Settings.

signal changed

const LANGS := {"en": "English", "ru": "Русский"}

var lang := "en"


func _ready() -> void:
	lang = str(Session.settings.get("lang", "en"))
	if not LANGS.has(lang):
		lang = "en"


func set_lang(code: String) -> void:
	if not LANGS.has(code) or code == lang:
		return
	lang = code
	Session.settings.lang = code
	Session.save_settings()
	changed.emit()


func t(key: String, args: Array = []) -> String:
	var entry: Variant = Strings.TABLE.get(key)
	var text := key
	if entry is Array:
		text = entry[1] if lang == "ru" and entry.size() > 1 else entry[0]
	for i in args.size():
		text = text.replace("{%d}" % i, str(args[i]))
	return text


## Picks "name_ru" over "name" (etc.) from API dictionaries when Russian is on.
func field(d: Dictionary, key: String) -> String:
	if lang == "ru" and d.has(key + "_ru"):
		return str(d[key + "_ru"])
	return str(d.get(key, ""))


func plural(n: int, key: String) -> String:
	# Table entries for plurals hold [en_one, en_many] and [ru_one, ru_few, ru_many] joined by "|".
	var forms := t(key).split("|")
	if lang == "ru" and forms.size() >= 3:
		var m10 := n % 10
		var m100 := n % 100
		if m10 == 1 and m100 != 11:
			return forms[0]
		if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
			return forms[1]
		return forms[2]
	return forms[0] if n == 1 or forms.size() < 2 else forms[1]
