extends Control
## Lanceur de Claude of Duty Zombie (comme celui de Minecraft) :
## - liste des versions publiées, « Dernière version » en tête ;
## - notes de version pour les joueurs, avec captures (cliquer pour agrandir) ;
## - à l'ouverture, télécharge tout seul la dernière version (mise à jour) ;
## - JOUER lance la version choisie (téléchargée au besoin), puis se ferme ;
## - se met à jour lui-même quand un lanceur plus récent est publié.
##
## Options (tests, captures) : --capture=<fichier.png> (image puis sortie, sans
## téléchargement), --changelogs=<changelogs.json local>, --offline,
## --quit-after-update (test : se ferme après la mise à jour automatique).

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")
const Texts := preload("res://scripts/texts.gd")
const Version := preload("res://scripts/version.gd")

const BG := Color(0.045, 0.04, 0.035)
const PANEL := Color(0.085, 0.075, 0.065)
const BONE := Color(0.86, 0.82, 0.72)
const DIM := Color(0.55, 0.52, 0.46)
const BLOOD := Color(0.62, 0.05, 0.04)
const BLOOD_BRIGHT := Color(0.85, 0.1, 0.06)
const GOLD := Color(0.95, 0.78, 0.35)

var settings := {}
var lang := "fr"
var versions: Array = []        # versions publiées (Releases.parse_releases)
var changelogs: Dictionary = {}
var online := true
var _known := false             # liste des versions connue (en ligne ou hors ligne confirmé)
var selected := "latest"        # « latest » ou un numéro de version
var _textures := {}             # nom d'image -> Texture2D
var _image_queue: Array = []
var _args := {}

var _list: ItemList
var _list_tags: Array = []
var _title: Label
var _date: Label
var _items: RichTextLabel
var _images: HFlowContainer
var _hint: Label
var _status: Label
var _progress: ProgressBar
var _play: Button
var _delete: Button
var _lang_btn: OptionButton
var _zoom: ColorRect
var _zoom_tex: TextureRect

var _http_api: HTTPRequest
var _http_notes: HTTPRequest
var _http_img: HTTPRequest
var _http_dl: HTTPRequest
var _dl_tag := ""
var _dl_size := 0
var _dl_is_update := false
var _dl_sha256 := ""            # somme attendue de l'exécutable en cours ("" : version ancienne)
var _play_after := false
var _img_loading := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--") and "=" in a:
			_args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
		elif a.begins_with("--"):
			_args[a.trim_prefix("--")] = true
	settings = Store.load_settings()
	lang = String(settings.get("language", "fr"))
	selected = String(settings.get("selected", "latest"))
	get_window().title = "Claude of Duty Zombie"
	get_window().min_size = Vector2i(900, 560)
	_build_ui()
	_http_api = _new_http()
	_http_notes = _new_http()
	_http_img = _new_http()
	_http_dl = _new_http()
	_load_cached_changelogs()
	_refresh_list()
	if _args.has("changelogs"):
		_read_local_changelogs(String(_args.changelogs))
	if _args.has("offline"):
		_set_offline()
	else:
		_set_status(Texts.t("loading", lang))
		_fetch(_http_api, Releases.API_URL, Releases.MAX_API_BYTES, _on_releases)
		if not _args.has("changelogs"):
			_fetch(_http_notes, Releases.CHANGELOG_URL, Releases.MAX_CHANGELOG_BYTES, _on_changelogs)
	if _args.has("capture"):
		_capture_later(String(_args.capture))


func _new_http() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = 20.0
	h.use_threads = true
	# Redirections suivies à la main (_on_http) : chaque adresse est revérifiée.
	h.max_redirects = 0
	# Certificat du serveur vérifié (autorités de confiance du système).
	h.set_tls_options(TLSOptions.client())
	h.request_completed.connect(_on_http.bind(h))
	add_child(h)
	return h


