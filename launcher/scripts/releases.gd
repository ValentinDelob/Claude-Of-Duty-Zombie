extends RefCounted
## Versions publiées du jeu (releases GitHub du dépôt public) et notes de
## version destinées aux joueurs (changelogs/changelogs.json du dépôt).
##
## Sécurité (docs/SECURITY.md, « Lanceur ») : tout ce qui vient d'Internet est
## vérifié ici avant usage : adresses HTTPS de domaines GitHub seulement,
## numéros de version et noms de fichiers sans caractère dangereux (ils
## deviennent des chemins), sommes SHA-256 des exécutables, texte des notes
## échappé (pas de BBCode injecté), images bornées.

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
## Sommes SHA-256 des fichiers de la release (tools/release.sh), format de
## `sha256sum` : « <64 chiffres hexadécimaux>  <nom du fichier> » par ligne.
const SUMS_ASSET := "SHA256SUMS.txt"
const HEADERS := ["User-Agent: ClaudeOfDutyZombie-Launcher", "Accept: application/vnd.github+json"]

## Seuls domaines contactés, redirections comprises (téléchargements GitHub :
## github.com redirige vers objects / release-assets.githubusercontent.com).
const ALLOWED_HOSTS := ["api.github.com", "github.com", "objects.githubusercontent.com",
	"release-assets.githubusercontent.com", "raw.githubusercontent.com"]
## Les fichiers joints doivent venir des releases de CE dépôt.
const DOWNLOAD_PREFIX := "https://github.com/" + REPO + "/releases/download/"
const MAX_REDIRECTS := 5

## Tailles maximales des réponses (octets).
const MAX_API_BYTES := 8 << 20
const MAX_CHANGELOG_BYTES := 4 << 20
const MAX_IMAGE_BYTES := 8 << 20
const MAX_SMALL_BYTES := 64 << 10
const MAX_EXE_BYTES := 2 << 30
## Côté le plus grand accepté pour une capture des notes (pixels).
const MAX_IMAGE_SIDE := 4096

## Politique d'intégrité d'une version (integrity()).
const VERIFIED := "verified"   # SHA256SUMS.txt publié : somme vérifiée
const LEGACY := "legacy"       # version antérieure aux sommes : taille vérifiée
const REFUSED := "refused"     # version récente sans somme : refusée


## Liste de l'API GitHub -> versions jouables, de la plus récente à la plus
## ancienne : {tag, date, title, exe_url, exe_name, exe_size, launcher_url,
## launcher_name, launcher_size, launcher_version_url, sums_url}.
## Versions au numéro suspect et fichiers hors des releases du dépôt ignorés.
static func parse_releases(text: String) -> Array:
	var data: Variant = JSON.parse_string(text)
	var out: Array = []
	if not data is Array:
		return out
	for r in data:
		if not r is Dictionary or r.get("draft", false) or r.get("prerelease", false):
			continue
		var tag := _str(r.get("tag_name"))
		if not is_safe_tag(tag):
			continue
		var v := {"tag": tag, "date": _str(r.get("published_at")).left(10),
			"title": _title(_str(r.get("name")).left(300), tag), "exe_url": "", "exe_name": "", "exe_size": 0,
			"launcher_url": "", "launcher_name": "", "launcher_size": 0, "launcher_version_url": "", "sums_url": ""}
		var assets: Variant = r.get("assets", [])
		if not assets is Array:
			continue
		for a in assets:
			if not a is Dictionary:
				continue
			var n := _str(a.get("name"))
			var url := _str(a.get("browser_download_url"))
			if not is_safe_asset_name(n) or not is_asset_url(url, tag):
				continue
			var size := maxi(int(a.get("size")) if a.get("size") is int or a.get("size") is float else 0, 0)
			if GAME_ASSET_PREFIXES.any(func(p): return n.begins_with(p)) and n.ends_with(".exe"):
				v.exe_url = url
				v.exe_name = n
				v.exe_size = size
			elif n in LAUNCHER_ASSETS and (v.launcher_url == "" or n == LAUNCHER_ASSETS[0]):
				v.launcher_url = url
				v.launcher_name = n
				v.launcher_size = size
			elif n == LAUNCHER_VERSION_ASSET:
				v.launcher_version_url = url
			elif n == SUMS_ASSET:
				v.sums_url = url
		if v.exe_url != "":
			out.append(v)
	out.sort_custom(func(a, b): return newer(a.tag, b.tag))
	return out


