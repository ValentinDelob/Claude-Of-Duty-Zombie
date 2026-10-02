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
## --quit-after-update (test : se ferme après la mise à jour automatique),
## --open=settings (ouvre les réglages, pour une capture).

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")
const Texts := preload("res://scripts/texts.gd")
const Version := preload("res://scripts/version.gd")
const Downloader := preload("res://scripts/downloader.gd")

const Look := preload("res://scripts/look.gd")
## Image du jeu en fond de l'accueil.
const BACKGROUND := "res://assets/background.jpg"

# Couleurs (identité visuelle : scripts/look.gd).
const BONE := Look.PAPER
const DIM := Look.DIM
## États de la ligne d'état (_set_status) : sa couleur.
const ST_BUSY := "busy"
const ST_ERROR := "error"
const ST_OFFLINE := "offline"

var settings := {}
var lang := "fr"
var versions: Array = []        # versions publiées (Releases.parse_releases)
var changelogs: Dictionary = {}
var online := true
var _known := false             # liste des versions connue (en ligne ou hors ligne confirmé)
var selected := "latest"        # « latest » ou un numéro de version (du canal choisi)
var channel := "stable"         # canal affiché : Releases.STABLE ou Releases.SNAPSHOT
var _textures := {}             # nom d'image -> Texture2D
var _image_queue: Array = []
var _args := {}
var _ui_scale := 1.0            # échelle de l'interface (_fit_screen)

var _list: ItemList
var _list_tags: Array = []
var _title: Label
var _date: Label
var _items: VBoxContainer
var _images: HFlowContainer
var _bg: TextureRect              # image du jeu (_frame_background)
var _bubble: PanelContainer      # bulle des notes
var _tail: Panel                 # sa pointe, en face de la version choisie
var _notes_label: Label
var _notes_scroll: ScrollContainer
var _status: Label
var _progress: ProgressBar
var _play: Button
var _delete: Button
var _lang_btn: OptionButton
var _channel_btns: Array = []   # interrupteur de canal : [STABLE, SNAPSHOT]
var _settings_btn: Button
var _settings: PanelContainer
var _settings_grid: GridContainer
var _settings_note: Label
var _progress_failed := false  # barre en rouge (échec) ou en lueur
## Téléchargement des versions en paquets (manifeste) : reprise, sommes.
var _dl: Node
var _dl_manifest := {}          # manifeste vérifié de la version en cours
var _dl_manifest_text := ""
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
	var crashes := _session_begin()
	channel = String(settings.get("channel", Releases.STABLE))
	selected = _selected_of(channel)
	get_window().title = "Claude of Duty Zombie"
	_fit_screen()
	_build_ui()
	_http_api = _new_http()
	_http_notes = _new_http()
	_http_img = _new_http()
	_http_dl = _new_http()
	_dl = Downloader.new()
	_dl.name = "Parts"
	add_child(_dl)
	_dl.finished.connect(_on_parts_done)
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
	# Capture d'un écran précis (tests, notes de version) : --open=settings.
	if String(_args.get("open", "")) == "settings":
		_show_settings(true)
	if _args.has("capture"):
		_capture_later(String(_args.capture))
	if not crashes.is_empty():
		_show_crash_note(crashes[crashes.size() - 1])
	_after_self_update()


## Même rendu quelle que soit la résolution de l'écran : l'interface (tailles
## des maquettes, Look) est multipliée par Look.screen_factor() de l'écran de
## la fenêtre, textes rendus à leur taille finale (canvas_items, jamais une
## image agrandie). L'échelle ne suit pas la taille de la fenêtre : agrandie,
## elle donne plus de place (content_scale_size suit la fenêtre). Capture
## (--capture) : échelle 1, image à la taille des maquettes ; --ui-scale=2
## (avec --resolution) impose une échelle (vérifier le rendu 4K).
func _fit_screen() -> void:
	var w := get_window()
	var screen := w.current_screen
	_ui_scale = 1.0 if _args.has("capture") else Look.screen_factor(DisplayServer.screen_get_size(screen))
	if _args.has("ui-scale"):
		_ui_scale = clampf(float(_args["ui-scale"]), 0.6, 4.0)
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.min_size = Vector2i(Vector2(Look.WINDOW_MIN) * _ui_scale)
	if w.mode == Window.MODE_WINDOWED and _ui_scale != 1.0 and not _args.has("capture"):
		var area := DisplayServer.screen_get_usable_rect(screen)
		var want := Vector2i(Vector2(Look.WINDOW) * _ui_scale).min(area.size)
		w.size = want
		w.position = area.position + (area.size - want) / 2
	_follow_window_size()
	w.size_changed.connect(_follow_window_size)
	print("[launcher] écran %s : échelle %.2f" % [DisplayServer.screen_get_size(screen), _ui_scale])


func _follow_window_size() -> void:
	var w := get_window()
	w.content_scale_size = Vector2i((Vector2(w.size) / _ui_scale).round())


