extends RefCounted
## Versions publiées du jeu (releases GitHub du dépôt public) et notes de
## version destinées aux joueurs (changelogs/changelogs.json du dépôt).

const REPO := "ValentinDelob/Claude-Of-Duty-Zombie"
const API_URL := "https://api.github.com/repos/" + REPO + "/releases?per_page=100"
const RAW_URL := "https://raw.githubusercontent.com/" + REPO + "/main/"
const CHANGELOG_URL := RAW_URL + "changelogs/changelogs.json"
const IMAGE_URL := RAW_URL + "changelogs/img/"
## Fichiers joints aux releases (le jeu s'appelait « Call of Claude Zombie »
## jusqu'à v0.1.126 : les anciens noms restent reconnus).
const GAME_ASSET_PREFIXES := ["ClaudeOfDutyZombie-v", "CallOfClaudeZombie-v"]
const LAUNCHER_ASSETS := ["ClaudeOfDutyZombie-Launcher.exe", "CallOfClaudeZombie-Launcher.exe"]
const LAUNCHER_VERSION_ASSET := "launcher_version.txt"
const HEADERS := ["User-Agent: ClaudeOfDutyZombie-Launcher", "Accept: application/vnd.github+json"]


## Liste de l'API GitHub -> versions jouables, de la plus récente à la plus
## ancienne : {tag, date, title, exe_url, exe_size, launcher_url, launcher_version_url}.
static func parse_releases(text: String) -> Array:
	var data = JSON.parse_string(text)
	var out: Array = []
	if not data is Array:
		return out
	for r in data:
		if not r is Dictionary or r.get("draft", false) or r.get("prerelease", false):
			continue
		var tag := String(r.get("tag_name", ""))
		var v := {"tag": tag, "date": String(r.get("published_at", "")).left(10),
			"title": _title(String(r.get("name", "")), tag), "exe_url": "", "exe_size": 0,
			"launcher_url": "", "launcher_version_url": ""}
		for a in r.get("assets", []):
			var n := String(a.get("name", ""))
			var url := String(a.get("browser_download_url", ""))
			if GAME_ASSET_PREFIXES.any(func(p): return n.begins_with(p)) and n.ends_with(".exe"):
				v.exe_url = url
				v.exe_size = int(a.get("size", 0))
			elif n in LAUNCHER_ASSETS and (v.launcher_url == "" or n == LAUNCHER_ASSETS[0]):
				v.launcher_url = url
			elif n == LAUNCHER_VERSION_ASSET:
				v.launcher_version_url = url
		if tag != "" and v.exe_url != "":
			out.append(v)
	out.sort_custom(func(a, b): return newer(a.tag, b.tag))
	return out


## Titre GitHub « v0.1.116 — feat: ... » : sans le numéro ni le préfixe technique.
static func _title(name: String, tag: String) -> String:
	var t := name.trim_prefix(tag).strip_edges().trim_prefix("—").strip_edges()
	var colon := t.find(": ")
	return t.substr(colon + 2) if colon >= 0 and colon < 12 else t


## Parties numériques d'une version (« v0.1.116 » -> [0, 1, 116]).
static func version_key(tag: String) -> Array:
	var out: Array = []
	for p in tag.trim_prefix("v").split("."):
		out.append(int(p) if p.is_valid_int() else 0)
	return out


## Vrai si `a` est plus récente que `b`.
static func newer(a: String, b: String) -> bool:
	var ka := version_key(a)
	var kb := version_key(b)
	for i in maxi(ka.size(), kb.size()):
		var x: int = ka[i] if i < ka.size() else 0
		var y: int = kb[i] if i < kb.size() else 0
		if x != y:
			return x > y
	return false


## Notes d'une version dans une langue : {title, items: [String], images: [String]}.
## Sans notes pour cette version : titre de la release, aucune puce.
static func notes(changelogs: Dictionary, tag: String, lang: String, fallback_title := "") -> Dictionary:
	var e: Dictionary = changelogs.get("versions", {}).get(tag, {})
	var items: Array = []
	for it in e.get("items", []):
		items.append(_pick(it, lang))
	return {
		"title": _pick(e.get("title", {}), lang) if e.has("title") else fallback_title,
		"items": items,
		"images": e.get("images", []),
		"found": not e.is_empty(),
	}


static func _pick(v, lang: String) -> String:
	if v is Dictionary:
		return String(v.get(lang, v.get("fr", v.get("en", ""))))
	return String(v)