## Champ texte de l'API : "" s'il est absent, null ou d'un autre type (GitHub
## renvoie « "name": null » pour une release sans titre ; une seule valeur
## inattendue ne doit pas vider toute la liste des versions).
static func _str(v: Variant) -> String:
	return v if v is String else ""


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


# --------------------------------------------------------------------------
# Vérifications (tout ce qui vient d'Internet)
# --------------------------------------------------------------------------

## Numéro de version utilisable comme nom de dossier : « v » puis 2 à 4
## nombres séparés par des points (jamais de « .. », « / » ni « \ »).
static func is_safe_tag(tag: String) -> bool:
	# « \z » : vraie fin du texte (« $ » accepterait un saut de ligne final).
	return RegEx.create_from_string("^v[0-9]{1,6}(\\.[0-9]{1,6}){1,3}\\z").search(tag) != null


## Nom de fichier joint à une release : lettres, chiffres, « . », « _ », « - ».
static func is_safe_asset_name(n: String) -> bool:
	return n.length() <= 100 and not n.begins_with(".") \
		and RegEx.create_from_string("^[A-Za-z0-9._-]+\\z").search(n) != null


## Nom d'une capture des notes (« v0.1.116/01.jpg ») : sous-dossiers permis,
## jamais « .. » ; .png, .jpg ou .jpeg seulement.
static func is_safe_image_name(n: String) -> bool:
	if n.length() > 120 or RegEx.create_from_string("^[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*\\z").search(n) == null:
		return false
	if ".." in n:
		return false
	var e := n.get_extension().to_lower()
	return e == "png" or e == "jpg" or e == "jpeg"


## Domaine d'une adresse HTTPS, "" si l'adresse n'est pas en HTTPS ou contient
## un identifiant (« user@ »), un port ou un caractère suspect.
static func url_host(url: String) -> String:
	if not url.begins_with("https://") or url.length() > 4096:
		return ""
	for c in url:
		if c.unicode_at(0) <= 32 or c == "\\" or c.unicode_at(0) == 127:
			return ""
	var rest := url.substr(8)
	var end := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < end:
			end = i
	var host := rest.substr(0, end).to_lower()
	if host.is_empty() or "@" in host or ":" in host:
		return ""
	return host


## Vrai si l'adresse peut être contactée (HTTPS, domaine autorisé).
static func is_allowed_url(url: String) -> bool:
	return url_host(url) in ALLOWED_HOSTS


## Fichier joint d'une release de ce dépôt (et de cette version). GitHub ne
## distingue pas la casse du nom du dépôt : la comparaison non plus.
static func is_asset_url(url: String, tag: String) -> bool:
	return is_allowed_url(url) and url.to_lower().begins_with((DOWNLOAD_PREFIX + tag + "/").to_lower())


## Valeur d'un en-tête HTTP (nom insensible à la casse), "" si absent.
static func header(headers: PackedStringArray, name: String) -> String:
	var key := name.to_lower() + ":"
	for h in headers:
		if h.to_lower().begins_with(key):
			return h.substr(key.length()).strip_edges()
	return ""