## Démarrage après une auto-mise à jour (Store.update_script) : --updated,
## le nouveau lanceur signale qu'il a bien démarré (sinon l'ancien est remis) ;
## --update-failed : l'ancien lanceur a été remis, le joueur en est informé.
func _after_self_update() -> void:
	if _args.has("updated"):
		var f := FileAccess.open(Store.UPDATE_OK, FileAccess.WRITE)
		if f:
			f.store_string(str(Version.LAUNCHER_VERSION))
			f.close()
		print("[launcher] mise à jour du lanceur réussie (version %d)" % Version.LAUNCHER_VERSION)
		_set_status(Texts.t("launcher_updated", lang))
	elif _args.has("update-failed"):
		print("[launcher] la mise à jour du lanceur a échoué : ancienne version remise")
		_set_status(Texts.t("launcher_update_failed", lang))


# --------------------------------------------------------------------------
# Journal et plantages (CrashLog, docs/ARCHITECTURE.md « Journaux et plantages »)
# --------------------------------------------------------------------------

## Session du lanceur : marqueur posé (exe exporté seulement, jamais dans les
## tests), rapports des sessions plantées. Renvoie les rapports créés.
func _session_begin() -> PackedStringArray:
	if not CrashLog.player_session():
		return PackedStringArray()
	return CrashLog.begin_session(OS.get_user_data_dir(), CrashLog.log_path(),
		{"programme": "Lanceur / Launcher", "version": str(Version.LAUNCHER_VERSION), "ecran": "lanceur"})


## Fermeture normale (jouer, mise à jour, fenêtre fermée) : marqueur retiré.
func _exit_tree() -> void:
	if CrashLog.player_session():
		CrashLog.end_session(OS.get_user_data_dir())


## Message discret sous l'état : où trouver le rapport du plantage.
func _show_crash_note(report: String) -> void:
	var l := Label.new()
	l.name = "CrashNote"
	l.text = Texts.t("crashed", lang) % report
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", DIM)
	_status.get_parent().add_child(l)


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

