class_name MapTextureLib
extends RefCounted
## TEXTURES DE LA CARTE (format 16, docs/MAP_AUTHORING.md § Textures de la
## carte) : images importées du disque, rangées DANS le dossier de la carte, à
## côté des cinq JSON :
##   textures/<tid>/texture.json   définition (nom, taille du motif...)
##   textures/<tid>/image.png      l'image (ou image.jpg)
##   textures/<tid>/normal.png     carte des normales facultative (ou normal.jpg)
## Une pièce ou une zone la cite dans ses champs de surface existants
## (« surface_sol », « surface_murs », « surface_plafond » d'une pièce ;
## « sol », « murs », « plafond » d'une zone) par « map:<tid> », à la place
## d'une clé de WorldLook.SURFACES.
##
## texture.json : {format, nom {fr, en}, taille (m : largeur d'une répétition
## de l'image ; la hauteur suit les proportions de l'image), rugosite (0 à 1),
## metal (0 à 1), teinte (#rrggbb, multiplie l'image), couleur (#rrggbb :
## couleur moyenne, calculée à l'import : invités d'une session, aperçus)}.
## Réglages facultatifs jamais écrits à leur valeur par défaut (DEFAULTS).
##
## Dans les textes d'une carte (EditorMap.file_texts, paquet réseau, cache,
## archive), une texture est une entrée de plus : « textures/<tid>/texture.json »
## (texte JSON) et « textures/<tid>/image.png » (octets en base64 ; sur le
## disque et dans une archive : le fichier binaire).
##
## AUCUN QUOTA de nombre ni de taille : le concepteur gère les ressources de sa
## carte. Seule borne : le côté d'une image (16384 px, la plus grande texture
## que le moteur crée).
##
## Sûreté (cartes reçues d'autres joueurs, CustomMapGuard) : définition
## vérifiée clé par clé (check_def), image vérifiée (signature PNG / JPEG,
## côtés lus dans l'en-tête et bornés AVANT tout décodage, puis vrai décodage
## par Image depuis les octets : jamais load(), jamais de ressource Godot).
## En jeu : Image.load_png_from_buffer / load_jpg_from_buffer -> image réduite
## à 20 pixels par mètre (pixelate : un pixel = un cube de 5 cm, le fichier
## n'est pas touché) -> ImageTexture (mipmaps) -> matériau
## (assets/shaders/map_texture.gdshader : image répétée en coordonnées monde,
## au plus proche, même échelle sur le sol, les murs et le plafond).
## Texture absente ou illisible : surface par défaut (zone ou jeu), avec un
## avertissement du validateur (MapRaster).

const DIR := "textures"
const DEF_FILE := "texture.json"
const IMAGE_FILES := ["image.png", "image.jpg"]
const NORMAL_FILES := ["normal.png", "normal.jpg"]
## Préfixe d'une texture de la carte dans un champ de surface.
const REF := "map:"
## Clé de matériau d'une texture de la carte dans la description du jeu
## (MapLayoutExport, noms de nœuds « <matériau>__<pièce>__<type> » :
## jamais « : » dans un nom de nœud).
const MAT_PREFIX := "tex-"
const FORMAT := 1
const MAX_TID := 32
## Plus grand côté d'une image (px) : la plus grande texture du moteur.
const MAX_SIDE := 16384
## Taille du motif (m) : largeur d'une répétition de l'image.
const SIZE := [0.05, 100.0]
const DEFAULTS := {"rugosite": 0.85, "metal": 0.0, "teinte": "#ffffff"}
const DEFAULT_SIZE := 2.0
## Borne de lecture de texture.json (un texte de quelques centaines d'octets).
const MAX_DEF_BYTES := 64 * 1024
const SHADER := preload("res://assets/shaders/map_texture.gdshader")


# ------------------------------------------------------------------ noms et clés

## Identifiant de texture (nom de son dossier) : 1 à 32 caractères parmi a-z,
## 0-9 et _, sans « __ » ni _ au début ou à la fin (le nom de matériau
## « tex-<tid> » se coupe sur « __ » dans les noms de nœuds).
static func tid_ok(s: Variant) -> bool:
	if not (s is String and String(s).length() <= MAX_TID and EditorMap.valid_id(s)):
		return false
	var t := String(s)
	return not t.contains("__") and not t.begins_with("_") and not t.ends_with("_")


