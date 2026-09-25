class_name Languages
extends RefCounted
## Every language a player can pick. The interface is translated to English and Russian;
## other languages fall back to English, but the choice is sent to the server (X-Lang)
## so places can show their own translations (studio "strings").
## Keep in sync with server/src/languages.js.

const LIST := [
	["en", "English"],
	["ru", "Русский"],
	["uk", "Українська"],
	["be", "Беларуская"],
	["kk", "Қазақша"],
	["uz", "Oʻzbekcha"],
	["ky", "Кыргызча"],
	["tg", "Тоҷикӣ"],
	["tk", "Türkmençe"],
	["az", "Azərbaycanca"],
	["hy", "Հայերեն"],
	["ka", "ქართული"],
	["mn", "Монгол"],
	["de", "Deutsch"],
	["fr", "Français"],
	["es", "Español"],
	["pt", "Português"],
	["it", "Italiano"],
	["nl", "Nederlands"],
	["pl", "Polski"],
	["cs", "Čeština"],
	["sk", "Slovenčina"],
	["sl", "Slovenščina"],
	["hr", "Hrvatski"],
	["sr", "Српски"],
	["bs", "Bosanski"],
	["bg", "Български"],
	["mk", "Македонски"],
	["ro", "Română"],
	["hu", "Magyar"],
	["el", "Ελληνικά"],
	["tr", "Türkçe"],
	["sv", "Svenska"],
	["no", "Norsk"],
	["da", "Dansk"],
	["fi", "Suomi"],
	["is", "Íslenska"],
	["et", "Eesti"],
	["lv", "Latviešu"],
	["lt", "Lietuvių"],
	["ga", "Gaeilge"],
	["cy", "Cymraeg"],
	["sq", "Shqip"],
	["ca", "Català"],
	["eu", "Euskara"],
	["gl", "Galego"],
	["mt", "Malti"],
	["he", "עברית"],
	["ar", "العربية"],
	["fa", "فارسی"],
	["ur", "اردو"],
	["hi", "हिन्दी"],
	["bn", "বাংলা"],
	["pa", "ਪੰਜਾਬੀ"],
	["gu", "ગુજરાતી"],
	["mr", "मराठी"],
	["ta", "தமிழ்"],
	["te", "తెలుగు"],
	["kn", "ಕನ್ನಡ"],
	["ml", "മലയാളം"],
	["si", "සිංහල"],
	["ne", "नेपाली"],
	["th", "ไทย"],
	["vi", "Tiếng Việt"],
	["id", "Bahasa Indonesia"],
	["ms", "Bahasa Melayu"],
	["tl", "Filipino"],
	["my", "မြန်မာ"],
	["km", "ខ្មែរ"],
	["lo", "ລາວ"],
	["zh", "中文"],
	["ja", "日本語"],
	["ko", "한국어"],
	["sw", "Kiswahili"],
	["am", "አማርኛ"],
	["yo", "Yorùbá"],
	["ha", "Hausa"],
	["zu", "isiZulu"],
	["af", "Afrikaans"],
	["eo", "Esperanto"],
	["la", "Latina"],
]


static func name_of(code: String) -> String:
	for l in LIST:
		if l[0] == code:
			return l[1]
	return code


static func has(code: String) -> bool:
	for l in LIST:
		if l[0] == code:
			return true
	return false