## Accueil (maquette A validée le 02/10/2026) : image du jeu en fond, nom et
## boutons par-dessus, versions dans une colonne à gauche, notes de la version
## choisie dans une bulle à part (sa pointe suit la version choisie), état et
## JOUER en bas. Placements fixes en pixels des maquettes (Look) : agrandie, la
## fenêtre montre plus de fond, jamais des éléments plus gros.
func _build_ui() -> void:
	theme = Look.theme()
	var ink := ColorRect.new()
	ink.color = Look.INK
	ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ink)
	_bg = TextureRect.new()
	_bg.name = "Background"
	_bg.texture = _background()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_add_scrims()

	# En-tête : le nom au pochoir (pas de logo), langue, réglages.
	var head := _head_bar(true)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(head)

	# Colonne des versions : canal (un seul endroit, un interrupteur), liste.
	var left_box := PanelContainer.new()
	left_box.name = "Versions"
	left_box.add_theme_stylebox_override("panel", Look.box(Look.PANEL, 12, 12, Look.STEEL, Look.BORDER))
	left_box.anchor_bottom = 1.0
	left_box.offset_left = Look.GUTTER
	left_box.offset_top = Look.HEAD_H
	left_box.offset_right = Look.GUTTER + Look.LIST_W
	left_box.offset_bottom = -Look.PANEL_BOTTOM
	add_child(left_box)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left_box.add_child(left)
	var sw_box := PanelContainer.new()
	sw_box.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), 0, 0, Look.STEEL, Look.BORDER))
	left.add_child(sw_box)
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 0)
	sw_box.add_child(sw)
	var group := ButtonGroup.new()
	_channel_btns = []
	for i in 2:
		var b := Button.new()
		b.name = "ChannelSnapshot" if i == 1 else "ChannelStable"
		b.button_group = group
		Look.switch_button(b, i == 1)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (i == 1) == (channel == Releases.SNAPSHOT)
		b.pressed.connect(_on_channel.bind(i))
		sw.add_child(b)
		_channel_btns.append(b)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_select)
	_list.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _place_tail())
	_list.resized.connect(_place_tail)
	left.add_child(_list)

	# Bulle des notes : étiquette et numéro, titre, puces, captures.
	_bubble = PanelContainer.new()
	_bubble.name = "Notes"
	var bs := Look.box(Color(Look.INK, 0.9), 0, 0, Look.STEEL, Look.BORDER)
	bs.content_margin_left = 26
	bs.content_margin_right = 26
	bs.content_margin_top = 22
	bs.content_margin_bottom = 24
	bs.shadow_color = Color(0, 0, 0, 0.55)
	bs.shadow_size = 20
	bs.shadow_offset = Vector2(0, 18)
	_bubble.add_theme_stylebox_override("panel", bs)
	_bubble.position = Vector2(Look.BUBBLE_X, Look.BUBBLE_Y)
	_bubble.custom_minimum_size = Vector2(Look.BUBBLE_W, 0)
	add_child(_bubble)
	# Pointe : carré tourné, bords gauche et bas, à cheval sur le bord gauche.
	_tail = Panel.new()
	_tail.name = "Tail"
	var ts := Look.box(Look.INK)
	ts.border_color = Look.STEEL
	ts.border_width_left = Look.BORDER
	ts.border_width_bottom = Look.BORDER
	_tail.add_theme_stylebox_override("panel", ts)
	_tail.size = Vector2(Look.TAIL, Look.TAIL)
	_tail.pivot_offset = _tail.size / 2
	_tail.rotation_degrees = 45
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tail)
	var notes := VBoxContainer.new()
	notes.add_theme_constant_override("separation", 10)
	_bubble.add_child(notes)
	var tag_row := HBoxContainer.new()
	notes.add_child(tag_row)
	_notes_label = Label.new()
	_notes_label.add_theme_font_override("font", Look.spaced(Look.label_font(), 3))
	_notes_label.add_theme_font_size_override("font_size", Look.SIZE_SMALL)
	_notes_label.add_theme_color_override("font_color", Look.ALARM)
	_notes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_row.add_child(_notes_label)
	_date = Label.new()
	_date.add_theme_font_override("font", Look.file_font())
	_date.add_theme_font_size_override("font_size", Look.SIZE_SMALL)
	_date.add_theme_color_override("font_color", Look.DIM)
	tag_row.add_child(_date)
	_title = Label.new()
	_title.add_theme_font_override("font", Look.display_font())
	_title.add_theme_font_size_override("font_size", Look.SIZE_TITLE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(_title)
	# Puces et captures : défilent dans la bulle si elles dépassent.
	_notes_scroll = ScrollContainer.new()
	_notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	notes.add_child(_notes_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	_notes_scroll.add_child(body)
	# Nouveautés : une ligne par puce (carré d'alerte, texte en clair).
	_items = VBoxContainer.new()
	_items.add_theme_constant_override("separation", 9)
	body.add_child(_items)
	_images = HFlowContainer.new()
	_images.add_theme_constant_override("h_separation", 12)
	_images.add_theme_constant_override("v_separation", 12)
	body.add_child(_images)

	# Pied : état, progression, supprimer, jouer.
	var foot := _foot_bar()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -Look.FOOT_H
	add_child(foot)
	var row: HBoxContainer = foot.get_child(0)
	row.add_theme_constant_override("separation", 20)
	# État sur ≈ 520 px (maquette), puis un vide jusqu'aux boutons.
	var st := VBoxContainer.new()
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.size_flags_stretch_ratio = 2.0
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.add_theme_constant_override("separation", 8)
	row.add_child(st)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 11)
	_progress.show_percentage = false
	Look.progress(_progress)
	_progress.visible = false
	st.add_child(_progress)
	_delete = Button.new()
	_delete.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_delete.pressed.connect(_on_delete)
	row.add_child(_delete)
	_play = Button.new()
	_play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Look.play_button(_play)
	_play.pressed.connect(_on_play)
	row.add_child(_play)
	resized.connect(_fit_bubble_later)
	resized.connect(_frame_background)
	_frame_background.call_deferred()

	_build_settings()

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


## Image de fond (assets/background.jpg) ; absente : nuit du bunker seule.
func _background() -> Texture2D:
	return load(BACKGROUND) as Texture2D if ResourceLoader.exists(BACKGROUND) else null


## Cadrage de l'image : couvre la fenêtre, agrandie de Look.BG_ZOOM, et son
## point clair (Look.BG_FOCUS : rayons, lustre) placé à Look.BG_AT de la
## fenêtre, à droite de la bulle ; jamais de bord vide.
func _frame_background() -> void:
	if _bg == null or _bg.texture == null:
		return
	var tex := Vector2(_bg.texture.get_size())
	var k := maxf(size.x / tex.x, size.y / tex.y) * Look.BG_ZOOM
	var shown := tex * k
	var pos := size * Look.BG_AT - shown * Look.BG_FOCUS
	_bg.size = shown
	_bg.position = pos.clamp(size - shown, Vector2.ZERO)


## Voiles sombres sur l'image : de gauche à droite (colonne lisible), en haut
## (nom, boutons) et en bas (état, JOUER), hauteurs fixes en pixels des maquettes.
func _add_scrims() -> void:
	var sides := [
		[Control.PRESET_FULL_RECT, 0, false, PackedFloat32Array([0.0, 0.34, 0.7, 1.0]), [0.9, 0.55, 0.12, 0.3]],
		[Control.PRESET_TOP_WIDE, Look.SCRIM_TOP, true, PackedFloat32Array([0.0, 1.0]), [0.85, 0.0]],
		[Control.PRESET_BOTTOM_WIDE, Look.SCRIM_BOTTOM, true, PackedFloat32Array([0.0, 0.56, 1.0]), [0.0, 0.75, 0.97]],
	]
	for s: Array in sides:
		var g := Gradient.new()
		g.offsets = s[3]
		var cols := PackedColorArray()
		for a: float in s[4]:
			cols.append(Color(Look.INK, a))
		g.colors = cols
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 4 if s[2] else 256
		tex.height = 256 if s[2] else 4
		tex.fill_to = Vector2(0, 1) if s[2] else Vector2(1, 0)
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(s[0])
		if s[0] == Control.PRESET_TOP_WIDE:
			r.offset_bottom = s[1]
		elif s[0] == Control.PRESET_BOTTOM_WIDE:
			r.offset_top = -s[1]
		add_child(r)


## Après la mise en page (puces repliées à la largeur de la bulle) : deux images.
func _fit_bubble_later() -> void:
	for i in 2:
		await get_tree().process_frame
		_fit_bubble()


## Hauteur de la bulle : celle de son contenu, bornée au-dessus du pied (au-delà,
## les puces défilent) ; puis la pointe.
func _fit_bubble() -> void:
	if _bubble == null:
		return
	var room := size.y - Look.PANEL_BOTTOM - Look.BUBBLE_Y
	var fixed := _bubble.get_combined_minimum_size().y - _notes_scroll.custom_minimum_size.y
	var want := (_notes_scroll.get_child(0) as Control).get_combined_minimum_size().y
	_notes_scroll.custom_minimum_size.y = clampf(want, 0.0, maxf(room - fixed, 40.0))
	_bubble.size = Vector2(Look.BUBBLE_W, 0)
	_place_tail()


## Pointe de la bulle en face de la version choisie (bornée aux bords de la bulle).
func _place_tail() -> void:
	if _tail == null or _bubble == null:
		return
	var y := Look.TAIL_Y
	var idx := _list_tags.find(selected)
	if idx >= 0 and idx < _list.item_count:
		var r := _list.get_item_rect(idx)
		var row_mid := _list.global_position.y - global_position.y + r.position.y + r.size.y / 2 - _list.get_v_scroll_bar().value
		y = row_mid - _bubble.position.y - Look.TAIL / 2.0
	y = clampf(y, 14.0, maxf(_bubble.size.y - Look.TAIL - 14.0, 14.0))
	_tail.position = Vector2(_bubble.position.x - Look.TAIL / 2.0 - 2, _bubble.position.y + y)


## Bandeau du haut (128 px) : le nom au pochoir, puis, sur l'accueil (sans
## fond : par-dessus l'image), la langue et RÉGLAGES ; sur les réglages, RETOUR.
func _head_bar(home: bool) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, Look.HEAD_H)
	box.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0) if home else Color("151812"), Look.GUTTER, 0))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var word := VBoxContainer.new()
	word.alignment = BoxContainer.ALIGNMENT_CENTER
	word.add_theme_constant_override("separation", -9)
	head.add_child(word)
	var top := Label.new()
	top.text = "CLAUDE OF DUTY"
	top.add_theme_font_override("font", Look.spaced(Look.display_font(), 7))
	top.add_theme_font_size_override("font_size", Look.SIZE_NAME_TOP)
	top.add_theme_color_override("font_color", Look.DIM)
	word.add_child(top)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 0)
	word.add_child(name_row)
	for part: Array in [["ZOMB", Look.PAPER], ["IE", Look.ALARM]]:
		var l := Label.new()
		l.text = part[0]
		l.add_theme_font_override("font", Look.spaced(Look.display_font(), 1))
		l.add_theme_font_size_override("font_size", Look.SIZE_NAME)
		l.add_theme_color_override("font_color", part[1])
		name_row.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if home:
		_lang_btn = OptionButton.new()
		_lang_btn.add_item("FR")
		_lang_btn.add_item("EN")
		_lang_btn.select(0 if lang == "fr" else 1)
		_lang_btn.item_selected.connect(_on_lang)
		_lang_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(_lang_btn)
		_settings_btn = Button.new()
		_settings_btn.name = "SettingsButton"
		_settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_settings_btn.pressed.connect(_show_settings.bind(true))
		head.add_child(_settings_btn)
	else:
		var back := Button.new()
		back.name = "Back"
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back.pressed.connect(_show_settings.bind(false))
		head.add_child(back)
	return box