static func ref(tid: String) -> String:
	return REF + tid


## Identifiant de texture d'un champ de surface (« map:<tid> ») ; "" sinon.
static func tid_of(v: Variant) -> String:
	if v is String and String(v).begins_with(REF):
		var tid := String(v).substr(REF.length())
		return tid if tid_ok(tid) else ""
	return ""


static func is_ref(v: Variant) -> bool:
	return tid_of(v) != ""


static func mat_key(tid: String) -> String:
	return MAT_PREFIX + tid


## Identifiant de texture d'une clé de matériau du jeu (« tex-<tid> ») ; "" sinon.
static func tid_of_mat(key: String) -> String:
	if key.begins_with(MAT_PREFIX):
		var tid := key.substr(MAT_PREFIX.length())
		return tid if tid_ok(tid) else ""
	return ""


static func def_key(tid: String) -> String:
	return "%s/%s/%s" % [DIR, tid, DEF_FILE]


static func file_key(tid: String, file: String) -> String:
	return "%s/%s/%s" % [DIR, tid, file]


## Clé de texte d'une carte -> [tid, fichier] si c'est une entrée de texture
## admise (textures/<tid>/texture.json, image.png|jpg, normal.png|jpg), [] sinon.
static func parse_key(k: Variant) -> Array:
	if not k is String:
		return []
	var parts := String(k).split("/")
	if parts.size() != 3 or parts[0] != DIR or not tid_ok(parts[1]) or not (parts[2] == DEF_FILE or parts[2] in IMAGE_FILES or parts[2] in NORMAL_FILES):
		return []
	return [parts[1], parts[2]]


## Entrée binaire (image : base64 en mémoire, fichier binaire sur le disque) ?
static func is_binary_key(k: Variant) -> bool:
	var pk := parse_key(k)
	return not pk.is_empty() and pk[1] != DEF_FILE


## Nouvel identifiant libre tiré d'un nom (EditorMap.slug, 24 caractères).
static func new_tid(name: String, used: Dictionary) -> String:
	var base := EditorMap.slug(name).left(24).trim_suffix("_")
	if base == "" or base == "carte":
		base = "texture"
	var tid := base
	var n := 2
	while used.has(tid):
		tid = "%s_%d" % [base, n]
		n += 1
	return tid


## Fichier d'image d'après la signature des octets : « image.png »,
## « image.jpg » ou "" (ni PNG ni JPEG). `normal` : « normal.png »...
static func file_for(b: PackedByteArray, normal := false) -> String:
	var ext := ""
	if b.size() >= 8 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47 and b[4] == 0x0D and b[5] == 0x0A and b[6] == 0x1A and b[7] == 0x0A:
		ext = "png"
	elif b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		ext = "jpg"
	if ext == "":
		return ""
	return ("normal." if normal else "image.") + ext


# ------------------------------------------------------------------ définition

static func _num(v: Variant, lo: float, hi: float) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


static func _color_ok(c: Variant) -> bool:
	return c is String and String(c).length() == 7 and String(c).begins_with("#") and String(c).substr(1).is_valid_hex_number()


