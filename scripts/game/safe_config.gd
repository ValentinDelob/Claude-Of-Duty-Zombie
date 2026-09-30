class_name SafeConfig
extends RefCounted
## Lecture sûre des fichiers de réglages (.cfg, format ConfigFile).
##
## `ConfigFile.load()` décode des Variant complets : `Object(Classe, ...)`
## instancie une classe du moteur et `Resource("chemin")` charge une ressource
## (un script .gd, une scène .tscn...), ce qui revient à EXÉCUTER du code venu
## du fichier. Un fichier de réglages modifié par un tiers (partagé, piégé)
## ne doit jamais pouvoir le faire : on lit le texte, on refuse tout
## constructeur hors de la liste des types de valeurs simples, puis on le
## donne à `ConfigFile.parse()`. Voir docs/SECURITY.md.

## Taille maximale d'un fichier de réglages (octets).
const MAX_BYTES := 1 << 20

## Constructeurs de valeurs sans effet de bord acceptés dans un fichier.
const SAFE_CONSTRUCTORS := [
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i",
	"Transform2D", "Transform3D", "Plane", "Quaternion", "AABB", "Basis", "Projection", "Color",
	"NodePath", "StringName", "Array", "Dictionary",
	"PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
	"PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array",
	"PackedColorArray", "PackedVector4Array",
	"inf", "nan",
]


## ConfigFile lu depuis `path`, ou null s'il est absent, trop gros, illisible
## ou s'il contient un objet ou une ressource (refus signalé dans le journal).
static func load_file(path: String) -> ConfigFile:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return null
	return parse_text(f.get_as_text(), path)


## ConfigFile à partir du texte, ou null (voir load_file).
static func parse_text(text: String, what := "") -> ConfigFile:
	var bad := unsafe_constructor(text)
	if bad != "":
		push_warning("[SafeConfig] %s ignoré : constructeur interdit « %s( »" % [what, bad])
		return null
	var cfg := ConfigFile.new()
	if cfg.parse(text) != OK:
		return null
	return cfg


## Premier constructeur interdit trouvé hors des chaînes et des commentaires
## (« Object », « Resource »...), ou "" si le texte est sûr.
static func unsafe_constructor(text: String) -> String:
	var code := strip_strings(text)
	var re := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	for m in re.search_all(code):
		var id := m.get_string(1)
		if not id in SAFE_CONSTRUCTORS:
			return id
	return ""


## Texte sans le contenu des chaînes ("...", échappements compris) ni les
## commentaires (« ; » ou « # » jusqu'à la fin de la ligne).
static func strip_strings(text: String) -> String:
	var out := PackedStringArray()
	var in_str := false
	var in_comment := false
	var escaped := false
	for c in text:
		if in_comment:
			if c == "\n":
				in_comment = false
				out.append(c)
			continue
		if in_str:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_str = false
				out.append(c)
			continue
		if c == "\"":
			in_str = true
			out.append(c)
		elif c == ";" or c == "#":
			in_comment = true
		else:
			out.append(c)
	return "".join(out)


# --------------------------------------------------------------------------
# Lecture typée : une valeur du mauvais type donne la valeur par défaut
# (au lieu d'une erreur de script qui laisserait les réglages à moitié lus).
# --------------------------------------------------------------------------

static func get_string(cfg: ConfigFile, section: String, key: String, default: String, max_len := 256) -> String:
	var v: Variant = cfg.get_value(section, key, default)
	return String(v).substr(0, max_len) if v is String or v is StringName else default


static func get_bool(cfg: ConfigFile, section: String, key: String, default: bool) -> bool:
	var v: Variant = cfg.get_value(section, key, default)
	return v if v is bool else default


static func get_int(cfg: ConfigFile, section: String, key: String, default: int, lo := -2147483648, hi := 2147483647) -> int:
	var v: Variant = cfg.get_value(section, key, default)
	if v is int:
		return clampi(v, lo, hi)
	if v is float and is_finite(v):
		# Borné AVANT la conversion : int(1e30) déborde (valeur la plus négative).
		return clampi(int(clampf(v, lo, hi)), lo, hi)
	return default


static func get_float(cfg: ConfigFile, section: String, key: String, default: float, lo := -1e9, hi := 1e9) -> float:
	var v: Variant = cfg.get_value(section, key, default)
	if (v is float or v is int) and is_finite(float(v)):
		return clampf(float(v), lo, hi)
	return default