## Bandeau du bas (110 px) ; son premier enfant reçoit le contenu.
func _foot_bar() -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, Look.FOOT_H)
	box.add_theme_stylebox_override("panel", Look.box(Color("0b0d09"), Look.GUTTER, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	return box


func _padded(c: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.add_child(c)
	return m


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Look.STEEL
	r.custom_minimum_size = Vector2(0, Look.BORDER)
	return r


func _vrule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Look.STEEL
	r.custom_minimum_size = Vector2(Look.BORDER, 0)
	return r


## Une puce des notes : carré d'alerte et texte (sans balise : texte en clair).
func _note_line(text: String, dim := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if not dim:
		var holder := VBoxContainer.new()
		var sq := ColorRect.new()
		sq.color = Look.ALARM
		sq.custom_minimum_size = Vector2(9, 9)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 5)
		holder.add_child(pad)
		holder.add_child(sq)
		holder.add_theme_constant_override("separation", 0)
		row.add_child(holder)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_constant_override("line_spacing", 4)
	if dim:
		l.add_theme_color_override("font_color", Look.DIM)
	row.add_child(l)
	return row


# --------------------------------------------------------------------------
# Réglages (écran par-dessus l'accueil) : langue, dossier et place prise,
# paquets inutilisés, journaux, à propos. Le canal se choisit sur l'accueil.
# --------------------------------------------------------------------------

func _build_settings() -> void:
	_settings = PanelContainer.new()
	_settings.name = "Settings"
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.add_theme_stylebox_override("panel", Look.box(Look.INK, 0))
	_settings.visible = false
	add_child(_settings)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_settings.add_child(col)
	col.add_child(_head_bar(false))
	col.add_child(_rule())
	var mid := MarginContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		mid.add_theme_constant_override("margin_" + side, Look.GUTTER)
	for side in ["top", "bottom"]:
		mid.add_theme_constant_override("margin_" + side, 28)
	col.add_child(mid)
	_settings_grid = GridContainer.new()
	_settings_grid.columns = 2
	_settings_grid.add_theme_constant_override("h_separation", Look.GUTTER)
	_settings_grid.add_theme_constant_override("v_separation", 18)
	mid.add_child(_settings_grid)
	col.add_child(_rule())
	var foot := _foot_bar()
	col.add_child(foot)
	_settings_note = Label.new()
	_settings_note.add_theme_color_override("font_color", Look.DIM)
	_settings_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.get_child(0).add_child(_settings_note)


func _show_settings(on: bool) -> void:
	if on:
		_fill_settings()
	_settings.visible = on


## Contenu des réglages (recalculé à chaque ouverture et changement de langue).
func _fill_settings() -> void:
	for c in _settings_grid.get_children():
		c.queue_free()
	(find_child("Back", true, false) as Button).text = Texts.t("back", lang)
	_settings_note.text = ""
	# Langue.
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 10)
	for i in 2:
		var b := Button.new()
		b.text = "FRANÇAIS" if i == 0 else "ENGLISH"
		b.toggle_mode = true
		b.button_pressed = (i == 1) == (lang == "en")
		b.pressed.connect(func() -> void:
			_lang_btn.select(i)
			_on_lang(i))
		lr.add_child(b)
	_setting(Texts.t("s_lang", lang), lr, Texts.t("s_lang_help", lang))
	# Dossier des versions et place prise.
	var n := Store.installed().size()
	var total := Store.dir_bytes(Store.data_dir())
	var engine := Store.dir_bytes(Store.engines_dir())
	var open := Button.new()
	open.text = Texts.t("s_open", lang)
	open.pressed.connect(func() -> void: OS.shell_open(Store.data_dir()))
	var space := Texts.t("s_space", lang) % [n, _mb(total)] + (Texts.t("s_space_engine", lang) % _mb(engine) if engine > 0 else "")
	_setting(Texts.t("s_folder", lang), open, space, Store.data_dir())
	# Paquets que plus aucune version n'utilise.
	var unused := Store.unused_bytes()
	var clean := Button.new()
	clean.text = Texts.t("s_clean_btn", lang) % _mb(unused)
	clean.disabled = unused == 0
	clean.pressed.connect(func() -> void:
		var removed := Store.prune_store()
		print("[launcher] paquets inutilisés supprimés : %d" % removed)
		_fill_settings()
		_settings_note.text = Texts.t("s_clean_done", lang))
	_setting(Texts.t("s_clean", lang), clean, Texts.t("s_clean_help", lang))
	# Journaux et rapports de plantage.
	var logs := ProjectSettings.globalize_path("user://logs")
	var open_logs := Button.new()
	open_logs.text = Texts.t("s_open", lang)
	open_logs.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(logs)
		OS.shell_open(logs))
	_setting(Texts.t("s_logs", lang), open_logs, Texts.t("s_logs_help", lang), logs)
	# À propos.
	_setting(Texts.t("s_about", lang), null, Texts.t("s_about_txt", lang) % Version.LAUNCHER_VERSION)


## Un bloc des réglages : titre, commande, chemin (police de dossier, laiton), aide.
func _setting(title: String, control: Control, help: String, path := "") -> void:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", Look.box(Look.CONCRETE, 16, 16, Look.STEEL, Look.BORDER))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", Look.label_font())
	t.add_theme_font_size_override("font_size", Look.SIZE_FIELD)
	v.add_child(t)
	if control:
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(control)
	if path != "":
		var c := Label.new()
		c.text = path
		c.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		c.add_theme_font_override("font", Look.file_font())
		c.add_theme_font_size_override("font_size", Look.SIZE_SMALL)
		c.add_theme_color_override("font_color", Look.BRASS)
		v.add_child(c)
	var h := Label.new()
	h.text = help
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_theme_color_override("font_color", Look.DIM)
	h.add_theme_font_size_override("font_size", Look.SIZE_HELP)
	v.add_child(h)
	_settings_grid.add_child(p)