## Contrôle d'une définition (texture.json lu) ; [fr, en] si elle est refusée,
## [] sinon. Liste blanche des clés et des valeurs.
static func check_def(d: Variant) -> Array:
	if not d is Dictionary:
		return ["texture.json : objet JSON attendu", "texture.json: JSON object expected"]
	for k in d:
		if not (k is String and k in ["format", "nom", "taille", "rugosite", "metal", "teinte", "couleur"]):
			return ["texture.json : clé inconnue « %s »" % CustomMapGuard.clean_display(str(k), 24), "texture.json: unknown key \"%s\"" % CustomMapGuard.clean_display(str(k), 24)]
	if d.has("format") and not (_num(d.format, 1, FORMAT) and float(d.format) == floorf(float(d.format))):
		return ["texture.json : format inconnu", "texture.json: unknown format"]
	var nom: Variant = d.get("nom")
	if not (nom is Dictionary and nom.size() >= 1 and nom.size() <= 2):
		return ["texture.json : nom {fr, en} attendu", "texture.json: name {fr, en} expected"]
	for k in nom:
		if not (k in ["fr", "en"] and nom[k] is String and String(nom[k]).strip_edges() != "" and CustomMapGuard.name_ok(nom[k])):
			return ["texture.json : nom refusé", "texture.json: name refused"]
	if not _num(d.get("taille"), SIZE[0], SIZE[1]):
		return ["texture.json : taille du motif « taille » de %s à %s m attendue" % [str(SIZE[0]), str(SIZE[1])],
			"texture.json: pattern size \"taille\" from %s to %s m expected" % [str(SIZE[0]), str(SIZE[1])]]
	for k in ["rugosite", "metal"]:
		if d.has(k) and not _num(d[k], 0.0, 1.0):
			return ["texture.json : « %s » de 0 à 1 attendu" % k, "texture.json: \"%s\" from 0 to 1 expected" % k]
	for k in ["teinte", "couleur"]:
		if d.has(k) and not _color_ok(d[k]):
			return ["texture.json : « %s » #rrggbb attendue" % k, "texture.json: \"%s\" #rrggbb expected" % k]
	return []


## Définition nettoyée (nombres arrondis, valeurs par défaut retirées) ; {} si
## elle est refusée (check_def).
static func sanitize(d: Variant) -> Dictionary:
	if not check_def(d).is_empty():
		return {}
	var out := {"format": FORMAT, "nom": (d.nom as Dictionary).duplicate(), "taille": snappedf(float(d.taille), 0.01)}
	for k in ["rugosite", "metal"]:
		if d.has(k) and absf(float(d[k]) - float(DEFAULTS[k])) > 0.0001:
			out[k] = snappedf(float(d[k]), 0.01)
	if d.has("teinte") and String(d.teinte).to_lower() != DEFAULTS.teinte:
		out["teinte"] = String(d.teinte).to_lower()
	if d.has("couleur"):
		out["couleur"] = String(d.couleur).to_lower()
	return out


## Texte de texture.json (JSON lisible ; nombres entiers sans décimale).
static func def_text(d: Dictionary) -> String:
	return EditorMap.dump(EditorMap._ints(d))


static func name_of(d: Dictionary) -> String:
	var n: Dictionary = d.get("nom", {})
	return Lang.t(String(n.get("fr", n.get("en", "?"))), String(n.get("en", n.get("fr", "?"))))


## Couleur moyenne (couleur de repli d'un aperçu sans image), sinon gris.
static func color_of(d: Dictionary) -> Color:
	var c := String(d.get("couleur", "#808080"))
	return Color.html(c) if Color.html_is_valid(c) else Color(0.5, 0.5, 0.5)


# ------------------------------------------------------------------ images

## Côtés d'une image PNG ou JPEG lus dans son en-tête (MapPrefabLib.image_size).
static func image_size(b: PackedByteArray) -> Vector2i:
	return MapPrefabLib.image_size(b.slice(0, mini(b.size(), 1 << 20)))


## Contrôle d'une image SANS la décoder : signature conforme au nom de fichier
## (« .png » / « .jpg »), côtés lus dans l'en-tête, de 1 à MAX_SIDE px.
## [fr, en] si refusée, [] sinon.
static func check_header(b: PackedByteArray, file: String) -> Array:
	var want := file_for(b, file.begins_with("normal."))
	if want == "" or want != file:
		return ["%s : pas une image %s" % [file, "PNG" if file.ends_with(".png") else "JPEG"], "%s: not a %s image" % [file, "PNG" if file.ends_with(".png") else "JPEG"]]
	var s := image_size(b)
	if s.x <= 0 or s.y <= 0:
		return ["%s : en-tête d'image illisible" % file, "%s: unreadable image header" % file]
	if s.x > MAX_SIDE or s.y > MAX_SIDE:
		return ["%s : image trop grande (%d × %d px, %d px de côté au plus)" % [file, s.x, s.y, MAX_SIDE],
			"%s: image too large (%d × %d px, %d px per side at most)" % [file, s.x, s.y, MAX_SIDE]]
	if not (_png_complete(b) if file.ends_with(".png") else _jpg_complete(b)):
		return ["%s : image tronquée ou abîmée" % file, "%s: truncated or damaged image" % file]
	return []


