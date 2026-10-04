class_name MapTextureTools
extends Node
## TEXTURES DE LA CARTE dans l'éditeur (format 16, MapTextureLib,
## docs/MAP_AUTHORING.md § Textures de la carte) :
##   - choix de texture (Propriétés d'une pièce, formulaire d'une zone :
##     MapPanels._surface_option) : surfaces du jeu, puis la section « Textures
##     de la carte », « Importer une texture… » (PNG ou JPEG du disque, COPIÉ
##     dans la carte : textures/<tid>/, écrit à l'enregistrement) et « Gérer les
##     textures… » (liste : ⚙ régler, ✕ supprimer) ;
##   - ⚙ : nom, taille du motif (m), rugosité, métal, teinte, carte des normales ;
##   - ✕ : refusé tant qu'elle est utilisée, sauf confirmation : les pièces et
##     zones qui l'utilisent reprennent leur surface par défaut (annulable).
## Le choix d'une texture sur une pièce ou une zone est une modification
## normale (Ctrl+Z). La bibliothèque n'est pas dans l'historique (comme les
## prefabs de la carte) ; en session, seul l'hôte la change (la carte est
## renvoyée aux invités ; les IMAGES n'y passent pas : un invité voit la
## surface par défaut dans son aperçu 3D, la couleur moyenne dans les listes).
## Les fonctions statiques (import_bytes, make_def, update, users_reset_ops)
## servent aussi à Claude (MapAgentTextures, MCP).

var ed: MapEditor
var _file_dialog: FileDialog
## Aperçus des textures de la carte : « tid:taille:hash » -> ImageTexture.
var _thumbs: Dictionary = {}


# ------------------------------------------------------------------ cœur (éditeur et MCP)

## Octets d'une image PNG / JPEG du disque, pour l'import : {bytes} ou
## {error: [fr, en]} (extension, fichier illisible). Aucune limite de taille.
static func read_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not ext in ["png", "jpg", "jpeg"]:
		return {"error": ["fichier refusé : image .png, .jpg ou .jpeg seulement", "file refused: .png, .jpg or .jpeg image only"]}
	if not FileAccess.file_exists(path):
		return {"error": ["fichier introuvable : %s" % path.get_file(), "file not found: %s" % path.get_file()]}
	var b := FileAccess.get_file_as_bytes(path)
	if b.is_empty():
		return {"error": ["fichier illisible : %s" % path.get_file(), "unreadable file: %s" % path.get_file()]}
	return {"bytes": b}


## Définition `base` modifiée par les réglages `opts` (nom : texte ou {fr, en},
## taille (m), rugosite, metal (0 à 1), teinte (#rrggbb)) : {def} ou
## {error: [fr, en]} (valeur refusée, jamais corrigée en silence).
static func make_def(base: Dictionary, opts: Dictionary) -> Dictionary:
	var d := base.duplicate(true)
	if opts.has("nom"):
		var n: Variant = opts.nom
		var nom := {}
		if n is String:
			var s := clean_name(n)
			nom = {"fr": s, "en": s}
		elif n is Dictionary:
			for k in ["fr", "en"]:
				if n.get(k) is String:
					nom[k] = clean_name(n[k])
			if nom.size() == 1:
				nom[["fr", "en"][1 - ["fr", "en"].find(nom.keys()[0])]] = nom.values()[0]
		for k in nom:
			if String(nom[k]) == "" or not CustomMapGuard.name_ok(nom[k]):
				return {"error": ["nom refusé (64 caractères au plus, sans balise)", "name refused (64 characters at most, no tag)"]}
		if nom.is_empty():
			return {"error": ["nom : texte ou {fr, en} attendu", "name: text or {fr, en} expected"]}
		d["nom"] = nom
	if opts.has("taille"):
		if not MapTextureLib._num(opts.taille, MapTextureLib.SIZE[0], MapTextureLib.SIZE[1]):
			return {"error": ["taille du motif de %s à %s m attendue" % [str(MapTextureLib.SIZE[0]).replace(".", ","), str(MapTextureLib.SIZE[1])],
				"pattern size from %s to %s m expected" % [str(MapTextureLib.SIZE[0]), str(MapTextureLib.SIZE[1])]]}
		d["taille"] = float(opts.taille)
	for k in ["rugosite", "metal"]:
		if opts.has(k):
			if not MapTextureLib._num(opts[k], 0.0, 1.0):
				return {"error": ["« %s » de 0 à 1 attendu" % k, "\"%s\" from 0 to 1 expected" % k]}
			d[k] = float(opts[k])
	if opts.has("teinte"):
		var t: Variant = opts.teinte
		if t is String and not String(t).begins_with("#"):
			t = "#" + String(t)
		if not MapTextureLib._color_ok(t):
			return {"error": ["teinte #rrggbb attendue", "#rrggbb tint expected"]}
		d["teinte"] = String(t).to_lower()
	var s := MapTextureLib.sanitize(d)
	if s.is_empty():
		var why := MapTextureLib.check_def(d)
		return {"error": why if not why.is_empty() else ["réglages refusés", "settings refused"]}
	return {"def": s}