static func _mb(bytes: int) -> String:
	return str(int(round(float(bytes) / 1048576.0)))


func _apply_texts() -> void:
	_play.text = Texts.t("play", lang)
	_delete.text = Texts.t("delete", lang)
	_settings_btn.text = Texts.t("settings", lang)
	_channel_btns[0].text = Texts.t("channel_stable", lang)
	_channel_btns[1].text = Texts.t("channel_snapshot", lang)
	if _settings and _settings.visible:
		_fill_settings()
	_refresh_list()


## Ligne d'état ; `kind` donne sa couleur : "" normal, "busy" en cours (lueur),
## "error" échec (alerte), "offline" hors ligne (laiton).
func _set_status(t: String, kind := "") -> void:
	_status.text = t
	var c: Color = {ST_BUSY: Look.NEON, ST_ERROR: Look.ALARM, ST_OFFLINE: Look.BRASS}.get(kind, Look.PAPER)
	_status.add_theme_color_override("font_color", c)
	if (kind == ST_ERROR) != _progress_failed:
		_progress_failed = kind == ST_ERROR
		Look.progress(_progress, _progress_failed)


# --------------------------------------------------------------------------
# Versions
# --------------------------------------------------------------------------

## Versions affichées : celles du canal choisi, publiées (en ligne) ou
## installées (hors ligne ; canal d'après le numéro).
func _all_tags() -> Array:
	var tags: Array = []
	for v in versions:
		if String(v.get("channel", Releases.STABLE)) == channel:
			tags.append(v.tag)
	for t: String in Store.installed():
		if not t in tags and _info(t).is_empty() and Releases.channel_of(t) == channel:
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
		_list.add_item("★  %s  (%s)" % [Texts.t("latest" if channel == Releases.STABLE else "latest_snapshot", lang), latest])
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
	settings["selected" if channel == Releases.STABLE else "selected_snapshot"] = selected
	Store.save_settings(settings)
	_show_notes()