## PNG entier : blocs (longueur, type, données, CRC) tous dans le fichier, au
## moins un IDAT, IEND en dernier. Évite de donner au décodeur du moteur un
## fichier tronqué (il l'écrirait en erreur au journal).
static func _png_complete(b: PackedByteArray) -> bool:
	var i := 8
	var idat := false
	while i + 12 <= b.size():
		var n := (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]
		var kind := b.slice(i + 4, i + 8).get_string_from_ascii()
		if n < 0 or i + 12 + n > b.size():
			return false
		if kind == "IDAT":
			idat = true
		i += 12 + n
		if kind == "IEND":
			return idat
	return false


## JPEG entier : marqueur de fin (FF D9) parmi les derniers octets (certains
## fichiers ont quelques octets de bourrage après).
static func _jpg_complete(b: PackedByteArray) -> bool:
	for i in range(b.size() - 2, maxi(b.size() - 66, 1), -1):
		if b[i] == 0xFF and b[i + 1] == 0xD9:
			return true
	return false


## Image décodée depuis ses octets (vrai décodage par le moteur, après
## check_header) ; null si refusée ou illisible.
static func decode(b: PackedByteArray, file: String) -> Image:
	if not check_header(b, file).is_empty():
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(b) if file.ends_with(".png") else img.load_jpg_from_buffer(b)
	if err != OK or img.is_empty() or img.get_width() > MAX_SIDE or img.get_height() > MAX_SIDE:
		return null
	return img


## Contrôle complet (réception) : en-tête puis décodage. [fr, en] ou [].
static func check_image(b: PackedByteArray, file: String) -> Array:
	var bad := check_header(b, file)
	if not bad.is_empty():
		return bad
	if decode(b, file) == null:
		return ["%s : image illisible (décodage refusé)" % file, "%s: unreadable image (decoding refused)" % file]
	return []


## Couleur moyenne d'une image (#rrggbb), pour les aperçus sans image.
static func average_color(img: Image) -> String:
	var small := img.duplicate() as Image
	if small.is_compressed():
		return "#808080"
	small.convert(Image.FORMAT_RGB8)
	small.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0)
	for y in 8:
		for x in 8:
			sum += small.get_pixel(x, y)
	sum /= 64.0
	sum.a = 1.0
	return "#" + sum.to_html(false)


## Aperçu (icône des listes) : l'image réduite en `w` × `h` px ; `size_m` >
## 0 : comme en jeu (pixelate, un pixel = 5 cm), un morceau de `w` × `h`
## pixels (2 m × 1,2 m) répété depuis le coin, comme les surfaces du jeu
## (MapIcons.surface_texture).
static func thumbnail(img: Image, w := 40, h := 24, size_m := 0.0) -> ImageTexture:
	if size_m > 0.0:
		var p := pixelate(img, size_m)
		p.convert(Image.FORMAT_RGB8)
		var out := Image.create(w, h, false, Image.FORMAT_RGB8)
		for y in h:
			for x in w:
				out.set_pixel(x, y, p.get_pixel(x % p.get_width(), y % p.get_height()))
		return ImageTexture.create_from_image(out)
	var t := img.duplicate() as Image
	t.convert(Image.FORMAT_RGB8)
	t.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(t)


# ------------------------------------------------------------------ texture de la carte (EditorMap)

## Fichier d'image (« image.png » / « image.jpg ») de la texture `tid` dans
## `files` (clé de texte -> base64), "" s'il manque.
static func image_file(files: Dictionary, tid: String, normal := false) -> String:
	for f in (NORMAL_FILES if normal else IMAGE_FILES):
		if files.has(file_key(tid, f)):
			return f
	return ""


## Octets de l'image (ou de la carte des normales) de la texture `tid`.
static func image_bytes(files: Dictionary, tid: String, normal := false) -> PackedByteArray:
	var f := image_file(files, tid, normal)
	return Marshalls.base64_to_raw(String(files[file_key(tid, f)])) if f != "" else PackedByteArray()