## Importe une image (octets PNG ou JPEG, décodée ici pour la vérifier) dans
## la carte `doc` : nouvelle texture. `opts` : réglages de make_def, plus
## « normale » (octets PNG / JPEG de la carte des normales) et « id »
## (identifiant voulu, sinon tiré du nom). {tid, def} ou {error: [fr, en]}.
static func import_bytes(doc: EditorMap, bytes: PackedByteArray, opts := {}) -> Dictionary:
	var file := MapTextureLib.file_for(bytes)
	if file == "":
		return {"error": ["image refusée : PNG ou JPEG attendu", "image refused: PNG or JPEG expected"]}
	var bad := MapTextureLib.check_header(bytes, file)
	if not bad.is_empty():
		return {"error": bad}
	var img := MapTextureLib.decode(bytes, file)
	if img == null:
		return {"error": ["image illisible (décodage refusé)", "unreadable image (decoding refused)"]}
	var normal := PackedByteArray()
	if opts.get("normale") is PackedByteArray and not (opts.normale as PackedByteArray).is_empty():
		normal = opts.normale
		var nf := MapTextureLib.file_for(normal, true)
		if nf == "" or MapTextureLib.decode(normal, nf) == null:
			return {"error": ["carte des normales refusée : image PNG ou JPEG lisible attendue", "normal map refused: readable PNG or JPEG image expected"]}
	var nm := String(opts.get("nom_fichier", "")).get_basename().replace("_", " ").replace("-", " ").strip_edges()
	var base := {"format": MapTextureLib.FORMAT, "nom": {"fr": clean_name(nm), "en": clean_name(nm)}, "taille": MapTextureLib.DEFAULT_SIZE,
		"couleur": MapTextureLib.average_color(img)}
	if nm == "" or not CustomMapGuard.name_ok(clean_name(nm)):
		var n := Lang.t("Texture %d", "Texture %d") % (doc.textures.size() + 1)
		base["nom"] = {"fr": n, "en": n}
	var got := make_def(base, opts)
	if got.has("error"):
		return got
	var tid := ""
	if opts.has("id"):
		tid = String(opts.id) if opts.id is String else ""
		if not MapTextureLib.tid_ok(tid):
			return {"error": ["identifiant refusé : a-z, 0-9 et _ (32 au plus, ni « __ » ni _ au bord)", "identifier refused: a-z, 0-9 and _ (32 at most, no \"__\" nor _ at the edges)"]}
		if doc.textures.has(tid):
			return {"error": ["la texture « %s » existe déjà" % tid, "texture \"%s\" already exists" % tid]}
	else:
		tid = MapTextureLib.new_tid(MapTextureLib.name_of(got.def), doc.textures)
	if not MapTextureLib.set_texture(doc, tid, got.def, bytes, normal):
		return {"error": ["texture refusée", "texture refused"]}
	return {"tid": tid, "def": doc.textures[tid], "px": [img.get_width(), img.get_height()]}