## Version choisie (mémorisée) dans un canal : « latest » ou un numéro.
func _selected_of(ch: String) -> String:
	return String(settings.get("selected" if ch == Releases.STABLE else "selected_snapshot", "latest"))


func _on_channel(i: int) -> void:
	channel = Releases.SNAPSHOT if i == 1 else Releases.STABLE
	settings.channel = channel
	Store.save_settings(settings)
	selected = _selected_of(channel)
	_refresh_list()
	if channel == Releases.SNAPSHOT:
		_set_status(Texts.t("snapshot_note", lang))
	_auto_update()


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
	_notes_label.text = Texts.t("notes", lang)
	var d := String(info.get("date", ""))
	_date.text = tag + ("  ·  " + Texts.date(d, lang) if d != "" else "")
	# Nouveautés en texte simple (Label : aucune balise interprétée). Anciennes
	# lignes retirées tout de suite : la bulle se mesure sans elles.
	for c in _items.get_children():
		_items.remove_child(c)
		c.queue_free()
	for it in n.items:
		_items.add_child(_note_line(String(it)))
	if n.items.is_empty():
		_items.add_child(_note_line(Texts.t("no_notes" if tag != "" else "no_versions", lang), true))
	for c in _images.get_children():
		_images.remove_child(c)
		c.queue_free()
	for img in n.images:
		var b := TextureButton.new()
		b.custom_minimum_size = Look.THUMB
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = Texts.t("click_zoom", lang)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.set_meta("image", img)
		b.pressed.connect(_on_zoom.bind(String(img)))
		_images.add_child(b)
		_fill_image(b, String(img))
	_update_buttons()
	_fit_bubble_later()


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
		if String(_info(tag).get("manifest_url", "")) != "":
			_set_status(Texts.t("to_download_parts", lang))
			return
		_set_status(Texts.t("to_download", lang) % str(int(round(float(_info(tag).exe_size) / 1048576.0)))
				+ ("   " + Texts.t("legacy", lang) if policy == Releases.LEGACY else ""))


func _on_delete() -> void:
	var tag := _resolved()
	if not Store.is_installed(tag) or _dl_tag == tag:
		return
	Store.remove(tag)
	# Paquets que plus aucune version installée n'utilise : supprimés.
	Store.prune_store()
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
	_auto_update()


## Mise à jour automatique : la dernière version du canal est téléchargée à
## l'ouverture (et au changement de canal) quand « Dernière version » est choisie.
func _auto_update() -> void:
	var latest := _latest()
	if online and _known and selected == "latest" and latest != "" and not Store.is_installed(latest) \
			and not _args.has("capture") and _dl_tag == "":
		_start_download(latest, true)


func _set_offline() -> void:
	online = false
	_known = true
	_refresh_list()
	_set_status(Texts.t("offline", lang), ST_OFFLINE)