## Texture utilisable : définition et image présentes.
static func usable(doc: EditorMap, tid: String) -> bool:
	return doc.textures.has(tid) and image_file(doc.texture_files, tid) != ""


## Ajoute (ou remplace) la texture `tid` ; `image` / `normal` : octets PNG ou
## JPEG (vides : inchangés ; `drop_normal` retire la carte des normales).
## Contrôle de l'en-tête seulement (l'appelant a décodé l'image importée).
static func set_texture(doc: EditorMap, tid: String, def: Dictionary, image := PackedByteArray(), normal := PackedByteArray(), drop_normal := false) -> bool:
	var s := sanitize(def)
	if s.is_empty() or not tid_ok(tid):
		return false
	var files := {}
	for pair in [[image, false], [normal, true]]:
		var b: PackedByteArray = pair[0]
		if b.is_empty():
			continue
		var f := file_for(b, pair[1])
		if f == "" or not check_header(b, f).is_empty():
			return false
		files[pair[1]] = [f, b]
	if not files.has(false) and image_file(doc.texture_files, tid) == "":
		return false
	for normal_side in files:
		for f in (NORMAL_FILES if normal_side else IMAGE_FILES):
			doc.texture_files.erase(file_key(tid, f))
		doc.texture_files[file_key(tid, files[normal_side][0])] = Marshalls.raw_to_base64(files[normal_side][1])
	if drop_normal and not files.has(true):
		for f in NORMAL_FILES:
			doc.texture_files.erase(file_key(tid, f))
	doc.textures[tid] = s
	return true


## Retire la texture `tid` de la bibliothèque. Ses images restent en mémoire
## (une annulation qui la rendrait les retrouve) mais ne sont plus écrites :
## file_texts n'écrit que les images des textures définies.
static func remove(doc: EditorMap, tid: String) -> void:
	doc.textures.erase(tid)


## Où la texture `tid` est utilisée : [{id, coll (« pieces » / « zones »), cle}].
static func users(doc: EditorMap, tid: String) -> Array:
	var r := ref(tid)
	var out := []
	for p in doc.pieces:
		for k in ["surface_sol", "surface_murs", "surface_plafond"]:
			if String(p.get(k, "")) == r:
				out.append({"id": String(p.get("id", "")), "coll": "pieces", "cle": k})
	for z in doc.zones:
		for k in ["sol", "murs", "plafond"]:
			if String(z.get(k, "")) == r:
				out.append({"id": String(z.get("id", "")), "coll": "zones", "cle": k})
	return out