## Réglages d'une texture existante (make_def, plus « normale » : octets d'une
## nouvelle carte des normales, « retirer_normale » : vrai pour la retirer,
## « image » : octets d'une nouvelle image). {def} ou {error: [fr, en]}.
static func update(doc: EditorMap, tid: String, opts: Dictionary) -> Dictionary:
	if not doc.textures.has(tid):
		return {"error": ["texture « %s » inconnue" % tid, "unknown texture \"%s\"" % tid]}
	var got := make_def(doc.textures[tid], opts)
	if got.has("error"):
		return got
	var image := PackedByteArray()
	if opts.get("image") is PackedByteArray and not (opts.image as PackedByteArray).is_empty():
		image = opts.image
		var f := MapTextureLib.file_for(image)
		var img := MapTextureLib.decode(image, f) if f != "" else null
		if img == null:
			return {"error": ["image refusée : PNG ou JPEG lisible attendu", "image refused: readable PNG or JPEG expected"]}
		got.def["couleur"] = MapTextureLib.average_color(img)
	var normal := PackedByteArray()
	if opts.get("normale") is PackedByteArray and not (opts.normale as PackedByteArray).is_empty():
		normal = opts.normale
		var nf := MapTextureLib.file_for(normal, true)
		if nf == "" or MapTextureLib.decode(normal, nf) == null:
			return {"error": ["carte des normales refusée : image PNG ou JPEG lisible attendue", "normal map refused: readable PNG or JPEG image expected"]}
	if not MapTextureLib.set_texture(doc, tid, got.def, image, normal, bool(opts.get("retirer_normale", false))):
		return {"error": ["réglages refusés", "settings refused"]}
	return {"def": doc.textures[tid]}


## Opérations (MapOps « put ») qui remettent la surface par défaut là où la
## texture `tid` est utilisée (pièces et zones : clé retirée).
static func users_reset_ops(doc: EditorMap, tid: String) -> Array:
	var ops := []
	var done := {}
	for u in MapTextureLib.users(doc, tid):
		var key := "%s:%s" % [u.coll, u.id]
		if done.has(key):
			continue
		done[key] = true
		var el := (doc.find(String(u.id)) as Dictionary).duplicate(true)
		for k in ["surface_sol", "surface_murs", "surface_plafond", "sol", "murs", "plafond"]:
			if String(el.get(k, "")) == MapTextureLib.ref(tid):
				el.erase(k)
		ops.append({"op": "put", "coll": String(u.coll), "el": el})
	return ops


static func clean_name(s: String) -> String:
	return CustomMapGuard.clean_display(s.strip_edges(), CustomMapGuard.MAX_NAME)


# ------------------------------------------------------------------ éditeur : session

## La bibliothèque peut-elle être changée ? (en session : l'hôte seulement)
func _can_edit() -> bool:
	if ed.collab != null and ed.collab.role == MapCollab.Role.GUEST:
		ed.set_status(Lang.t("Seul l'hôte de la session change les textures de la carte", "Only the session host changes the map textures"), true)
		return false
	return true


## Après un changement de la bibliothèque : carte modifiée, panneaux,
## invités de la session (la carte entière, sans les images).
func library_changed() -> void:
	ed.changed()
	if ed.collab != null:
		ed.collab.broadcast_map()


# ------------------------------------------------------------------ aperçus

## Aperçu d'une surface (clé du jeu ou « map:<tid> ») pour les listes.
func icon(key: String) -> Texture2D:
	var tid := MapTextureLib.tid_of(key)
	if tid == "":
		return MapIcons.surface_texture(key)
	var def: Dictionary = ed.doc.textures.get(tid, {})
	var f := MapTextureLib.image_file(ed.doc.texture_files, tid)
	var b64 := String(ed.doc.texture_files.get(MapTextureLib.file_key(tid, f), "")) if f != "" else ""
	var ck := "%s:%d:%d:%s" % [tid, b64.length(), b64.hash(), String(def.get("couleur", ""))]
	if _thumbs.has(ck):
		return _thumbs[ck]
	var tex: Texture2D = null
	var img := MapTextureLib.decode(Marshalls.base64_to_raw(b64), f) if f != "" else null
	if img != null:
		tex = MapTextureLib.thumbnail(img)
	else:
		# Sans image (invité d'une session, image absente) : sa couleur moyenne.
		var flat := Image.create(40, 24, false, Image.FORMAT_RGB8)
		flat.fill(MapTextureLib.color_of(def) if not def.is_empty() else Color(0.35, 0.1, 0.1))
		tex = ImageTexture.create_from_image(flat)
	if _thumbs.size() > 64:
		_thumbs.clear()
	_thumbs[ck] = tex
	return tex