## SHA256SUMS.txt -> {nom de fichier: somme en minuscules}. Lignes invalides ignorées.
static func parse_sums(text: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("^([0-9a-fA-F]{64})[ \\t]+\\*?([^\\s]+)$")
	var lines := text.split("\n")
	for i in mini(lines.size(), 200):
		var m := re.search(lines[i].strip_edges())
		if m == null:
			continue
		var n := m.get_string(2).get_file()
		if is_safe_asset_name(n):
			out[n] = m.get_string(1).to_lower()
	return out


## Politique d'intégrité de la version `tag` parmi `versions` :
## - VERIFIED : la release publie SHA256SUMS.txt, l'exécutable doit avoir
##   exactement cette somme ;
## - LEGACY : release sans sommes ET plus ancienne que la première release qui
##   en a (versions publiées avant l'ajout des sommes) : acceptée, taille
##   vérifiée, comme avant ;
## - REFUSED : release sans sommes plus récente qu'une release qui en a
##   (anormal : fichier retiré ou release trafiquée) : jamais téléchargée.
static func integrity(versions: Array, tag: String) -> String:
	var first_verified := ""
	var has_sums := false
	for v in versions:
		if String(v.get("sums_url", "")) == "":
			continue
		if v.tag == tag:
			has_sums = true
		if first_verified == "" or newer(first_verified, v.tag):
			first_verified = v.tag
	if has_sums:
		return VERIFIED
	if first_verified == "" or newer(first_verified, tag):
		return LEGACY
	return REFUSED


## Texte affiché dans un RichTextLabel à BBCode : « [ » neutralisé (aucune
## balise [url], [img]... venue des notes publiées).
static func escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")


## Format d'une image d'après ses premiers octets : "png", "jpg" ou "".
static func image_format(b: PackedByteArray) -> String:
	if b.size() >= 8 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47:
		return "png"
	if b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		return "jpg"
	return ""


## Dimensions lues dans l'en-tête (PNG : IHDR ; JPEG : marqueur SOF), sans
## décoder l'image ; Vector2i(-1, -1) si illisible.
static func image_size(b: PackedByteArray) -> Vector2i:
	var f := image_format(b)
	if f == "png":
		if b.size() < 24:
			return Vector2i(-1, -1)
		return Vector2i(_be32(b, 16), _be32(b, 20))
	if f == "jpg":
		var o := 2
		while o + 9 < b.size():
			if b[o] != 0xFF:
				return Vector2i(-1, -1)
			var m := b[o + 1]
			if m == 0xFF:
				o += 1
				continue
			if m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
				return Vector2i(_be16(b, o + 7), _be16(b, o + 5))
			o += 2 + _be16(b, o + 2)
	return Vector2i(-1, -1)


## Image acceptable pour les notes : format reconnu, taille et dimensions bornées.
static func image_ok(b: PackedByteArray) -> bool:
	if b.size() > MAX_IMAGE_BYTES:
		return false
	var s := image_size(b)
	return s.x > 0 and s.y > 0 and s.x <= MAX_IMAGE_SIDE and s.y <= MAX_IMAGE_SIDE


static func _be16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


static func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


# --------------------------------------------------------------------------
# Notes de version
# --------------------------------------------------------------------------

## Notes d'une version dans une langue : {title, items: [String], images: [String]}.
## Sans notes pour cette version : titre de la release, aucune puce.
## Captures au nom suspect ignorées.
static func notes(changelogs: Dictionary, tag: String, lang: String, fallback_title := "") -> Dictionary:
	var versions: Variant = changelogs.get("versions", {})
	var e: Variant = versions.get(tag, {}) if versions is Dictionary else {}
	if not e is Dictionary:
		e = {}
	var items: Array = []
	var raw_items: Variant = e.get("items", [])
	for it in (raw_items if raw_items is Array else []):
		items.append(_pick(it, lang).left(2000))
	var images: Array = []
	var raw_images: Variant = e.get("images", [])
	for img in (raw_images if raw_images is Array else []):
		if img is String and is_safe_image_name(img) and images.size() < 12:
			images.append(img)
	return {
		"title": _pick(e.get("title", {}), lang).left(300) if e.has("title") else fallback_title,
		"items": items,
		"images": images,
		"found": not e.is_empty(),
	}


static func _pick(v, lang: String) -> String:
	if v is Dictionary:
		return _str(v.get(lang, v.get("fr", v.get("en", ""))))
	return String(v) if v is String else ""