## Définitions de textures d'un instantané (EditorMap.to_dict, session),
## contrôlées une par une.
static func read_snapshot(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for tid in v:
			if tid_ok(tid):
				var def := sanitize(v[tid])
				if not def.is_empty():
					out[tid] = def
	return out


## Entrées de texture des textes de la carte : texture.json de chaque texture
## définie, et ses images (seulement celles des textures définies).
static func texts_of(doc: EditorMap) -> Dictionary:
	var out := {}
	var ids := doc.textures.keys()
	ids.sort()
	for tid in ids:
		out[def_key(tid)] = def_text(doc.textures[tid])
		for f in IMAGE_FILES + NORMAL_FILES:
			var k := file_key(tid, f)
			if doc.texture_files.has(k):
				out[k] = String(doc.texture_files[k])
	return out


## Lit les entrées de texture parmi des textes (EditorMap.from_texts) ;
## définition illisible : texture ignorée avec un message (load_errors) ;
## image absente : texture gardée (repli sur la surface par défaut,
## avertissement du validateur).
static func read_texts(doc: EditorMap, texts: Dictionary) -> void:
	doc.textures = {}
	doc.texture_files = {}
	var keys := texts.keys().filter(func(k): return not parse_key(k).is_empty())
	keys.sort()
	for k in keys:
		var pk := parse_key(k)
		var tid := String(pk[0])
		if pk[1] != DEF_FILE:
			if texts[k] is String:
				doc.texture_files[k] = String(texts[k])
			continue
		var j := JSON.new()
		var bad: Array = ["JSON illisible", "unreadable JSON"] if not texts[k] is String or j.parse(String(texts[k])) != OK else check_def(j.data)
		if not bad.is_empty():
			doc.load_errors.append(["texture %s ignorée : %s" % [tid, bad[0]], "texture %s ignored: %s" % [tid, bad[1]]])
			continue
		doc.textures[tid] = sanitize(j.data)
	# Images sans définition : oubliées (jamais réécrites).
	for k in doc.texture_files.keys():
		if not doc.textures.has(String(parse_key(k)[0])):
			doc.texture_files.erase(k)


# ------------------------------------------------------------------ dossier

## Entrées de texture d'un dossier de carte (textures/<tid>/...) : {texts:
## {clé: texte (texture.json) ou base64 (image)}, reasons}. Seuls les fichiers
## admis sont lus ; les dossiers au nom non admis sont ignorés.
static func read_dir(dir: String) -> Dictionary:
	var texts := {}
	var reasons := []
	var root := dir.path_join(DIR)
	if not DirAccess.dir_exists_absolute(root):
		return {"texts": texts, "reasons": reasons}
	var tids := Array(DirAccess.get_directories_at(root)).filter(func(t): return tid_ok(t))
	tids.sort()
	for tid in tids:
		var td := root.path_join(tid)
		if not FileAccess.file_exists(td.path_join(DEF_FILE)):
			continue
		var t: Variant = EditorMap.read_text(td.path_join(DEF_FILE), MAX_DEF_BYTES)
		if t == null:
			reasons.append(["texture %s : texture.json trop gros ou illisible" % tid, "texture %s: texture.json too big or unreadable" % tid])
			continue
		texts[def_key(tid)] = t
		for f in IMAGE_FILES + NORMAL_FILES:
			var p := td.path_join(f)
			if FileAccess.file_exists(p):
				var b := FileAccess.get_file_as_bytes(p)
				if not b.is_empty():
					texts[file_key(tid, f)] = Marshalls.raw_to_base64(b)
	return {"texts": texts, "reasons": reasons}


## Écrit les entrées de texture (`texts` : clé -> texte ou base64) dans le
## dossier de la carte et retire ce qui n'y est plus (seulement des dossiers au
## nom admis, et seulement leurs fichiers admis). Une image déjà là,
## identique (même SHA-256), n'est pas réécrite.
static func write_dir(dir: String, texts: Dictionary) -> Error:
	var root := dir.path_join(DIR)
	var keep := {}
	for k in texts:
		var pk := parse_key(k)
		if not pk.is_empty():
			keep.get_or_add(pk[0], {})[pk[1]] = true
	if DirAccess.dir_exists_absolute(root):
		for t in DirAccess.get_directories_at(root):
			if not tid_ok(t):
				continue
			if not keep.has(t):
				remove_texture_dir(root.path_join(t))
				continue
			# Image remplacée (png -> jpg) ou carte des normales retirée.
			for f in IMAGE_FILES + NORMAL_FILES:
				if not (keep[t] as Dictionary).has(f) and FileAccess.file_exists(root.path_join(t).path_join(f)):
					DirAccess.remove_absolute(root.path_join(t).path_join(f))
	if keep.is_empty():
		if DirAccess.dir_exists_absolute(root) and DirAccess.get_directories_at(root).is_empty() and DirAccess.get_files_at(root).is_empty():
			DirAccess.remove_absolute(root)
		return OK
	for k in texts:
		var pk := parse_key(k)
		if pk.is_empty():
			continue
		var td := root.path_join(String(pk[0]))
		var err := DirAccess.make_dir_recursive_absolute(td)
		if err != OK and not DirAccess.dir_exists_absolute(td):
			return err
		var path := td.path_join(String(pk[1]))
		if pk[1] != DEF_FILE:
			var bytes := Marshalls.base64_to_raw(String(texts[k]))
			if FileAccess.file_exists(path) and FileAccess.get_size(path) == bytes.size() \
					and FileAccess.get_sha256(path) == CustomMapGuard.sha256_hex(bytes):
				continue
			var fb := FileAccess.open(path, FileAccess.WRITE)
			if fb == null:
				return FileAccess.get_open_error()
			fb.store_buffer(bytes)
			fb.close()
		else:
			var ft := FileAccess.open(path, FileAccess.WRITE)
			if ft == null:
				return FileAccess.get_open_error()
			ft.store_string(String(texts[k]))
			ft.close()
	return OK


## Efface un dossier de texture : ses fichiers admis, puis le dossier s'il est vide.
static func remove_texture_dir(td: String) -> void:
	for f in [DEF_FILE] + IMAGE_FILES + NORMAL_FILES:
		if FileAccess.file_exists(td.path_join(f)):
			DirAccess.remove_absolute(td.path_join(f))
	DirAccess.remove_absolute(td)


## Efface tout le dossier textures/ d'une carte (cache : carte retirée).
static func remove_all(dir: String) -> void:
	var root := dir.path_join(DIR)
	if not DirAccess.dir_exists_absolute(root):
		return
	for t in DirAccess.get_directories_at(root):
		if tid_ok(t):
			remove_texture_dir(root.path_join(t))
	DirAccess.remove_absolute(root)


# ------------------------------------------------------------------ contrôle des textes d'une carte reçue

## Contrôle des entrées de texture parmi les textes d'une carte
## (CustomMapGuard) : noms des entrées, définitions (clé par clé), images
## (base64 strict, signature, côtés, vrai décodage), une seule image et au plus
## une carte des normales par texture, aucune image sans texture.json. Aucun
## quota de nombre ni de taille. Une texture citée mais absente n'est pas un
## refus : surface par défaut (avertissement du validateur). Liste de raisons
## [fr, en] (vide : accepté).
static func check_entries(texts: Dictionary) -> Array:
	var defs := {}
	var imgs := {}
	var normals := {}
	var b64re := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")
	for k in texts:
		var pk := parse_key(k)
		if pk.is_empty():
			continue
		var tid := String(pk[0])
		if not texts[k] is String:
			return [["texture %s : entrée illisible" % tid, "texture %s: unreadable entry" % tid]]
		if pk[1] == DEF_FILE:
			defs[tid] = texts[k]
			continue
		var side := imgs if pk[1] in IMAGE_FILES else normals
		if side.has(tid):
			return [["texture %s : deux images" % tid, "texture %s: two images" % tid]]
		side[tid] = [String(pk[1]), texts[k]]
	for tid in imgs.keys() + normals.keys():
		if not defs.has(tid):
			return [["texture %s : image sans texture.json" % tid, "texture %s: image without texture.json" % tid]]
	for tid in defs:
		var t: String = defs[tid]
		if t.to_utf8_buffer().size() > MAX_DEF_BYTES:
			return [["texture %s : texture.json trop gros" % tid, "texture %s: texture.json too big" % tid]]
		var dep := CustomMapGuard.json_depth(t)
		var d: Variant = CustomMapGuard.parse_json(t) if dep >= 0 and dep <= 4 else null
		var bad := check_def(d)
		if not bad.is_empty():
			return [["texture %s : %s" % [tid, bad[0]], "texture %s: %s" % [tid, bad[1]]]]
	for side in [imgs, normals]:
		for tid in side:
			var f: String = side[tid][0]
			var s: String = side[tid][1]
			# Alphabet base64 vérifié avant le décodage (pas d'erreur du moteur).
			if s.is_empty() or s.length() % 4 != 0 or b64re.search(s) == null:
				return [["texture %s : %s mal encodée" % [tid, f], "texture %s: badly encoded %s" % [tid, f]]]
			var raw := Marshalls.base64_to_raw(s)
			if raw.is_empty() or Marshalls.raw_to_base64(raw) != s:
				return [["texture %s : %s mal encodée" % [tid, f], "texture %s: badly encoded %s" % [tid, f]]]
			var bad := check_image(raw, f)
			if not bad.is_empty():
				return [["texture %s : %s" % [tid, bad[0]], "texture %s: %s" % [tid, bad[1]]]]
	return []


# ------------------------------------------------------------------ en jeu : matériau

## Textures déjà créées (jeu et aperçu 3D de l'éditeur, fil principal) : clé
## (empreinte des octets) -> ImageTexture. Bornée : vidée au-delà de 64.
static var _tex_cache: Dictionary = {}


## Description d'une texture pour le jeu (MapLayoutExport, clé
## « map_textures ») : {def, image, file, normal?, normal_file?}.
static func layout_entry(doc_textures: Dictionary, files: Dictionary, tid: String) -> Dictionary:
	var f := image_file(files, tid)
	if not doc_textures.has(tid) or f == "":
		return {}
	var e := {"def": doc_textures[tid], "image": String(files[file_key(tid, f)]), "file": f}
	var nf := image_file(files, tid, true)
	if nf != "":
		e["normal"] = String(files[file_key(tid, nf)])
		e["normal_file"] = nf
	return e


## Image en PIXEL ART « un pixel = un cube de 5 cm » (GAME_CONCEPT.md
## § 4.19) : `img` ramenée à `size_m` × 20 pixels de large (hauteur selon ses
## proportions), par moyenne de zone (mipmaps : réduction trilinéaire) si elle
## est plus grande, au plus proche si elle est plus petite. Le fichier de la
## carte n'est pas touché : seule l'image affichée change.
static func pixelate(img: Image, size_m: float) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.clear_mipmaps()
	var tw := maxi(1, roundi(size_m * PixelSurfaces.PX_PER_M))
	var th := maxi(1, roundi(tw * float(out.get_height()) / maxf(1.0, float(out.get_width()))))
	if out.get_width() != tw or out.get_height() != th:
		var shrink := out.get_width() > tw or out.get_height() > th
		out.resize(tw, th, Image.INTERPOLATE_TRILINEAR if shrink else Image.INTERPOLATE_NEAREST)
	return out


## ImageTexture (mipmaps) des octets base64 d'une image, réduite à `size_m` ×
## 20 pixels de large (pixelate) ; null si illisible.
static func _texture(b64: String, file: String, size_m: float) -> ImageTexture:
	var key := "%s:%d:%d:%.2f" % [file, b64.length(), b64.hash(), size_m]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := decode(Marshalls.base64_to_raw(b64), file)
	var tex: ImageTexture = null
	if img != null:
		img = pixelate(img, size_m)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	if _tex_cache.size() >= 64:
		_tex_cache.clear()
	_tex_cache[key] = tex
	return tex


## Matériau d'une texture de la carte (entrée « map_textures » de la
## description) : image répétée en coordonnées monde, motif de `taille` m de
## large (hauteur selon les proportions de l'image), rugosité, métal, teinte,
## carte des normales. null si l'entrée ou l'image est illisible (journalisé :
## l'appelant met la surface par défaut).
static func material_of(e: Variant) -> ShaderMaterial:
	if not (e is Dictionary and e.get("def") is Dictionary and e.get("image") is String and String(e.get("file", "")) in IMAGE_FILES):
		return null
	var d := sanitize(e.def)
	if d.is_empty():
		return null
	var tex := _texture(String(e.image), String(e.file), float(d.taille))
	if tex == null:
		push_warning("[MapTextureLib] image de texture illisible : surface par défaut")
		return null
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", tex)
	# Motif d'un nombre entier de pixels de 5 cm (côtés de l'image réduite).
	m.set_shader_parameter("tile", Vector2(tex.get_width(), tex.get_height()) / float(PixelSurfaces.PX_PER_M))
	m.set_shader_parameter("tint", Color.html(String(d.get("teinte", DEFAULTS.teinte))))
	m.set_shader_parameter("roughness_base", float(d.get("rugosite", DEFAULTS.rugosite)))
	m.set_shader_parameter("metallic_base", float(d.get("metal", DEFAULTS.metal)))
	if e.get("normal") is String and String(e.get("normal_file", "")) in NORMAL_FILES:
		var nt := _texture(String(e.normal), String(e.normal_file), float(d.taille))
		if nt != null:
			m.set_shader_parameter("normal_tex", nt)
			m.set_shader_parameter("use_normal", true)
	return m


## Surface du jeu de repli d'une partie (type de nœud de la géométrie :
## « floor », « ceil », sinon un mur).
static func fallback_for(kind: String) -> String:
	return "concrete" if kind == "floor" else ("ceiling" if kind == "ceil" else "wall")