## Nom affiché d'une surface (clé du jeu ou « map:<tid> »).
func surface_name(key: String) -> String:
	var tid := MapTextureLib.tid_of(key)
	if tid == "":
		return MapCatalog.surface_name(key)
	if not ed.doc.textures.has(tid):
		return Lang.t("%s (absente)", "%s (missing)") % tid
	return MapTextureLib.name_of(ed.doc.textures[tid])


# ------------------------------------------------------------------ importer

## « Importer une texture… » : explorateur du système (FilePick). L'image
## choisie passe par import_file ; `on_done(tid)` reçoit la nouvelle texture.
func import_dialog(on_done := Callable()) -> void:
	if not _can_edit():
		return
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()
	var chosen := func(path: String):
		var tid := import_file(path)
		if tid != "" and on_done.is_valid():
			on_done.call(tid)
	_file_dialog = FilePick.pick(ed, Lang.t("Importer une texture (image de la carte)", "Import a texture (map image)"),
		FilePick.Mode.OPEN, PackedStringArray(["*.png, *.jpg, *.jpeg ; " + Lang.t("Image PNG ou JPEG", "PNG or JPEG image")]),
		chosen, "", "", ed.ui_scale)


## Importe l'image `path` (copiée dans la carte, écrite à l'enregistrement
## dans textures/<tid>/). Rend l'identifiant ("" : refusée, raison affichée).
func import_file(path: String, opts := {}) -> String:
	if not _can_edit():
		return ""
	var got := read_file(path)
	if got.has("error"):
		_refuse(Lang.t(got.error[0], got.error[1]))
		return ""
	var o := opts.duplicate()
	o["nom_fichier"] = path.get_file()
	var res := import_bytes(ed.doc, got.bytes, o)
	if res.has("error"):
		push_warning("[MapTextureTools] import refusé (%s) : %s" % [path.get_file(), res.error[0]])
		_refuse(Lang.t(res.error[0], res.error[1]))
		return ""
	library_changed()
	ed.set_status(Lang.t("Texture « %s » importée (%d × %d px) : copiée dans le dossier de la carte à l'enregistrement",
		"Texture \"%s\" imported (%d × %d px): copied into the map folder when saved") % [MapTextureLib.name_of(res.def), res.px[0], res.px[1]])
	return String(res.tid)


func _refuse(msg: String) -> void:
	ed.set_status(Lang.t("Import refusé : %s", "Import refused: %s") % msg, true)
	if ed.is_inside_tree() and DisplayServer.get_name() != "headless":
		ed._info(Lang.t("Importer une texture", "Import a texture"), msg)


# ------------------------------------------------------------------ régler