## Requête GET vers une adresse autorisée (HTTPS, domaines GitHub), réponse
## bornée à `limit` octets, écrite dans `file` si donné. `done` reçoit
## (résultat, code HTTP, corps). Faux si l'adresse est refusée ou si la
## requête ne part pas (rien n'est appelé).
func _fetch(h: HTTPRequest, url: String, limit: int, done: Callable, file := "", timeout := 20.0) -> bool:
	if not Releases.is_allowed_url(url):
		push_warning("[launcher] adresse refusée : " + url.left(200))
		return false
	h.set_meta("done", done)
	h.set_meta("hops", 0)
	h.download_file = file
	h.body_size_limit = limit
	h.timeout = timeout
	return h.request(url, PackedStringArray(Releases.HEADERS)) == OK


func _on_http(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, h: HTTPRequest) -> void:
	if code in [301, 302, 303, 307, 308]:
		var loc := Releases.header(headers, "location")
		var hops := int(h.get_meta("hops", 0)) + 1
		if hops <= Releases.MAX_REDIRECTS and Releases.is_allowed_url(loc):
			h.set_meta("hops", hops)
			if h.request(loc, PackedStringArray(Releases.HEADERS)) == OK:
				return
		push_warning("[launcher] redirection refusée : " + loc.left(200))
		result = HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED
	var done: Callable = h.get_meta("done", Callable())
	if done.is_valid():
		done.call(result, code, body)


# --------------------------------------------------------------------------
# Interface
# --------------------------------------------------------------------------

func _font(names: Array) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


func _build_ui() -> void:
	var body_font := _font(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	var title_font := _font(["Impact", "Bahnschrift", "Arial Black", "sans-serif"])
	var th := Theme.new()
	th.default_font = body_font
	th.default_font_size = 17
	th.set_color("font_color", "Label", BONE)
	th.set_color("font_color", "ItemList", BONE)
	th.set_color("font_selected_color", "ItemList", Color(1, 0.95, 0.88))
	th.set_color("font_hovered_color", "ItemList", Color(1, 0.95, 0.88))
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(BLOOD, 0.75)
	th.set_stylebox("selected", "ItemList", sel)
	th.set_stylebox("selected_focus", "ItemList", sel)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(1, 1, 1, 0.05)
	th.set_stylebox("hovered", "ItemList", hov)
	th.set_stylebox("panel", "ItemList", _box(PANEL, 0))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_constant("v_separation", "ItemList", 10)
	th.set_constant("h_separation", "ItemList", 10)
	th.set_color("default_color", "RichTextLabel", BONE)
	theme = th

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# En-tête : titre, sous-titre, langue.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var t := Label.new()
	t.text = "CLAUDE OF DUTY ZOMBIE"
	t.add_theme_font_override("font", title_font)
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", BONE)
	t.add_theme_color_override("font_shadow_color", Color(BLOOD, 0.9))
	t.add_theme_constant_override("shadow_offset_x", 3)
	t.add_theme_constant_override("shadow_offset_y", 3)
	head.add_child(t)
	var sub := Label.new()
	sub.name = "Subtitle"
	sub.add_theme_color_override("font_color", BLOOD_BRIGHT)
	sub.add_theme_font_override("font", title_font)
	sub.add_theme_font_size_override("font_size", 22)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_lang_btn = OptionButton.new()
	_lang_btn.add_item("FRANÇAIS")
	_lang_btn.add_item("ENGLISH")
	_lang_btn.select(0 if lang == "fr" else 1)
	_lang_btn.item_selected.connect(_on_lang)
	_lang_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_lang_btn)

	# Corps : versions à gauche, notes à droite.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	body.add_child(left)
	var vt := Label.new()
	vt.name = "VersionsTitle"
	vt.add_theme_font_override("font", title_font)
	vt.add_theme_font_size_override("font_size", 20)
	vt.add_theme_color_override("font_color", DIM)
	left.add_child(vt)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_select)
	_list.add_theme_font_size_override("font_size", 17)
	left.add_child(_list)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", _box(PANEL, 18))
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 10)
	scroll.add_child(notes)
	_title = Label.new()
	_title.add_theme_font_override("font", title_font)
	_title.add_theme_font_size_override("font_size", 32)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(_title)
	_date = Label.new()
	_date.add_theme_color_override("font_color", DIM)
	notes.add_child(_date)
	_items = RichTextLabel.new()
	_items.bbcode_enabled = true
	_items.fit_content = true
	_items.scroll_active = false
	_items.add_theme_font_size_override("normal_font_size", 19)
	_items.add_theme_constant_override("line_separation", 6)
	notes.add_child(_items)
	_images = HFlowContainer.new()
	_images.add_theme_constant_override("h_separation", 10)
	_images.add_theme_constant_override("v_separation", 10)
	notes.add_child(_images)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", DIM)
	_hint.add_theme_font_size_override("font_size", 14)
	notes.add_child(_hint)

	# Pied : état, progression, supprimer, jouer.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	root.add_child(foot)
	var st := VBoxContainer.new()
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(st)
	_status = Label.new()
	_status.add_theme_color_override("font_color", DIM)
	st.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 10)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background", _box(PANEL, 0))
	_progress.add_theme_stylebox_override("fill", _box(BLOOD, 0))
	_progress.visible = false
	st.add_child(_progress)
	_delete = Button.new()
	_delete.custom_minimum_size = Vector2(150, 56)
	_style_button(_delete, Color(0.16, 0.14, 0.12), title_font, 20)
	_delete.pressed.connect(_on_delete)
	foot.add_child(_delete)
	_play = Button.new()
	_play.custom_minimum_size = Vector2(260, 56)
	_style_button(_play, BLOOD, title_font, 30)
	_play.pressed.connect(_on_play)
	foot.add_child(_play)

	# Capture agrandie (clic pour fermer).
	_zoom = ColorRect.new()
	_zoom.color = Color(0, 0, 0, 0.88)
	_zoom.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zoom.visible = false
	_zoom.gui_input.connect(_on_zoom_input)
	add_child(_zoom)
	_zoom_tex = TextureRect.new()
	_zoom_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zoom_tex.offset_left = 40
	_zoom_tex.offset_top = 40
	_zoom_tex.offset_right = -40
	_zoom_tex.offset_bottom = -40
	_zoom_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zoom_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_zoom_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom.add_child(_zoom_tex)
	_apply_texts()