func _load_cached_changelogs() -> void:
	var f := FileAccess.open("user://changelogs.json", FileAccess.READ)
	if f and f.get_length() <= Releases.MAX_CHANGELOG_BYTES:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			changelogs = d


func _on_changelogs(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() > Releases.MAX_CHANGELOG_BYTES:
		return
	var text := body.get_string_from_utf8()
	var d: Variant = JSON.parse_string(text)
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
	var d: Variant = JSON.parse_string(f.get_as_text())
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
	_dl_manifest = {}
	var ok := false
	if String(info.get("manifest_url", "")) != "":
		# Version en paquets : seulement ce qui manque (docs/RELEASE.md). Les
		# sommes sont obligatoires (manifeste vérifié avant d'être lu).
		ok = policy == Releases.VERIFIED and _fetch(_http_dl, String(info.sums_url), Releases.MAX_SMALL_BYTES, _on_manifest_sums)
	elif policy == Releases.VERIFIED:
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


## Version en paquets, étape 1 : somme du manifeste lue dans SHA256SUMS.txt.
func _on_manifest_sums(result: int, code: int, body: PackedByteArray) -> void:
	var sha := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		sha = String(Releases.parse_sums(body.get_string_from_utf8()).get(Releases.MANIFEST_ASSET, ""))
	if sha == "":
		_fail_download(_dl_tag, "no_checksum")
		return
	_dl_sha256 = sha
	if not _fetch(_http_dl, String(_info(_dl_tag).manifest_url), Releases.MAX_MANIFEST_BYTES, _on_manifest):
		_fail_download(_dl_tag, "download_failed")


## Étape 2 : manifeste reçu, vérifié (somme puis contenu) ; téléchargement des
## seuls fichiers manquants (moteur, paquets), avec reprise.
func _on_manifest(result: int, code: int, body: PackedByteArray) -> void:
	var tag := _dl_tag
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail_download(tag, "download_failed")
		return
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var text := body.get_string_from_utf8()
	var m := Releases.parse_manifest(text, tag)
	if ctx.finish().hex_encode() != _dl_sha256 or m.is_empty():
		print("[launcher] %s : manifeste NON conforme (somme ou contenu), refusé" % tag)
		_fail_download(tag, "integrity_failed")
		return
	_dl_manifest = m
	_dl_manifest_text = text
	var missing := Store.missing_files(m)
	var mb := 0
	for f: Dictionary in missing:
		mb += int(f.size)
	print("[launcher] %s : %d fichier(s) à télécharger (%d Mo)" % [tag, missing.size(), mb >> 20])
	if missing.is_empty():
		_on_parts_done(true, "")
		return
	_dl_size = mb
	_dl.start(missing)


## Étape 3 : fichiers vérifiés rangés ; installation (copies locales).
func _on_parts_done(ok: bool, key: String) -> void:
	var tag := _dl_tag
	if tag == "" or _dl_manifest.is_empty():
		return
	if not ok:
		# Les fichiers partiels restent : le prochain essai reprend à la suite.
		_fail_download(tag, key)
		return
	if not Store.install_manifest(tag, _dl_manifest, _dl_manifest_text):
		_fail_download(tag, "download_failed")
		return
	_dl_manifest = {}
	_dl_tag = ""
	_progress.visible = false
	_refresh_list()
	print("[launcher] installée (paquets) : ", Store.exe_path(tag))
	if _args.has("quit-after-update"):
		get_tree().quit()
		return
	if _play_after and _resolved() == tag:
		_launch(tag)


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
	_dl_manifest = {}
	_play_after = false
	_progress.visible = false
	var part := Store.part_path(tag)
	if part != "" and FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	_refresh_list()
	_set_status(Texts.t(key, lang) % tag, ST_ERROR)


func _process(_delta: float) -> void:
	if _dl_tag == "":
		return
	if _dl.busy():
		var got: int = _dl.progress_bytes()
		var all: int = maxi(_dl.total_bytes, 1)
		var p := 100.0 * float(got) / float(all)
		_progress.value = p
		_set_status(Texts.t("downloading_parts", lang) % [_dl_tag, int(p), str(int(round(float(all) / 1048576.0)))]
				+ ("   " + Texts.t("play_after", lang) if _play_after else ""), ST_BUSY)
		return
	var total := _http_dl.get_body_size()
	if total <= 0:
		total = _dl_size
	var pct := 0.0 if total <= 0 else 100.0 * float(_http_dl.get_downloaded_bytes()) / float(total)
	_progress.value = pct
	_set_status(Texts.t("updating" if _dl_is_update else "downloading", lang) % [_dl_tag, int(pct)]
			+ ("   " + Texts.t("play_after", lang) if _play_after else ""), ST_BUSY)


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
	# Version en paquets : les paquets de répliques sont montés par le jeu.
	var args := Store.launch_args(tag)
	print("[launcher] lancement de %s %s" % [tag, " ".join(args)])
	var pid := OS.create_process(Store.exe_path(tag), args)
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
	# Lanceur de la dernière version du canal choisi : un joueur du canal
	# stable ne reçoit jamais le lanceur d'une snapshot.
	var v := Releases.launcher_release(versions, channel)
	if v.is_empty():
		return
	# Nouveau lanceur jamais installé sans somme SHA-256 publiée avec lui.
	if String(v.sums_url) == "":
		print("[launcher] mise à jour du lanceur ignorée : %s sans %s" % [v.tag, Releases.SUMS_ASSET])
		return
	if Releases.launcher_mode(v) == "":
		return
	var h := _new_http()
	if not _fetch(h, String(v.sums_url), Releases.MAX_SMALL_BYTES, _on_launcher_sums.bind(h, v)):
		h.queue_free()


## Étape 1 : SHA256SUMS.txt de la release. Avec un manifeste : sa somme, puis
## le manifeste (entrée « launcher ») ; sinon l'ancien mécanisme.
func _on_launcher_sums(result: int, code: int, body: PackedByteArray, h: HTTPRequest, v: Dictionary) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		h.queue_free()
		return
	var sums := Releases.parse_sums(body.get_string_from_utf8())
	if Releases.launcher_mode(v) == Releases.LAUNCHER_BY_MANIFEST and sums.has(Releases.MANIFEST_ASSET):
		if not _fetch(h, String(v.manifest_url), Releases.MAX_MANIFEST_BYTES, _on_launcher_manifest.bind(h, v, sums)):
			h.queue_free()
		return
	_launcher_from_assets(h, v, sums)


## Étape 2 (manifeste) : vérifié (somme puis contenu) ; son entrée « launcher »
## décide. Sans cette entrée (snapshots 165 à 167) : ancien mécanisme.
func _on_launcher_manifest(result: int, code: int, body: PackedByteArray, h: HTTPRequest, v: Dictionary, sums: Dictionary) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		h.queue_free()
		return
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var m := Releases.parse_manifest(body.get_string_from_utf8(), String(v.tag))
	if ctx.finish().hex_encode() != String(sums.get(Releases.MANIFEST_ASSET, "")) or m.is_empty():
		print("[launcher] mise à jour du lanceur ignorée : manifeste de %s NON conforme" % v.tag)
		h.queue_free()
		return
	if not m.has("launcher"):
		_launcher_from_assets(h, v, sums)
		return
	var l := Releases.launcher_from_manifest(m, Version.LAUNCHER_VERSION)
	if l.is_empty():
		h.queue_free()
		return
	print("[launcher] lanceur %d disponible (manifeste de %s)" % [l.version, v.tag])
	_download_launcher(h, l)


## Ancien mécanisme : launcher_version.txt et lanceur joints à la release.
func _launcher_from_assets(h: HTTPRequest, v: Dictionary, sums: Dictionary) -> void:
	if not Releases.has_launcher_assets(v) or not _fetch(h, String(v.launcher_version_url), 64, _on_launcher_version.bind(h, v, sums)):
		h.queue_free()


func _on_launcher_version(result: int, code: int, body: PackedByteArray, h: HTTPRequest, v: Dictionary, sums: Dictionary) -> void:
	var txt := body.get_string_from_utf8() if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
	var l := Releases.launcher_from_assets(v, txt, sums, Version.LAUNCHER_VERSION)
	if l.is_empty():
		if txt.strip_edges().is_valid_int() and txt.to_int() > Version.LAUNCHER_VERSION:
			print("[launcher] mise à jour du lanceur ignorée : somme SHA-256 absente")
		h.queue_free()
		return
	print("[launcher] lanceur %d disponible (fichiers joints à %s)" % [l.version, v.tag])
	_download_launcher(h, l)


## Étape finale : téléchargement dans un fichier partiel, vérifié (taille,
## SHA-256) avant tout remplacement.
func _download_launcher(h: HTTPRequest, l: Dictionary) -> void:
	var exe := OS.get_executable_path()
	var fresh := exe.get_base_dir() + "/ClaudeOfDutyZombie-Launcher.new.exe"
	var part := fresh + ".part"
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	var size := int(l.size)
	if not _fetch(h, String(l.url), size if size > 0 else Releases.MAX_EXE_BYTES,
			_on_launcher_downloaded.bind(h, exe, fresh, String(l.sha256), size), part, 0.0):
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
	# Remplacement après fermeture (un exécutable ouvert ne peut pas être
	# écrasé), redémarrage automatique et retour à l'ancien lanceur si le
	# nouveau ne démarre pas (Store.update_script).
	var bat := ProjectSettings.globalize_path("user://update_launcher.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Store.UPDATE_LOG).get_base_dir())
	f.store_string(Store.update_script(exe, fresh, ProjectSettings.globalize_path(Store.UPDATE_OK),
		ProjectSettings.globalize_path(Store.UPDATE_LOG)))
	f.close()
	print("[launcher] mise à jour du lanceur : script ", bat)
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