func _row(box: Container, label: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	box.add_child(h)


static func _spin(lo: float, hi: float, step: float, v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	return s


## ⚙ : nom, taille du motif, rugosité, métal, teinte, carte des normales ;
## « Supprimer… » en bas.
func edit_dialog(tid: String) -> void:
	if not _can_edit() or not ed.doc.textures.has(tid):
		return
	var def: Dictionary = ed.doc.textures[tid]
	var d := ConfirmationDialog.new()
	d.title = Lang.t("Texture de la carte", "Map texture")
	var box := VBoxContainer.new()
	d.add_child(box)
	var top := HBoxContainer.new()
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(80, 48)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture = icon(MapTextureLib.ref(tid))
	top.add_child(pic)
	var info := Label.new()
	info.text = "map:%s · %s" % [tid, Lang.t("utilisée %d fois", "used %d times") % MapTextureLib.users(ed.doc, tid).size()]
	info.add_theme_color_override("font_color", UiStyle.DIM)
	top.add_child(info)
	box.add_child(top)
	var e := LineEdit.new()
	e.text = MapTextureLib.name_of(def)
	e.max_length = CustomMapGuard.MAX_NAME
	e.custom_minimum_size = Vector2(320, 0)
	_row(box, Lang.t("Nom :", "Name:"), e)
	var size := _spin(MapTextureLib.SIZE[0], MapTextureLib.SIZE[1], 0.05, float(def.taille))
	size.suffix = "m"
	size.tooltip_text = Lang.t("Largeur d'une répétition de l'image, en mètres (la hauteur suit les proportions de l'image) : même échelle au sol, aux murs et au plafond",
		"Width of one repeat of the image, in metres (the height follows the image proportions): same scale on floors, walls and ceilings")
	_row(box, Lang.t("Taille du motif :", "Pattern size:"), size)
	var rough := _spin(0.0, 1.0, 0.05, float(def.get("rugosite", MapTextureLib.DEFAULTS.rugosite)))
	_row(box, Lang.t("Rugosité :", "Roughness:"), rough)
	var metal := _spin(0.0, 1.0, 0.05, float(def.get("metal", MapTextureLib.DEFAULTS.metal)))
	_row(box, Lang.t("Métal :", "Metallic:"), metal)
	var tint := ColorPickerButton.new()
	tint.color = Color.html(String(def.get("teinte", MapTextureLib.DEFAULTS.teinte)))
	tint.edit_alpha = false
	tint.custom_minimum_size = Vector2(60, 24)
	_row(box, Lang.t("Teinte :", "Tint:"), tint)
	var nb := HBoxContainer.new()
	var has_n := MapTextureLib.image_file(ed.doc.texture_files, tid, true) != ""
	var nl := Label.new()
	nl.text = Lang.t("présente", "present") if has_n else Lang.t("aucune", "none")
	nb.add_child(nl)
	var nbtn := Button.new()
	nbtn.text = Lang.t("Importer…", "Import…")
	var on_normal := func(path: String):
		var got := read_file(path)
		if got.has("error"):
			_refuse(Lang.t(got.error[0], got.error[1]))
			return
		if set_settings(tid, {"normale": got.bytes}):
			nl.text = Lang.t("présente", "present")
	nbtn.pressed.connect(func():
		FilePick.pick(ed, Lang.t("Carte des normales (PNG ou JPEG)", "Normal map (PNG or JPEG)"), FilePick.Mode.OPEN,
			PackedStringArray(["*.png, *.jpg, *.jpeg ; " + Lang.t("Image PNG ou JPEG", "PNG or JPEG image")]), on_normal, "", "", ed.ui_scale))
	nb.add_child(nbtn)
	var nrm := Button.new()
	nrm.text = Lang.t("Retirer", "Remove")
	nrm.pressed.connect(func():
		set_settings(tid, {"retirer_normale": true})
		nl.text = Lang.t("aucune", "none"))
	nb.add_child(nrm)
	_row(box, Lang.t("Carte des normales :", "Normal map:"), nb)
	var del := Button.new()
	del.text = Lang.t("Supprimer la texture…", "Delete the texture…")
	del.pressed.connect(func():
		d.hide()
		d.queue_free()
		delete_dialog(tid))
	box.add_child(del)
	d.ok_button_text = Lang.t("Appliquer", "Apply")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	ed.add_child(d)
	d.confirmed.connect(func():
		set_settings(tid, {"nom": e.text, "taille": size.value, "rugosite": rough.value, "metal": metal.value, "teinte": "#" + tint.color.to_html(false)})
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	e.grab_focus.call_deferred()


## Nouveaux réglages (update) avec message ; vrai si appliqués.
func set_settings(tid: String, opts: Dictionary) -> bool:
	if not _can_edit():
		return false
	var res := update(ed.doc, tid, opts)
	if res.has("error"):
		ed.set_status(Lang.t("Réglages refusés : %s", "Settings refused: %s") % Lang.t(res.error[0], res.error[1]), true)
		return false
	library_changed()
	ed.set_status(Lang.t("Texture « %s » mise à jour", "Texture \"%s\" updated") % MapTextureLib.name_of(res.def))
	return true


# ------------------------------------------------------------------ supprimer

func delete_dialog(tid: String) -> void:
	if not _can_edit() or not ed.doc.textures.has(tid):
		return
	var users := MapTextureLib.users(ed.doc, tid)
	var nm := MapTextureLib.name_of(ed.doc.textures[tid])
	if users.is_empty():
		ed._confirm(Lang.t("Supprimer la texture", "Delete the texture"), Lang.t("Supprimer « %s » de la carte ?", "Delete \"%s\" from the map?") % nm, func(): delete_texture(tid, false))
	else:
		ed._confirm(Lang.t("Supprimer la texture", "Delete the texture"),
			Lang.t("« %s » est utilisée %d fois (pièces, zones). Les supprimer quand même ? Ces pièces et zones reprendront leur surface par défaut (annulable : Ctrl+Z).",
				"\"%s\" is used %d times (rooms, zones). Delete it anyway? These rooms and zones go back to their default surface (undo: Ctrl+Z).") % [nm, users.size()],
			func(): delete_texture(tid, true))


## Supprime la texture ; utilisée : refusé, sauf `force` (surface par défaut
## remise là où elle est utilisée : une modification annulable).
func delete_texture(tid: String, force := false) -> bool:
	if not _can_edit() or not ed.doc.textures.has(tid):
		return false
	var ops := users_reset_ops(ed.doc, tid)
	if not ops.is_empty() and not force:
		ed.set_status(Lang.t("Texture utilisée %d fois : choisissez d'abord une autre surface", "Texture used %d times: pick another surface first") % ops.size(), true)
		return false
	if not ops.is_empty():
		ed.push_undo()
		MapOps.apply(ed.doc, ops)
		ed.changed()
	MapTextureLib.remove(ed.doc, tid)
	library_changed()
	ed.set_status(Lang.t("Texture supprimée", "Texture deleted"))
	return true


# ------------------------------------------------------------------ gérer

## « Gérer les textures… » : toutes les textures de la carte (aperçu, nom,
## référence, utilisations), ⚙ et ✕ sur chacune, « Importer… » en bas.
func manage_dialog() -> void:
	var d := AcceptDialog.new()
	d.title = Lang.t("Textures de la carte", "Map textures")
	d.ok_button_text = Lang.t("Fermer", "Close")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	d.add_child(box)
	var ids := ed.doc.textures.keys()
	ids.sort()
	if ids.is_empty():
		var l := Label.new()
		l.text = Lang.t("Aucune texture importée.", "No imported texture.")
		box.add_child(l)
	for tid in ids:
		var h := HBoxContainer.new()
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(40, 24)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture = icon(MapTextureLib.ref(tid))
		h.add_child(pic)
		var l := Label.new()
		l.text = "%s  (map:%s · %s)" % [MapTextureLib.name_of(ed.doc.textures[tid]), tid, Lang.t("%d utilisation(s)", "%d use(s)") % MapTextureLib.users(ed.doc, tid).size()]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var e := Button.new()
		e.text = "⚙"
		e.tooltip_text = Lang.t("Renommer, régler", "Rename, adjust")
		e.pressed.connect(func():
			d.queue_free()
			edit_dialog(tid))
		h.add_child(e)
		var x := Button.new()
		x.text = "✕"
		x.tooltip_text = Lang.t("Supprimer cette texture", "Delete this texture")
		x.pressed.connect(func():
			d.queue_free()
			delete_dialog(tid))
		h.add_child(x)
		box.add_child(h)
	var imp := Button.new()
	imp.text = Lang.t("Importer une texture…", "Import a texture…")
	imp.pressed.connect(func():
		d.queue_free()
		import_dialog(func(tid): edit_dialog(tid)))
	box.add_child(imp)
	ed.add_child(d)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.popup_centered()