func _box(c: Color, pad: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	return b


func _style_button(b: Button, c: Color, f: Font, size: int) -> void:
	b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.9))
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_stylebox_override("normal", _box(c, 8))
	b.add_theme_stylebox_override("hover", _box(c.lightened(0.15), 8))
	b.add_theme_stylebox_override("pressed", _box(c.darkened(0.2), 8))
	b.add_theme_stylebox_override("disabled", _box(c.darkened(0.45), 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _apply_texts() -> void:
	(find_child("Subtitle", true, false) as Label).text = Texts.t("subtitle", lang)
	(find_child("VersionsTitle", true, false) as Label).text = Texts.t("versions", lang)
	_play.text = Texts.t("play", lang)
	_delete.text = Texts.t("delete", lang)
	_refresh_list()


func _set_status(t: String) -> void:
	_status.text = t


# --------------------------------------------------------------------------
# Versions
# --------------------------------------------------------------------------

## Versions affichées : publiées (en ligne) ou installées (hors ligne).
func _all_tags() -> Array:
	var tags: Array = []
	for v in versions:
		tags.append(v.tag)
	for t in Store.installed():
		if not t in tags:
			tags.append(t)
	tags.sort_custom(func(a, b): return Releases.newer(a, b))
	return tags


func _latest() -> String:
	var tags := _all_tags()
	return tags[0] if not tags.is_empty() else ""


func _resolved() -> String:
	return _latest() if selected == "latest" else selected


func _info(tag: String) -> Dictionary:
	for v in versions:
		if v.tag == tag:
			return v
	return {}


func _refresh_list() -> void:
	if _list == null:
		return
	_list.clear()
	_list_tags = []
	var latest := _latest()
	if latest != "":
		_list.add_item("★  %s  (%s)" % [Texts.t("latest", lang), latest])
		_list_tags.append("latest")
	for tag in _all_tags():
		var d := String(_info(tag).get("date", ""))
		var line: String = tag + ("   " + Texts.date(d, lang) if d != "" else "")
		if Store.is_installed(tag):
			line += "   ✓"
		_list.add_item(line)
		_list_tags.append(tag)
	# Version choisie disparue (supprimée, retirée) : retour à la dernière, mais
	# seulement une fois la liste connue (sinon on perdrait le choix au démarrage).
	if _known and not selected in _list_tags and selected != "latest":
		selected = "latest"
	var idx := _list_tags.find(selected)
	if idx >= 0:
		_list.select(idx)
	_show_notes()


func _on_select(i: int) -> void:
	selected = _list_tags[i]
	settings.selected = selected
	Store.save_settings(settings)
	_show_notes()


func _on_lang(i: int) -> void:
	lang = "fr" if i == 0 else "en"
	settings.language = lang
	Store.save_settings(settings)
	_apply_texts()


func _show_notes() -> void:
	var tag := _resolved()
	var info := _info(tag)
	var n := Releases.notes(changelogs, tag, lang, String(info.get("title", "")))
	_title.text = String(n.title) if String(n.title) != "" else tag
	var d := String(info.get("date", ""))
	_date.text = tag + ("  ·  " + Texts.date(d, lang) if d != "" else "")
	var txt := ""
	for it in n.items:
		# Texte des notes échappé : aucune balise BBCode venue d'Internet.
		txt += "[color=#%s]■[/color]  %s\n" % [BLOOD_BRIGHT.to_html(false), Releases.escape_bbcode(String(it))]
	if n.items.is_empty():
		txt = "[color=#%s]%s[/color]" % [DIM.to_html(false), Texts.t("no_notes" if tag != "" else "no_versions", lang)]
	_items.text = txt.strip_edges()
	for c in _images.get_children():
		c.queue_free()
	for img in n.images:
		var b := TextureButton.new()
		b.custom_minimum_size = Vector2(320, 180)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.set_meta("image", img)
		b.pressed.connect(_on_zoom.bind(String(img)))
		_images.add_child(b)
		_fill_image(b, String(img))
	_hint.text = Texts.t("click_zoom", lang) if not n.images.is_empty() else ""
	_update_buttons()


func _update_buttons() -> void:
	var tag := _resolved()
	var busy := _dl_tag != ""
	_play.disabled = tag == "" or (not Store.is_installed(tag) and _info(tag).is_empty())
	_delete.visible = Store.is_installed(tag) and not (busy and _dl_tag == tag)
	if busy:
		return
	if tag == "":
		return
	if Store.is_installed(tag):
		_set_status(Texts.t("ready", lang) if online else Texts.t("offline", lang))
	elif not _info(tag).is_empty():
		var policy := Releases.integrity(versions, tag)
		if policy == Releases.REFUSED:
			_play.disabled = true
			_set_status(Texts.t("no_checksum", lang) % tag)
			return
		_set_status(Texts.t("to_download", lang) % str(int(round(float(_info(tag).exe_size) / 1048576.0)))
				+ ("   " + Texts.t("legacy", lang) if policy == Releases.LEGACY else ""))


func _on_delete() -> void:
	var tag := _resolved()
	if not Store.is_installed(tag) or _dl_tag == tag:
		return
	Store.remove(tag)
	_refresh_list()
	_set_status(Texts.t("deleted", lang) % tag)


# --------------------------------------------------------------------------
# Réseau : versions, notes, captures
# --------------------------------------------------------------------------

func _on_releases(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_offline()
		return
	versions = Releases.parse_releases(body.get_string_from_utf8())
	online = not versions.is_empty()
	_known = true
	_refresh_list()
	if not online:
		_set_offline()
		return
	_check_launcher_update()
	# Mise à jour automatique : la dernière version est téléchargée à l'ouverture.
	var latest := _latest()
	if selected == "latest" and latest != "" and not Store.is_installed(latest) and not _args.has("capture"):
		_start_download(latest, true)


func _set_offline() -> void:
	online = false
	_known = true
	_refresh_list()
	_set_status(Texts.t("offline", lang))


func _load_cached_changelogs() -> void:
	var f := FileAccess.open("user://changelogs.json", FileAccess.READ)
	if f and f.get_length() <= Releases.MAX_CHANGELOG_BYTES:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			changelogs = d


func _on_changelogs(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() > Releases.MAX_CHANGELOG_BYTES:
		return
	var text := body.get_string_from_utf8()
	var d = JSON.parse_string(text)
	if not d is Dictionary:
		return
	changelogs = d
	var f := FileAccess.open("user://changelogs.json", FileAccess.WRITE)
	if f:
		f.store_string(text)
	_show_notes()


## Notes locales (aperçu avant publication) : images dans img/ à côté du fichier.
func _read_local_changelogs(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		changelogs = d
		_args["local_img"] = path.get_base_dir() + "/img/"
	_refresh_list()


func _fill_image(b: TextureButton, name: String) -> void:
	# Le nom devient un chemin (cache, adresse) : déjà filtré par Releases.notes.
	if not Releases.is_safe_image_name(name):
		return
	if _textures.has(name):
		b.texture_normal = _textures[name]
		return
	var local := String(_args.get("local_img", ""))
	var cache := "user://img/" + name
	for path in [local + name if local != "" else "", cache]:
		if path != "" and FileAccess.file_exists(path):
			var tex := _texture_from(FileAccess.get_file_as_bytes(path), name)
			if tex:
				_textures[name] = tex
				b.texture_normal = tex
				return
	if not name in _image_queue and name != _img_loading:
		_image_queue.append(name)
	_next_image()


func _next_image() -> void:
	if _img_loading != "" or _image_queue.is_empty() or _args.has("offline"):
		return
	_img_loading = _image_queue.pop_front()
	if not _fetch(_http_img, Releases.IMAGE_URL + _img_loading.uri_encode().replace("%2F", "/"), Releases.MAX_IMAGE_BYTES, _on_image):
		_img_loading = ""


func _on_image(result: int, code: int, body: PackedByteArray) -> void:
	var name := _img_loading
	_img_loading = ""
	# Seules les images valides (format, taille, dimensions) sont gardées en cache.
	var tex := _texture_from(body, name) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if tex:
		DirAccess.make_dir_recursive_absolute(("user://img/" + name).get_base_dir())
		var f := FileAccess.open("user://img/" + name, FileAccess.WRITE)
		if f:
			f.store_buffer(body)
		_textures[name] = tex
		for b in _images.get_children():
			if b.get_meta("image", "") == name:
				(b as TextureButton).texture_normal = tex
	_next_image()


## Texture d'une capture : format reconnu à ses premiers octets (pas au nom),
## dimensions lues dans l'en-tête et bornées AVANT le décodage.
func _texture_from(bytes: PackedByteArray, _name: String) -> Texture2D:
	if not Releases.image_ok(bytes):
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes) if Releases.image_format(bytes) == "png" else img.load_jpg_from_buffer(bytes)
	return ImageTexture.create_from_image(img) if err == OK else null


func _on_zoom_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_zoom.visible = false


func _on_zoom(name: String) -> void:
	if _textures.has(name):
		_zoom_tex.texture = _textures[name]
		_zoom.visible = true


# --------------------------------------------------------------------------
# Téléchargement et lancement
# --------------------------------------------------------------------------

## Téléchargement d'une version, en deux temps quand la release publie ses
## sommes (Releases.integrity) : SHA256SUMS.txt d'abord, puis l'exécutable
## dans un fichier partiel, vérifié (taille, SHA-256) avant de devenir
## l'exécutable installé. Une version récente sans sommes est refusée.
func _start_download(tag: String, is_update: bool) -> void:
	var info := _info(tag)
	if info.is_empty() or _dl_tag != "":
		return
	var policy := Releases.integrity(versions, tag)
	if policy == Releases.REFUSED:
		_play_after = false
		_set_status(Texts.t("no_checksum", lang) % tag)
		return
	Store.prepare_dir(tag)
	_dl_tag = tag
	_dl_size = int(info.exe_size)
	_dl_is_update = is_update
	_dl_sha256 = ""
	var ok := false
	if policy == Releases.VERIFIED:
		ok = _fetch(_http_dl, String(info.sums_url), Releases.MAX_SMALL_BYTES, _on_game_sums)
	else:
		print("[launcher] %s : version antérieure aux sommes SHA-256, taille vérifiée seulement" % tag)
		ok = _download_exe(info)
	if not ok:
		_dl_tag = ""
		_set_status(Texts.t("download_failed", lang) % tag)
		return
	_progress.visible = true
	_progress.value = 0
	_update_buttons()


func _on_game_sums(result: int, code: int, body: PackedByteArray) -> void:
	var info := _info(_dl_tag)
	var sha := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and not info.is_empty():
		sha = String(Releases.parse_sums(body.get_string_from_utf8()).get(String(info.exe_name), ""))
	if sha == "":
		_fail_download(_dl_tag, "no_checksum")
		return
	_dl_sha256 = sha
	if not _download_exe(info):
		_fail_download(_dl_tag, "download_failed")


func _download_exe(info: Dictionary) -> bool:
	var part := Store.part_path(String(info.tag))
	if part == "":
		return false
	Store.prepare_dir(String(info.tag))
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	var limit := int(info.exe_size) if int(info.exe_size) > 0 else Releases.MAX_EXE_BYTES
	return _fetch(_http_dl, String(info.exe_url), limit, _on_download_done, part, 0.0)


func _fail_download(tag: String, key: String) -> void:
	_dl_tag = ""
	_play_after = false
	_progress.visible = false
	var part := Store.part_path(tag)
	if part != "" and FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	_refresh_list()
	_set_status(Texts.t(key, lang) % tag)


func _process(_delta: float) -> void:
	if _dl_tag == "":
		return
	var total := _http_dl.get_body_size()
	if total <= 0:
		total = _dl_size
	var pct := 0.0 if total <= 0 else 100.0 * float(_http_dl.get_downloaded_bytes()) / float(total)
	_progress.value = pct
	_set_status(Texts.t("updating" if _dl_is_update else "downloading", lang) % [_dl_tag, int(pct)]
			+ ("   " + Texts.t("play_after", lang) if _play_after else ""))


func _on_download_done(result: int, code: int, _b: PackedByteArray) -> void:
	var tag := _dl_tag
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail_download(tag, "download_failed")
		return
	# Jamais installé (ni lancé) avant d'être vérifié : taille annoncée par
	# GitHub et, si la release les publie, somme SHA-256.
	if not Store.verify_file(Store.part_path(tag), _dl_sha256, _dl_size):
		print("[launcher] %s : fichier téléchargé NON conforme (taille ou SHA-256), supprimé" % tag)
		_fail_download(tag, "integrity_failed")
		return
	if not Store.finish_download(tag):
		_fail_download(tag, "download_failed")
		return
	_dl_tag = ""
	_progress.visible = false
	_refresh_list()
	if _args.has("quit-after-update"):
		print("[launcher] installée : ", Store.exe_path(tag))
		get_tree().quit()
		return
	if _play_after and _resolved() == tag:
		_launch(tag)


func _on_play() -> void:
	var tag := _resolved()
	if tag == "":
		return
	if Store.is_installed(tag):
		_launch(tag)
		return
	_play_after = true
	if _dl_tag == "":
		_start_download(tag, false)
	else:
		_update_buttons()
		_process(0.0)


func _launch(tag: String) -> void:
	if not Store.is_installed(tag):
		return
	_set_status(Texts.t("launching", lang) % tag)
	var pid := OS.create_process(Store.exe_path(tag), [])
	if pid <= 0:
		_set_status(Texts.t("download_failed", lang) % tag)
		return
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


# --------------------------------------------------------------------------
# Mise à jour du lanceur lui-même
# --------------------------------------------------------------------------

func _check_launcher_update() -> void:
	if not OS.has_feature("template") or _args.has("capture") or versions.is_empty():
		return
	var v: Dictionary = versions[0]
	if String(v.launcher_version_url) == "" or String(v.launcher_url) == "":
		return
	# Nouveau lanceur jamais installé sans somme SHA-256 publiée avec lui.
	if String(v.sums_url) == "":
		print("[launcher] mise à jour du lanceur ignorée : %s sans %s" % [v.tag, Releases.SUMS_ASSET])
		return
	var h := _new_http()
	if not _fetch(h, String(v.launcher_version_url), 64, _on_launcher_version.bind(h, v)):
		h.queue_free()


func _on_launcher_version(result: int, code: int, body: PackedByteArray, h: HTTPRequest, v: Dictionary) -> void:
	var txt := body.get_string_from_utf8().strip_edges()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not txt.is_valid_int() or txt.to_int() <= Version.LAUNCHER_VERSION:
		h.queue_free()
		return
	if not _fetch(h, String(v.sums_url), Releases.MAX_SMALL_BYTES, _on_launcher_sums.bind(h, v)):
		h.queue_free()


func _on_launcher_sums(result: int, code: int, body: PackedByteArray, h: HTTPRequest, v: Dictionary) -> void:
	var sha := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		sha = String(Releases.parse_sums(body.get_string_from_utf8()).get(String(v.launcher_name), ""))
	if sha == "":
		print("[launcher] mise à jour du lanceur ignorée : somme SHA-256 absente")
		h.queue_free()
		return
	var exe := OS.get_executable_path()
	var fresh := exe.get_base_dir() + "/ClaudeOfDutyZombie-Launcher.new.exe"
	var part := fresh + ".part"
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	var size := int(v.launcher_size)
	if not _fetch(h, String(v.launcher_url), size if size > 0 else Releases.MAX_EXE_BYTES,
			_on_launcher_downloaded.bind(h, exe, fresh, sha, size), part, 0.0):
		h.queue_free()


func _on_launcher_downloaded(result: int, code: int, _b: PackedByteArray, h: HTTPRequest, exe: String, fresh: String, sha: String, size: int) -> void:
	h.queue_free()
	var part := fresh + ".part"
	# Vérifié AVANT de remplacer le lanceur : sinon supprimé, l'ancien reste.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not Store.verify_file(part, sha, size):
		print("[launcher] nouveau lanceur refusé (téléchargement incomplet ou SHA-256 différente)")
		if FileAccess.file_exists(part):
			DirAccess.remove_absolute(part)
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_set_status(Texts.t("integrity_failed_launcher", lang))
		return
	if FileAccess.file_exists(fresh):
		DirAccess.remove_absolute(fresh)
	if DirAccess.rename_absolute(part, fresh) != OK:
		return
	# Remplacement après fermeture (un exécutable ouvert ne peut pas être écrasé).
	var bat := ProjectSettings.globalize_path("user://update_launcher.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		return
	# « % » est spécial dans un .bat : doublé dans les chemins.
	var cur := exe.replace("/", "\\").replace("%", "%%")
	var nxt := fresh.replace("/", "\\").replace("%", "%%")
	f.store_string("@echo off\r\nping 127.0.0.1 -n 3 >nul\r\nmove /y \"%s\" \"%s\" >nul\r\nstart \"\" \"%s\"\r\ndel \"%%~f0\"\r\n" % [nxt, cur, cur])
	f.close()
	_set_status(Texts.t("self_update", lang))
	OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	get_tree().quit()


# --------------------------------------------------------------------------
# Capture (tests, notes de version)
# --------------------------------------------------------------------------

func _capture_later(path: String) -> void:
	# Fenêtre hors écran (lancer avec --position -20000,-20000 et no_focus :
	# elle ne dérange pas l'utilisateur), puis image et sortie ; 20 s au plus.
	DisplayServer.window_set_position(Vector2i(-20000, -20000))
	get_tree().create_timer(20.0).timeout.connect(get_tree().quit)
	for i in 240:
		await get_tree().process_frame
		if _http_api.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and i > 60 and _img_loading == "" and _image_queue.is_empty():
			break
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[launcher] capture : ", path)
	get_tree().quit()
