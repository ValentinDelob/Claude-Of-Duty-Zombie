class_name MapEditor
extends Control
## ÉDITEUR DE CARTES (docs/MAP_AUTHORING.md) : vue de dessus (MapCanvas),
## inventaire façon Minecraft (barre rapide de 9 cases + inventaire complet,
## MapHotbar / MapInventory), panneaux (MapPanels : propriétés, pièces, zones,
## étages, vérification), fichiers (dossier de cinq JSON, archive .zip),
## annuler / rétablir (par auteur, MapHistory), enregistrement explicite
## seulement, avec confirmation avant de perdre des modifications et copie de
## récupération (MapUnsaved), sélection multiple et actions de groupe
## (MapGroup), menu du clic droit (MapContextMenu), bouton
## Tester (partie solo sur la carte éditée), édition à plusieurs et avec
## Claude (menu Collaboration : MapCollab, MapAgentLink, docs/MAP_COLLAB.md).
## Lançable depuis le menu principal ou directement :
##   godot --path . res://scenes/editor/map_editor.tscn

const SCENE := "res://scenes/editor/map_editor.tscn"
## Copie de récupération (MapUnsaved) : toutes les 60 s s'il y a du nouveau.
const RECOVERY_EVERY := 60.0
const RECENT_MAX := 8
const PANEL_W := 340.0
## TESTER en solo : session d'édition (MapCollab : carte, historique) et état
## de l'éditeur gardés pendant la partie, repris au retour ({collab, state}) ;
## vide sinon.
static var _test_keep: Dictionary = {}

var doc: EditorMap:
	set(v):
		doc = v
		if collab != null:
			collab.doc = v
		# Format 10 : les prefabs de cette carte dans le catalogue (inventaire).
		if v != null:
			v.activate_prefabs()
## Prefabs de la carte (format 10) : création, import, renommage (MapPrefabTools).
var prefab_tools: MapPrefabTools
## Textures de la carte (format 16) : import, réglages, suppression (MapTextureTools).
var texture_tools: MapTextureTools
## Dossier d'enregistrement ("" : jamais enregistrée).
var map_dir := ""
## Ouverte depuis un exemple livré (assets/maps/) : Enregistrer en fait une copie.
var example := false
## Modifications non enregistrées (étoile du titre) : empreinte de la carte
## (MapUnsaved.signature) différente de celle de l'état enregistré, recalculée
## quand la carte a changé (doc_version). `dirty = false` : l'état courant
## devient l'état enregistré ; `dirty = true` : modifiée quoi qu'il arrive
## (carte importée, supprimée du disque) jusqu'au prochain enregistrement.
var dirty: bool:
	get:
		if _dirty_ver != doc_version:
			_dirty_ver = doc_version
			_dirty = _saved_sig == "" or MapUnsaved.signature(doc) != _saved_sig
		return _dirty
	set(v):
		_saved_sig = "" if v else MapUnsaved.signature(doc)
		_dirty_ver = -1
var _dirty := false
var _dirty_ver := -1
## Empreinte de l'état enregistré ("" : à enregistrer quoi qu'il arrive).
var _saved_sig := ""
## Empreinte de la dernière copie de récupération écrite.
var _recovery_sig := ""
## Une copie de récupération attend la réponse de l'utilisateur (Récupérer /
## Ignorer) : rien ne l'écrase ni ne l'efface d'ici là.
var _recovery_pending := false
## Invité d'une session au dernier changement de session (départ de l'invité).
var _was_guest := false
## Session d'édition (docs/MAP_COLLAB.md) : seul, hôte ou invité ; tient
## l'historique (MapHistory, annuler / rétablir par auteur).
var collab: MapCollab
## Retour d'un TESTER à plusieurs (CollabPlaytest.take) : état de l'éditeur à
## retrouver ({state, message, error}), traité par _start ; vide sinon.
var _playtest_back: Dictionary = {}
## Liaison avec une IA (commandes pour le serveur MCP du jeu, MapAgentLink).
var agent_link: MapAgentLink
## Menu Collaboration et participants (CollabPanel).
var collab_ui: CollabPanel
## Rendu de la collaboration sur le plan (curseurs, sélections, aperçus,
## lots de Claude…, CollabView).
var collab_view: CollabView
## Aperçu en direct envoyé aux autres pendant un glissement (presence.live :
## {coll, el}) ; vide sinon.
var live: Dictionary = {}
var _live_ms := -1000000
## Aperçu en direct : 10 envois par seconde au plus.
const LIVE_EVERY_MS := 100
## Carte d'avant le changement en cours (push_undo) : le diff est calculé et
## inscrit par changed().
var _before: Dictionary = {}
## Niveau affiché (indice dans doc.levels()) ; format 17 : le niveau suit son
## ALTITUDE (_view_alt) quand les niveaux changent (pièce déplacée, supprimée).
var floor_k := 0
var _view_alt := 0.0
## Élément choisi quand UN seul l'est ("" sinon ; sélection multiple : `group`).
var selected := ""
## Sélection multiple (docs/MAP_AUTHORING.md § 2, MapGroup) : identifiants des
## éléments choisis quand il y en a au moins deux (`selected` vaut alors "") ;
## vide sinon. sel_ids() rend la sélection dans les deux cas.
var group: Array = []
## Change à chaque changement de sélection (redessin des élévations).
var sel_version := 0
## Menu du clic droit (MapContextMenu), créé au premier usage.
var context_menu: MapContextMenu
## Presse-papiers : un élément (Ctrl+C sur un seul), ou {"items": [...]} (groupe).
var clipboard: Dictionary = {}
var ghost_below := true
var hotbar: Array = MapHotbar.migrate(MapCatalog.DEFAULT_HOTBAR)
## Case choisie de la barre rapide ; MOUSE (-1) : la souris (outil Sélection),
## case fixe à gauche de la barre, jamais remplacée. L'éditeur démarre dessus.
var hot_index := MOUSE
## Dernière case (0 à 8) choisie : un objet pris dans l'inventaire souris en
## main y va quand la barre est pleine.
var last_slot := 0
## Rotation (degrés) de l'objet tenu (prefabs, luminaires) : R avant de poser.
var place_rot := 0
## Variante de l'objet tenu (portes, débris, armes murales : V avant de
## poser) ; "" : l'aspect par défaut.
var place_variant := ""
## Élément survolé (liste des objets ou carte) : contour lumineux sur la carte.
var hover_id := ""
## Éléments posés devenus invalides (dessinés en rouge) : id -> raison.
var invalid: Dictionary = {}
var validator: MapValidator
var validation_stale := true
var _raster: MapRaster
var _raster_dirty := true
## Version de la carte : augmente à chaque modification (caches des vues :
## boîtes des élévations, MapElevation).
var doc_version := 0
## Ce que montrent les vues a changé (coupe, étages, plan) : elles se redessinent.
var views_stamp := 0
var _elev_items: Array = []
var _elev_ver := -1
var _recovery_t := 0.0
var _validate_t := -1.0

var canvas: MapCanvas
## Zone des vues (MapViewLayout) : vues, barre rapide, inventaire.
var views: MapViewLayout
var panels: MapPanels
## Onglet déployable « Objets sur la carte » (à gauche de la vue).
var object_list: MapObjectList
var hotbar_ui: MapHotbar
var inventory: MapInventory
## Aperçu 3D en direct (MapPreviewPanel : bouton APERÇU 3D, touche P).
var preview: MapPreviewPanel
var status: Label
var cursor_label: Label
var title_label: Label
var floor_label: Label
var check_button: Button
## Mode d'aimantation (clic ou G : grille 1 m, grille fine, libre).
var snap_button: Button
## Menu Disposition (MapViewLayoutMenu).
var layout_button: Button
var file_menu: MenuButton
var edit_menu: MenuButton
var _recent_menu: PopupMenu
var _dialog: AcceptDialog
var _dialog_scroll: ScrollContainer
var _dialog_label: Label
var _file_dialog: FileDialog
var _status_error := false
## Barre du haut (passe à la ligne si elle ne tient pas en largeur).
var top_bar: HFlowContainer
## Écran d'options ouvert par-dessus l'éditeur (bouton ⚙, Fichier > Options).
var options: EditorOptions
## Taille de l'interface appliquée (EditorUi ; -1 : pas encore).
var ui_scale := -1.0
## Contrôles ajoutés depuis, mis à l'échelle en fin d'image.
var _ui_pending: Array = []
var _ui_queued := false
## Position du plan à l'écran avant un changement de taille (_keep_plan_in_place).
var _plan_anchor := Vector2.ZERO
var _plan_pending := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--check="):
			_cli_check(a.substr(8))
			return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Aucune musique dans l'éditeur : celle du menu principal (ou de la partie
	# lancée par TESTER) est coupée net, ainsi que les sons du menu encore en
	# cours ; le menu la relance à son retour.
	Audio.cut_music()
	Audio.stop_sounds("menu_")
	if GameState.state != GameState.State.MAIN_MENU:
		GameState.reset_to_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = make_theme(EditorUi.factor())
	_build_ui()
	apply_ui_scale()
	get_tree().node_added.connect(_on_node_added)
	resized.connect(_fit_side_panels)
	Settings.editor_ui_scale_changed.connect(func(_v): apply_ui_scale())
	# Fermeture de la fenêtre : demandée à l'éditeur d'abord (modifications non
	# enregistrées : confirmation) ; rétabli en quittant l'éditeur (_exit_tree).
	get_tree().set_auto_accept_quit(false)
	doc = EditorMap.blank()
	_setup_collab()
	_start.call_deferred()


## Vérification en ligne de commande (sans fenêtre), pour une carte écrite à
## la main ou par un outil :
##   godot --headless --path . res://scenes/editor/map_editor.tscn -- --check=<dossier ou archive .zip>
## Affiche le rapport du validateur ; code de sortie 0 si la carte est jouable.
func _cli_check(path: String) -> void:
	var p := path
	if not (p.is_absolute_path() or p.begins_with("res://") or p.begins_with("user://")):
		p = ProjectSettings.globalize_path("res://").path_join(p)
	var m: EditorMap = EditorMap.import_zip(p) if p.get_extension().to_lower() == "zip" else EditorMap.load_dir(p)
	for e in m.load_errors:
		print("[carte] ", Lang.t(e[0], e[1]))
	var v := MapRaster.build(m).v
	v.analyze()
	print(v.report_text())
	get_tree().quit(0 if v.ok() else 1)


func _start() -> void:
	if not _playtest_back.is_empty():
		_resume_playtest(_playtest_back)
		_playtest_back = {}
		return
	# Copie de récupération restée d'un plantage ou d'une fermeture forcée.
	if MapUnsaved.pending_dir() != "":
		_open_last()
		offer_recovery()
		return
	_open_last()


## Démarrage : la dernière carte ouverte (cartes récentes), sinon une nouvelle.
func _open_last() -> void:
	var recent := recent_maps()
	if not recent.is_empty() and EditorMap.is_map_dir(recent[0]):
		open_dir(recent[0])
	else:
		new_map(true)


func _process(delta: float) -> void:
	_recovery_t += delta
	if _recovery_t >= RECOVERY_EVERY:
		_recovery_t = 0.0
		write_recovery()
	if _validate_t > 0.0:
		_validate_t -= delta
		if _validate_t <= 0.0 and panels.is_check_tab():
			validate()


# ------------------------------------------------------------------ interface

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# Barre du haut : passe sur deux lignes plutôt que de déborder (grande
	# taille d'interface).
	var top := PanelContainer.new()
	root.add_child(top)
	var bar := HFlowContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	top.add_child(bar)
	top_bar = bar
	file_menu = MenuButton.new()
	file_menu.text = Lang.t("Fichier", "File")
	file_menu.flat = false
	bar.add_child(file_menu)
	var fm := file_menu.get_popup()
	fm.add_item(Lang.t("Nouvelle carte", "New map") + "   Ctrl+N", 0)
	fm.add_item(Lang.t("Ouvrir…", "Open…") + "   Ctrl+O", 1)
	fm.add_item(Lang.t("Enregistrer", "Save") + "   Ctrl+S", 2)
	fm.add_item(Lang.t("Enregistrer sous…", "Save as…") + "   Ctrl+Maj+S", 3)
	fm.add_separator()
	fm.add_item(Lang.t("Exporter l'archive .zip…", "Export .zip archive…"), 4)
	fm.add_item(Lang.t("Importer une archive .zip…", "Import .zip archive…"), 5)
	fm.add_separator()
	_recent_menu = PopupMenu.new()
	_recent_menu.name = "Recent"
	fm.add_child(_recent_menu)
	fm.add_submenu_item(Lang.t("Cartes récentes", "Recent maps"), "Recent", 6)
	_recent_menu.index_pressed.connect(func(i):
		var dir: String = recent_maps()[i]
		confirm_unsaved(Lang.t("ouvrir une autre carte", "open another map"), func(): open_dir(dir)))
	fm.add_separator()
	fm.add_item(Lang.t("Options (taille de l'interface…)", "Options (interface size…)"), 8)
	fm.add_item(Lang.t("Retour au menu principal", "Back to main menu"), 7)
	fm.id_pressed.connect(_on_file_menu)
	fm.about_to_popup.connect(_fill_recent)
	fm.about_to_popup.connect(update_file_menu)
	edit_menu = MenuButton.new()
	edit_menu.text = Lang.t("Édition", "Edit")
	edit_menu.flat = false
	bar.add_child(edit_menu)
	var em := edit_menu.get_popup()
	em.add_item(Lang.t("Annuler", "Undo") + "   Ctrl+Z", 0)
	em.add_item(Lang.t("Rétablir", "Redo") + "   Ctrl+Y", 1)
	em.add_separator()
	em.add_item(Lang.t("Copier", "Copy") + "   Ctrl+C", 2)
	em.add_item(Lang.t("Couper", "Cut") + "   Ctrl+X", 9)
	em.add_item(Lang.t("Coller", "Paste") + "   Ctrl+V", 3)
	em.add_item(Lang.t("Dupliquer", "Duplicate") + "   Ctrl+D", 10)
	em.add_item(Lang.t("Pivoter de 90°", "Rotate 90°") + "   R", 4)
	em.add_item(Lang.t("Aspect suivant", "Next look") + "   V", 8)
	em.add_item(Lang.t("Supprimer", "Delete") + "   Suppr", 5)
	em.add_separator()
	em.add_item(Lang.t("Tout sélectionner (étage)", "Select all (floor)") + "   Ctrl+A", 11)
	em.add_item(Lang.t("Créer une prefab…", "Create a prefab…") + "   Ctrl+G", 12)
	em.add_separator()
	em.add_item(Lang.t("Inventaire", "Inventory") + "   E / Tab", 6)
	em.add_item(Lang.t("Recadrer la vue", "Frame the view") + "   Origine", 7)
	em.id_pressed.connect(_on_edit_menu)
	bar.add_child(VSeparator.new())
	var prev := Button.new()
	prev.text = "◄"
	prev.tooltip_text = Lang.t("Niveau du dessous (Page préc.)", "Level below (Page Up)")
	prev.pressed.connect(func(): set_floor(floor_k - 1))
	bar.add_child(prev)
	floor_label = Label.new()
	floor_label.custom_minimum_size = Vector2(120, 0)
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(floor_label)
	var next := Button.new()
	next.text = "►"
	next.tooltip_text = Lang.t("Niveau du dessus (Page suiv.)", "Level above (Page Down)")
	next.pressed.connect(func(): set_floor(floor_k + 1))
	bar.add_child(next)
	bar.add_child(VSeparator.new())
	var test := Button.new()
	test.text = Lang.t("▶  TESTER", "▶  PLAY TEST")
	test.tooltip_text = Lang.t("Lance une partie solo sur la carte telle qu'elle est (sans l'enregistrer)", "Starts a solo game on the map as it is (without saving it)")
	test.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	test.pressed.connect(test_map)
	bar.add_child(test)
	check_button = Button.new()
	check_button.flat = true
	check_button.tooltip_text = Lang.t("Onglet Vérification", "Check tab")
	check_button.pressed.connect(func(): panels.show_tab("check"))
	bar.add_child(check_button)
	snap_button = Button.new()
	snap_button.tooltip_text = Lang.t("Aimantation : G pour changer (grille 1 m, grille fine, libre) ; Maj+G : pas de la grille fine ; Maj maintenu : inverse",
		"Snapping: G to change (1 m grid, fine grid, free); Shift+G: fine grid step; hold Shift: invert")
	snap_button.pressed.connect(func(): canvas.cycle_snap())
	bar.add_child(snap_button)
	# --- Aperçu 3D (MapPreviewPanel) : bouton et touche P.
	var preview_button := Button.new()
	preview_button.text = Lang.t("APERÇU 3D", "3D PREVIEW")
	preview_button.toggle_mode = true
	preview_button.focus_mode = Control.FOCUS_NONE
	preview_button.tooltip_text = Lang.t("Afficher / masquer l'aperçu 3D en direct (P)", "Show / hide the live 3D preview (P)")
	preview_button.toggled.connect(func(on): preview.set_shown(on))
	bar.add_child(preview_button)
	# --- fin aperçu 3D
	# Disposition des vues (docs/EDITOR_VIEWS.md § 5) : menu à 6 vignettes.
	layout_button = Button.new()
	layout_button.name = "LayoutButton"
	layout_button.text = Lang.t("Disposition ▾", "Layout ▾")
	layout_button.icon = _grid_icon()
	layout_button.focus_mode = Control.FOCUS_NONE
	layout_button.toggle_mode = true
	layout_button.tooltip_text = Lang.t("Disposition des vues : 1 à 4 fenêtres (Ctrl+Alt+Q : 4 vues ; Ctrl+Espace : agrandir la vue active)",
		"View layout: 1 to 4 windows (Ctrl+Alt+Q: 4 views; Ctrl+Space: maximize the active view)")
	layout_button.pressed.connect(func():
		views.open_menu(layout_button.get_screen_position() + Vector2(0, layout_button.size.y + 2))
		layout_button.set_pressed_no_signal(true))
	bar.add_child(layout_button)
	var opt := Button.new()
	opt.name = "OptionsButton"
	opt.text = "⚙"
	opt.focus_mode = Control.FOCUS_NONE
	opt.tooltip_text = Lang.t("Options du jeu (taille de l'interface de l'éditeur : Ctrl + / Ctrl - / Ctrl 0)",
		"Game options (map editor UI size: Ctrl + / Ctrl - / Ctrl 0)")
	opt.pressed.connect(open_options)
	bar.add_child(opt)
	# Nom et dossier de la carte, à droite ; coupé s'il est trop long.
	title_label = Label.new()
	title_label.add_theme_color_override("font_color", UiStyle.BONE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size = Vector2(70, 0)
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(title_label)
	var help := Button.new()
	help.text = " ? "
	help.tooltip_text = Lang.t("Raccourcis", "Shortcuts")
	help.pressed.connect(_show_help)
	bar.add_child(help)
	# Vue + panneaux.
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	root.add_child(mid)
	object_list = MapObjectList.new()
	object_list.ed = self
	mid.add_child(object_list)
	views = MapViewLayout.new()
	views.name = "Views"
	views.ed = self
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(views)
	canvas = MapCanvas.new()
	canvas.name = "Canvas"
	canvas.ed = self
	panels = MapPanels.new()
	panels.ed = self
	# Largeur à l'échelle, bornée pour laisser la place au plan (side_width).
	panels.set_meta(EditorUi.KEEP_MIN, true)
	panels.custom_minimum_size = Vector2(side_width(PANEL_W), 0)
	mid.add_child(panels)
	# Barre d'état.
	var sb := PanelContainer.new()
	root.add_child(sb)
	var sbh := HBoxContainer.new()
	sb.add_child(sbh)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	sbh.add_child(status)
	cursor_label = Label.new()
	cursor_label.add_theme_color_override("font_color", UiStyle.DIM)
	sbh.add_child(cursor_label)
	# Barre rapide (au bas de la zone des vues) et inventaire.
	hotbar_ui = MapHotbar.new()
	hotbar_ui.ed = self
	views.add_child(hotbar_ui)
	inventory = MapInventory.new()
	inventory.ed = self
	inventory.visible = false
	views.add_child(inventory)
	prefab_tools = MapPrefabTools.new()
	prefab_tools.ed = self
	prefab_tools.name = "PrefabTools"
	add_child(prefab_tools)
	texture_tools = MapTextureTools.new()
	texture_tools.ed = self
	texture_tools.name = "TextureTools"
	add_child(texture_tools)
	_dialog = AcceptDialog.new()
	# Texte du message dans une zone qui défile (aide « ? » à grande taille) ;
	# sa taille est calculée par _info.
	_dialog.get_label().visible = false
	_dialog_scroll = ScrollContainer.new()
	_dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog_scroll.set_meta(EditorUi.SKIP, true)
	_dialog_label = Label.new()
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_scroll.add_child(_dialog_label)
	_dialog.add_child(_dialog_scroll)
	add_child(_dialog)
	# --- Aperçu 3D (MapPreviewPanel), flottant au-dessus de la vue.
	preview = MapPreviewPanel.new()
	preview.ed = self
	add_child(preview)
	preview.shown_changed.connect(func(on): preview_button.set_pressed_no_signal(on))
	# --- fin aperçu 3D
	# Disposition mémorisée (_editeur.cfg, clé « vues ») ; premier lancement :
	# deux vues empilées (Dessus au-dessus d'Avant). Après l'aperçu (fenêtre 3D).
	views.apply_state(pref(MapViewLayout.PREF_KEY, {}))


## Icône du bouton Disposition : un quadrillage (maquette).
static func _grid_icon() -> Texture2D:
	var img := Image.create(14, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color("E0DBCC")
	for x in 14:
		img.set_pixel(x, 0, c)
		img.set_pixel(x, 11, c)
		img.set_pixel(x, 6, c)
	for y in 12:
		img.set_pixel(0, y, c)
		img.set_pixel(13, y, c)
		img.set_pixel(7, y, c)
	return ImageTexture.create_from_image(img)


## Thème de l'éditeur à la taille d'interface `f` (EditorUi) : styles écrits
## à 100 %, puis marges, bordures et arrondis mis à l'échelle, par-dessus le
## thème par défaut de Godot lui aussi à l'échelle (EditorUi.base_theme).
func make_theme(f := 1.0) -> Theme:
	var t := EditorUi.base_theme(f)
	t.default_font = UiStyle.font("body")
	t.default_font_size = EditorUi.fs(EditorUi.BODY_FONT, f)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.13, 0.135, 0.145)
	panel.set_content_margin_all(6)
	panel.border_color = Color(0.22, 0.22, 0.24)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var popup := panel.duplicate()
	popup.bg_color = Color(0.1, 0.1, 0.11)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "AcceptDialog", popup)
	t.set_stylebox("panel", "ConfirmationDialog", popup)
	for kind in ["Button", "MenuButton", "OptionButton", "CheckBox"]:
		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.2, 0.2, 0.22) if kind != "CheckBox" else Color(0, 0, 0, 0)
		n.set_corner_radius_all(3)
		n.set_content_margin_all(5)
		n.content_margin_left = 9
		n.content_margin_right = 9
		var h := n.duplicate()
		h.bg_color = Color(0.3, 0.26, 0.2)
		var p := n.duplicate()
		p.bg_color = Color(0.45, 0.14, 0.1)
		var d := n.duplicate()
		d.bg_color = Color(0.15, 0.15, 0.16)
		t.set_stylebox("normal", kind, n)
		t.set_stylebox("hover", kind, h)
		t.set_stylebox("pressed", kind, p)
		t.set_stylebox("disabled", kind, d)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_color("font_color", kind, Color(0.88, 0.86, 0.8))
		t.set_color("font_hover_color", kind, Color(1, 0.95, 0.85))
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.07, 0.07, 0.08)
	le.set_content_margin_all(5)
	le.border_color = Color(0.3, 0.3, 0.33)
	le.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = Color(0.85, 0.6, 0.25)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("panel", "ItemList", le)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", Color(0.86, 0.84, 0.78))
	t.set_color("font_color", "ItemList", Color(0.86, 0.84, 0.78))
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(0.16, 0.16, 0.17)
	tab.set_content_margin_all(6)
	var tabs := tab.duplicate()
	tabs.bg_color = Color(0.3, 0.12, 0.08)
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", tab)
	t.set_stylebox("tab_selected", "TabContainer", tabs)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_font_size("font_size", "TabContainer", EditorUi.fs(13, f))
	t.set_font_size("font_size", "TooltipLabel", EditorUi.fs(13, f))
	for type in ["PanelContainer", "Panel", "PopupMenu", "PopupPanel", "AcceptDialog", "ConfirmationDialog",
			"Button", "MenuButton", "OptionButton", "CheckBox", "LineEdit", "ItemList", "TabContainer"]:
		for n in t.get_stylebox_list(type):
			EditorUi.scale_stylebox(t.get_stylebox(n, type), f)
	return t


# ------------------------------------------------------------------ taille de l'interface

## Applique la taille d'interface du réglage (Settings.editor_ui_scale) à tout
## l'éditeur, en direct : thème, contrôles (EditorUi.scale_tree), dessins de
## la vue, barre rapide, liste des objets, inventaire, aperçu 3D. Le plan garde
## son zoom et ne bouge pas à l'écran : il gagne la place libérée.
func apply_ui_scale() -> void:
	var f := EditorUi.factor()
	var first := ui_scale < 0.0
	if not first and is_equal_approx(f, ui_scale):
		return
	var g0 := canvas.global_position
	ui_scale = f
	if not first:
		theme = make_theme(f)
		if preview != null and preview.window != null:
			preview.window.theme = theme
	EditorUi.scale_tree(self, f)
	_fit_side_panels()
	if hotbar_ui != null:
		hotbar_ui.queue_redraw_slots()
		hotbar_ui.ui_scale_changed()
	if views != null:
		views.ui_scale_changed()
	if object_list != null:
		object_list.ui_scale_changed()
	if inventory != null:
		inventory.ui_scale_changed()
	if preview != null:
		preview.ui_scale_changed()
	canvas.queue_redraw()
	if first:
		return
	set_status(Lang.t("Taille de l'interface : %d %% (Ctrl + / Ctrl - / Ctrl 0 ; Options, onglet JEU)",
		"Interface size: %d%% (Ctrl + / Ctrl - / Ctrl 0; Options, GAME tab)") % roundi(f * 100.0))
	# Après la mise en page (image suivante) : le plan reste à la même place à
	# l'écran, même après plusieurs changements dans la même image.
	if not _plan_pending:
		_plan_pending = true
		_plan_anchor = g0
		get_tree().process_frame.connect(_keep_plan_in_place, CONNECT_ONE_SHOT)


func _keep_plan_in_place() -> void:
	_plan_pending = false
	canvas.origin += _plan_anchor - canvas.global_position
	canvas.queue_redraw()


## Part de la largeur de l'éditeur que peut prendre chaque panneau latéral
## (liste des objets, panneaux de droite) : le plan garde au moins 40 %.
const SIDE_MAX := 0.3


## Largeur d'un panneau latéral de `base` pixels à 100 %, à la taille de
## l'interface, bornée par SIDE_MAX (grande taille, petite fenêtre).
func side_width(base: float) -> float:
	var w := EditorUi.px(base)
	return minf(w, roundf(size.x * SIDE_MAX)) if size.x > 0.0 else w


func _fit_side_panels() -> void:
	if panels != null:
		panels.custom_minimum_size = Vector2(side_width(PANEL_W), 0)
	if object_list != null:
		object_list.fit_width(side_width(MapObjectList.WIDTH))


## Ctrl + / Ctrl - (pas de 5 %), Ctrl 0 (taille par défaut) : même réglage
## que dans les options, enregistré tout de suite.
func step_ui_scale(dir: int) -> void:
	var v := Settings.EDITOR_UI_SCALE_DEFAULT if dir == 0 else Settings.editor_ui_scale + dir * Settings.EDITOR_UI_SCALE_STEP
	Settings.editor_ui_scale = v
	Settings.save_settings()
	if is_equal_approx(Settings.editor_ui_scale, ui_scale):
		set_status(Lang.t("Taille de l'interface : %d %% (de %d à %d %%)", "Interface size: %d%% (from %d to %d%%)") % [
			roundi(ui_scale * 100.0), roundi(Settings.EDITOR_UI_SCALE_RANGE.x * 100.0), roundi(Settings.EDITOR_UI_SCALE_RANGE.y * 100.0)])


## Contrôle ajouté à l'éditeur (panneaux reconstruits, fenêtres...) : mis à
## l'échelle en fin d'image, une fois ses tailles écrites par le code.
func _on_node_added(n: Node) -> void:
	if ui_scale < 0.0 or not n is Control:
		return
	_ui_pending.append(n)
	if not _ui_queued:
		_ui_queued = true
		_flush_ui_pending.call_deferred()


func _flush_ui_pending() -> void:
	_ui_queued = false
	var list := _ui_pending
	_ui_pending = []
	for n in list:
		if is_instance_valid(n) and (n as Node).is_inside_tree() and is_ancestor_of(n) and not EditorUi.skipped(n, self):
			EditorUi.scale_control(n, ui_scale)


# ------------------------------------------------------------------ options

## Écran d'options du jeu par-dessus l'éditeur (onglet JEU, sur la taille de
## l'interface) ; RETOUR ou Échap le ferme.
func open_options() -> void:
	if options_open():
		return
	canvas.cancel()
	views.set_space(false)
	options = EditorOptions.open_in(self)
	options.closed.connect(func(): options = null)


func options_open() -> bool:
	return options != null and is_instance_valid(options)


func set_status(text: String, error := false) -> void:
	status.text = text
	_status_error = error
	status.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if error else Color(0.8, 0.8, 0.75))


## Curseur sur une élévation (`m` : coordonnées de l'écran, m) : les deux
## axes qu'elle montre, l'altitude au-dessus du sol de l'étage courant.
func show_cursor_view(v: MapView, m: Vector2) -> void:
	if v == canvas or not MapView.is_elevation(v.plane):
		show_cursor(m if v == canvas else Vector2(-m.x, m.y))
		return
	var fr := not Lang.is_en()
	var p := MapView.point_of(v.plane, m, 0.0)
	var axis := String(MapView.h_axis(v.plane)[0])
	var h := p.x if axis == "X" else p.y
	# Présence : l'axe montré change, la profondeur garde sa dernière valeur.
	if axis == "X":
		_cursor_m.x = p.x
	else:
		_cursor_m.y = p.y
	_cursor_view = v.plane
	_cursor_z = p.z
	send_presence()
	cursor_label.text = "%s %s m · z %s m · %s" % [axis.to_lower(), MapRules._m(snappedf(h, 0.01), fr), MapRules._m(snappedf(p.z - view_alt(), 0.01), fr), EditorMap.level_name(view_alt()).to_lower()]


## K : coupe autour de la sélection dans l'élévation active (dans toutes les
## élévations si la vue active n'en est pas une) ; de nouveau K : enlevée.
func toggle_cut() -> void:
	var av := views.active_view()
	var targets: Array = [av] if av is MapElevation else views.elevations()
	if targets.is_empty():
		set_status(Lang.t("Coupe : aucune élévation affichée", "Cut: no elevation shown"))
		return
	var on := targets.any(func(e): return (e as MapElevation).coupe_mode == "selection")
	for e in targets:
		if on:
			(e as MapElevation).set_cut([], "aucune")
		else:
			(e as MapElevation).cut_around_selection()
	if on:
		set_status(Lang.t("Coupe enlevée", "Cut removed"))


## Boîtes des élévations (MapElevationItems), une fois par version de la carte.
func elevation_items() -> Array:
	if _elev_ver != doc_version:
		_elev_ver = doc_version
		_elev_items = MapElevationItems.build(doc, raster().v)
	return _elev_items


func show_cursor(m: Vector2) -> void:
	_cursor_view = "dessus"
	_cursor_z = NAN
	var fr := not Lang.is_en()
	var s := canvas.snap(m)
	cursor_label.text = "x %s m · y %s m · %s" % [MapRules._m(snappedf(s.x, 0.01), fr), MapRules._m(snappedf(s.y, 0.01), fr), EditorMap.level_name(view_alt()).to_lower()]
	_cursor_m = m
	send_presence()


var _cursor_m := Vector2.ZERO
## Plan de la vue où est le curseur, sa hauteur (m) dans une élévation.
var _cursor_view := "dessus"
var _cursor_z := NAN


## Présence de cet éditeur pour les autres (curseur, étage, sélection, outil,
## aperçu en direct) ; MapCollab l'envoie au plus 10 fois par seconde.
func send_presence() -> void:
	if collab == null or not collab.is_session():
		return
	var p := {"cursor": [snappedf(_cursor_m.x, 0.01), snappedf(_cursor_m.y, 0.01)], "alt": view_alt(),
		"selection": sel_ids(), "tool": tool()}
	# Curseur dans une élévation : son plan et sa hauteur (§ 6.4).
	if _cursor_view != "" and _cursor_view != "dessus":
		p["vue"] = _cursor_view
		if not is_nan(_cursor_z):
			p["z"] = snappedf(_cursor_z, 0.01)
	if not live.is_empty():
		p["live"] = live
	collab.set_presence(p)


## Aperçu en direct de l'élément `eid` qu'on glisse (MapCanvas), envoyé au
## plus toutes les LIVE_EVERY_MS ms ; `eid` vide : aperçu retiré (relâché).
## Rend true si une présence a été préparée. `now_ms` : horloge (tests).
func send_live(eid: String, now_ms := -1) -> bool:
	if collab == null or not collab.is_session():
		live = {}
		return false
	if eid == "":
		if live.is_empty():
			return false
		live = {}
		_live_ms = -1000000
		send_presence()
		return true
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now - _live_ms < LIVE_EVERY_MS:
		return false
	var e := doc.find(eid)
	if e.is_empty():
		return false
	_live_ms = now
	live = {"coll": CollabView.coll_of(doc, eid), "el": e.duplicate(true)}
	send_presence()
	return true


## Mode d'aimantation changé (MapCanvas) : bouton de la barre du haut.
func snap_changed() -> void:
	if snap_button != null and canvas != null:
		snap_button.text = Lang.t("Aimantation : %s", "Snapping: %s") % MapSnap.label(canvas.snap_mode, canvas.fine_step)
	if views != null:
		views.dock_redraw()


func _update_title() -> void:
	var where := Lang.t("exemple (copie à l'enregistrement)", "example (copied when saved)") if example else (map_dir if map_dir != "" else Lang.t("non enregistrée", "not saved"))
	title_label.text = "%s%s  —  %s" % [doc.display_name(), " *" if dirty else "", where]
	title_label.tooltip_text = title_label.text
	# Plus rien à enregistrer (annulé jusqu'à l'état enregistré, autre carte
	# ouverte) : la copie de récupération écrite d'ici est périmée.
	if not dirty and _recovery_sig != "" and not is_guest():
		_drop_recovery()
	floor_label.text = "%s (%d/%d)" % [EditorMap.level_name(view_alt()), floor_k + 1, doc.level_count()]
	floor_label.tooltip_text = Lang.t("Niveau affiché : altitude de son sol. Page préc. / Page suiv. : niveau voisin.",
		"Level shown: altitude of its floor. Page Up / Page Down: next level.")
	snap_changed()
	if validation_stale or validator == null:
		check_button.text = Lang.t("À vérifier", "Not checked")
		check_button.add_theme_color_override("font_color", UiStyle.DIM)
	else:
		var ne := validator.errors().size()
		var nw := validator.warnings().size()
		check_button.text = (Lang.t("✔ jouable (%d avert.)", "✔ playable (%d warn.)") % nw) if ne == 0 else (Lang.t("✖ %d erreur(s)", "✖ %d error(s)") % ne)
		check_button.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if ne == 0 else Color(1, 0.4, 0.35))


func _show_help() -> void:
	_info(Lang.t("Raccourcis", "Shortcuts"), Lang.t(
		"Clic gauche : poser / choisir · clic droit : menu (Créer une prefab…, Dupliquer, Copier, Couper, Coller ici, Pivoter, Supprimer, Tout sélectionner, Désélectionner) ; pendant un tracé ou un glissement, le clic droit l'annule\nSélection multiple : Maj + clic ajoute ou retire un élément · glisser depuis le vide (ou Maj + glisser n'importe où) : rectangle ; de gauche à droite, il prend les éléments ENTIÈREMENT dedans (cadre bleu), de droite à gauche, ceux qu'il TOUCHE (cadre vert en tirets) ; avec Maj, il ajoute à la sélection · Ctrl+A : tout l'étage · Échap ou simple clic sur l'élément déjà choisi : désélectionner\nGroupe (plusieurs éléments choisis) : glisser l'un d'eux déplace tout (élévations : aussi d'étage) · flèches : d'un pas de grille · R ou poignée ronde : pivoter autour du centre · Ctrl+D : dupliquer à côté · Ctrl+C / Ctrl+X / Ctrl+V : copier, couper, coller sous la souris · Suppr · une seule annulation par action ; un élément refusé (entouré de rouge, nommé) annule toute l'action\nPrefab : sélectionnez du décor posé au sol, puis clic droit > Créer une prefab… (Ctrl+G) ; elle rejoint l'inventaire (E), catégorie « Prefabs de la carte » : prenez-la et cliquez sur le plan pour la poser, R pour la pivoter\nGlisser (ou clic puis clic) : pièces, formes, murs, piliers, escaliers, pièges\nPièce tracée sur une autre : la partie retirée est hachurée en orange (en rouge : pièce supprimée) ; au relâcher, confirmation (Entrée : Découper, Échap : Annuler) ; l'ancienne pièce perd la partie recouverte (coupée en morceaux si besoin, reliés par un passage libre), son contenu passe à la nouvelle ; une seule annulation\nEscaliers : « qui monte » (flèche vers le haut) se trace du bas (cet étage) vers le haut, « qui descend » (flèche vers le bas) du haut (cet étage) vers le bas ; départ et arrivée montrés pendant le tracé, ce qui gêne en rouge ; un escalier se choisit depuis ses deux étages\nG : aimantation grille 1 m, grille fine, libre (sans grille) · Maj+G : pas de la grille fine (0,5 / 0,25 / 0,1 m) · Maj maintenu : inverse le mode\nSans grille : aimants aux sommets et aux côtés des pièces, côtés à 15° près\nMurs et côtés de polygone : à 0, 45 ou 90° sur la grille ; Alt : angle libre (longueur et angle affichés)\nPendant un tracé : taper la longueur, Tab, l'angle (degrés depuis l'est), Entrée (rectangle : largeur, hauteur ; cercle : rayon, points)\nCercle, ellipse : molette ou + / - pendant le tracé : nombre de points (3 à 64) · mur courbe : segments\nPièce rectangle en main : R la tourne de 45°\nPoignée ronde de l'élément choisi : rotation par pas de 15° (Alt : au degré près) ; angle dans les propriétés\nCtrl + molette : zoom · clic milieu ou Espace + glisser : déplacer la vue\nCtrl + « + » / Ctrl + « - » / Ctrl + 0 : taille de l'interface de l'éditeur (aussi dans les options, bouton ⚙)\nMolette ou 1 à 9 : case de la barre rapide · ² ou Échap : la souris (case à gauche de la barre) · E ou Tab : inventaire\nR : pivoter de 90° (aussi le décor tenu, avant de le poser) · Suppr : supprimer · Ctrl+C / Ctrl+X / Ctrl+V : copier / couper / coller · Ctrl+D : dupliquer\nL : liste des objets sur la carte\nCtrl+Z / Ctrl+Y : annuler / rétablir · Ctrl+S : enregistrer (seule façon d'écrire la carte ; « * » au titre : modifications non enregistrées, confirmation avant de les perdre ; TESTER joue la carte sans l'enregistrer)\nPage préc. / suiv. : étage · Origine : recadrer · Entrée : fermer un polygone\nP : aperçu 3D · orbite : clic droit glisser, molette, clic milieu · vol libre et vue joueur : touches de déplacement du jeu, Maj, clic droit pour regarder\nClic dans l'aperçu : choisir l'élément · Ctrl + double-clic sur la carte : y placer la caméra de l'aperçu\nVues : bouton Disposition (1 à 4 fenêtres) · Ctrl+Alt+Q : 4 vues · Ctrl+Espace ou ⛶ : agrandir la vue active · séparateurs : glisser, double-clic : partage égal\nViewCube (coin haut droit de chaque vue) : face : changer de plan · coin : la 3D vue de ce coin · maison : vue d'origine · ◄ ► : façade suivante · pavé 7 / 1 / 3 : Dessus / Avant / Droite (Ctrl : la vue opposée), pavé 5 : 3D (souris sur la vue)\nÉlévations (Avant, Droite…) : glisser : déplacer sur les deux axes de la vue (hauteur de pose, ou étage) · flèches d'axe : un seul axe · X / Y / Z pendant le glissement : verrouiller · chiffres ou Tab : taper l'écart, Entrée · losange : plafond, hauteur · étiquette « É1 » : sol de l'étage · K : coupe autour de la sélection · la pose reste en vue Dessus
Décor choisi (format 14) : poignées d'échelle (coins jaunes : uniforme, Alt : depuis le centre · faces : un axe · losange : la hauteur ; la base reste posée), pas de 0,25 / 0,05 / 0,01 selon l'aimantation ; anneaux de rotation (Dessus : Z, Avant : Y, Droite : X, 3D : les trois ; crans de 15°, Maj : libre) ; pendant le geste, taper « 1,5 », « 3m » ou un angle puis Entrée, Échap : annuler · panneau Propriétés : Échelle (cadenas : les trois axes ensemble) et Rotation (Rester posé, Remettre droit) · objets de jeu et prefab qui en contient un : taille fixe (cadenas gris)",
		"Left click: place / pick · right click: menu (Create a prefab…, Duplicate, Copy, Cut, Paste here, Rotate, Delete, Select all, Deselect); while drawing or dragging, right click cancels it\nMultiple selection: Shift + click adds or removes an element · drag from an empty spot (or Shift + drag anywhere): rectangle; left to right it takes the elements ENTIRELY inside (blue frame), right to left those it TOUCHES (dashed green frame); with Shift it adds to the selection · Ctrl+A: whole floor · Esc or a single click on the already selected element: deselect\nGroup (several elements picked): dragging one of them moves them all (elevations: also between floors) · arrow keys: one grid step · R or round handle: rotate around the centre · Ctrl+D: duplicate next to it · Ctrl+C / Ctrl+X / Ctrl+V: copy, cut, paste under the mouse · Del · one undo per action; a refused element (outlined in red, named) cancels the whole action\nPrefab: select props placed on the floor, then right click > Create a prefab… (Ctrl+G); it joins the inventory (E), \"Map prefabs\" category: take it and click on the plan to place it, R to rotate it\nDrag (or click then click): rooms, shapes, walls, pillars, stairs, traps\nRoom drawn over another: the removed part is hatched in orange (in red: room deleted); on release, confirmation (Enter: Cut, Esc: Cancel); the old room loses the covered part (split into parts if needed, linked by an open passage), its content goes to the new one; a single undo\nStairs: going up (arrow up) are drawn from the bottom (this floor) to the top, going down (arrow down) from the top (this floor) to the bottom; start and arrival shown while drawing, what is in the way in red; stairs can be picked from both their floors\nG: snapping 1 m grid, fine grid, free (no grid) · Shift+G: fine grid step (0.5 / 0.25 / 0.1 m) · hold Shift: invert the mode\nNo grid: magnets on room corners and sides, sides at 15° steps\nWalls and polygon sides: at 0, 45 or 90° on the grid; Alt: free angle (length and angle shown)\nWhile drawing: type the length, Tab, the angle (degrees from east), Enter (rectangle: width, height; circle: radius, points)\nCircle, ellipse: wheel or + / - while drawing: number of points (3 to 64) · curved wall: segments\nRectangle room held: R turns it 45°\nRound handle of the selected element: rotate in 15° steps (Alt: to the degree); angle in the properties\nCtrl + wheel: zoom · middle click or Space + drag: pan\nCtrl + \"+\" / Ctrl + \"-\" / Ctrl + 0: map editor UI size (also in the options, ⚙ button)\nWheel or 1 to 9: hotbar slot · ` (key left of 1) or Esc: the mouse (slot left of the hotbar) · E or Tab: inventory\nR: rotate 90° (also the held prop, before placing it) · Del: delete · Ctrl+C / Ctrl+X / Ctrl+V: copy / cut / paste · Ctrl+D: duplicate\nL: list of the items on the map\nCtrl+Z / Ctrl+Y: undo / redo · Ctrl+S: save (the only way the map is written; \"*\" in the title: unsaved changes, confirmation before losing them; PLAY TEST plays the map without saving it)\nPage Up / Down: floor · Home: frame · Enter: close a polygon\nP: 3D preview · orbit: right drag, wheel, middle drag · free flight and player view: game movement keys, Shift, right drag to look\nClick in the preview: pick the element · Ctrl + double-click on the map: move the preview camera there\nViews: Layout button (1 to 4 windows) · Ctrl+Alt+Q: 4 views · Ctrl+Space or ⛶: maximize the active view · splitters: drag, double-click: equal split\nViewCube (top right of each view): face: switch plane · corner: 3D from that corner · home: home view · ◄ ►: next side · numpad 7 / 1 / 3: Top / Front / Right (Ctrl: opposite view), numpad 5: 3D (mouse over the view)\nElevations (Front, Right…): drag: move on the two axes of the view (placement height, or floor) · axis arrows: a single axis · X / Y / Z while dragging: lock · digits or Tab: type the offset, Enter · diamond: ceiling, height · \"F1\" tag: floor level · K: cut around the selection · placing stays in the Top view
Selected prop (format 14): scale handles (yellow corners: uniform, Alt: from the centre · faces: one axis · diamond: the height; the base stays grounded), steps of 0.25 / 0.05 / 0.01 following snapping; rotation rings (Top: Z, Front: Y, Right: X, 3D: all three; 15° steps, Shift: free); during the gesture, type \"1.5\", \"3m\" or an angle then Enter, Esc: cancel · Properties panel: Scale (lock: the three axes together) and Rotation (Stay grounded, Set upright) · game objects and a prefab that contains one: fixed size (grey lock)"))


func _info(title_text: String, text: String) -> void:
	_dialog.title = title_text
	_dialog_label.text = text
	# Texte replié à une largeur qui tient dans la fenêtre, et qui défile s'il
	# est plus haut qu'elle (toutes les tailles d'interface).
	var vp := get_viewport_rect().size
	var w := minf(EditorUi.px(820.0), vp.x - 80.0)
	var font := _dialog_label.get_theme_font("font")
	var fsz := _dialog_label.get_theme_font_size("font_size")
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, fsz).y
	h += h / maxf(font.get_height(fsz), 1.0) * _dialog_label.get_theme_constant("line_spacing") + 8.0
	_dialog_scroll.custom_minimum_size = Vector2(w + EditorUi.px(14.0), minf(h, vp.y - 160.0))
	_dialog.popup_centered()


func _confirm(title_text: String, text: String, on_ok: Callable, on_cancel := Callable(), parent: Node = null) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = title_text
	d.dialog_text = text
	d.ok_button_text = Lang.t("Oui", "Yes")
	d.cancel_button_text = Lang.t("Non", "No")
	# Par-dessus une autre fenêtre : sa fille (une seule fenêtre exclusive par parent).
	var under: Node = parent if parent != null else self
	under.add_child(d)
	d.confirmed.connect(func():
		d.queue_free()
		on_ok.call())
	d.canceled.connect(func():
		d.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	d.popup_centered()
	return d


# ------------------------------------------------------------------ clavier

func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Une boîte de l'éditeur est-elle ouverte (Ouvrir, Créer une prefab…) ?
## Ses listes gardent alors les flèches.
func _dialog_open() -> bool:
	for c in get_children():
		if c is AcceptDialog and (c as AcceptDialog).visible:
			return true
	return false


## Les flèches vont-elles aux vues (déplacer la sélection) ? Oui si le focus
## clavier est sur une vue (MapView), ou s'il n'est nulle part et que la souris
## est sur une vue ; jamais avec une boîte ouverte. Une liste (Pièces, Zones,
## Étages), un champ, un menu gardent leurs flèches.
func arrows_to_views() -> bool:
	if _dialog_open() or (context_menu != null and context_menu.visible):
		return false
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		return f is MapView
	return views != null and views.hovered_pane() != null


## Un glissement ou un tracé est-il en cours (vue Dessus, élévations) ? Les
## actions qui changent la carte (flèches, R, Suppr, Ctrl+V / X / D, prefab)
## attendent alors : le glissement remettrait sa carte de départ au mouvement
## suivant. Vrai : refusé, message dans la barre d'état.
func edit_blocked() -> bool:
	if views == null or not views.busy():
		return false
	set_status(Lang.t("Terminez d'abord le glissement ou le tracé en cours (relâcher), ou annulez-le (Échap, clic droit)",
		"Finish the drag or drawing in progress first (release), or cancel it (Esc, right click)"), true)
	return true


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	# Options ouvertes par-dessus : les touches sont à elles.
	if options_open():
		return
	var k := event as InputEventKey
	# Ctrl+Espace : agrandir la vue active (une seconde fois : la disposition).
	# Touche tenue (répétition) : prise aussi, sans passer en main (Espace).
	if k.keycode == KEY_SPACE and k.ctrl_pressed and k.pressed and not _typing():
		if not k.echo:
			views.toggle_maximized(views.active_pane)
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_SPACE and not _typing():
		views.set_space(k.pressed)
		get_viewport().set_input_as_handled()
		return
	if not k.pressed:
		return
	if k.echo and not (k.keycode in [KEY_Z, KEY_Y, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]):
		return
	# Pavé numérique sur une vue (7, 1, 3, 5 ; Ctrl : la vue opposée) : le
	# plan de la vue ; ailleurs il garde la barre rapide (§ 4). Pendant un tracé
	# ou un glissement, les chiffres du pavé sont la valeur tapée.
	if k.keycode in [KEY_KP_1, KEY_KP_3, KEY_KP_5, KEY_KP_7] and not _typing() and not k.alt_pressed and not views.busy() and views.numpad(k, views.hovered_pane()):
		get_viewport().set_input_as_handled()
		return
	# Ctrl+Alt+Q : quatre vues (pas pendant une saisie : AltGr+Q = « @ » sur
	# certains claviers).
	if k.ctrl_pressed and k.alt_pressed and k.keycode == KEY_Q and not _typing():
		views.set_layout("4")
		get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed:
		match k.keycode:
			KEY_S:
				if k.shift_pressed:
					save_as_dialog()
				else:
					save()
			KEY_Z:
				if k.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_N:
				new_map()
			KEY_O:
				open_dialog()
			KEY_C:
				if _typing():
					return
				copy_selected()
			KEY_V:
				if _typing():
					return
				paste()
			# Sélection multiple (MapGroup) : couper, dupliquer, tout l'étage,
			# créer une prefab de la sélection.
			KEY_X:
				if _typing():
					return
				cut_selected()
			KEY_D:
				if _typing():
					return
				duplicate_selection()
			KEY_A:
				if _typing():
					return
				select_all()
			KEY_G:
				if _typing():
					return
				create_prefab_from_selection()
			# Taille de l'interface (Ctrl + molette reste le zoom du plan) ; pas
			# pendant une saisie (AltGr = Ctrl+Alt : AltGr+à = « @ » en AZERTY).
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				if _typing():
					return
				step_ui_scale(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				if _typing():
					return
				step_ui_scale(-1)
			KEY_0, KEY_KP_0:
				if _typing():
					return
				step_ui_scale(0)
			_:
				# Ctrl 0 sur un clavier AZERTY (touche « à / 0 »).
				if k.physical_keycode == KEY_0 and not _typing():
					step_ui_scale(0)
				else:
					return
		get_viewport().set_input_as_handled()
		return
	if _typing():
		if k.keycode == KEY_ESCAPE:
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()
		return
	# Glissement dans une élévation : verrou d'axe, valeur tapée, Échap.
	if views.handle_drag_key(k):
		get_viewport().set_input_as_handled()
		return
	# Aimantation (G), saisie au clavier du tracé, points d'une forme (+ / -).
	if canvas.handle_key(k):
		get_viewport().set_input_as_handled()
		return
	var handled := true
	var pk := k.physical_keycode
	# Flèches : la sélection avance d'un pas de la grille, seulement quand le
	# clavier est à une vue (focus sur une vue, ou aucun focus et la souris sur
	# une vue) ; une liste, un champ, une boîte gardent leurs flèches ; pas
	# avec la 3D survolée (ses touches de déplacement).
	if k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and not k.alt_pressed and not (preview != null and preview.nav_active()) and arrows_to_views():
		if not sel_ids().is_empty():
			nudge_selection({KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[k.keycode])
			get_viewport().set_input_as_handled()
		return
	if pk >= KEY_1 and pk <= KEY_9:
		select_slot(pk - KEY_1)
	elif pk == KEY_QUOTELEFT:
		# Touche à gauche du 1 (² en AZERTY, ` en QWERTY) : la souris.
		select_mouse()
	elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
		select_slot(k.keycode - KEY_KP_1)
	else:
		match k.keycode:
			KEY_E, KEY_TAB:
				toggle_inventory()
			KEY_ESCAPE:
				if inventory.visible:
					toggle_inventory()
				elif not canvas.drag.is_empty() or not canvas.poly_pts.is_empty():
					canvas.cancel()
				elif context_menu != null and context_menu.visible:
					context_menu.hide()
				elif not sel_ids().is_empty() or mouse_active():
					select("")
				else:
					# Échap suivant (rien en cours) : retour à la souris.
					select_mouse()
			KEY_R:
				rotate_selected()
			KEY_V:
				cycle_variant()
			KEY_L:
				object_list.toggle()
			KEY_DELETE:
				delete_selection()
			KEY_BACKSPACE:
				if not canvas.poly_pts.is_empty():
					canvas.undo_point()
				else:
					delete_selection()
			KEY_ENTER, KEY_KP_ENTER:
				canvas.finish_polygon()
			KEY_PAGEUP:
				set_floor(floor_k - 1)
			KEY_PAGEDOWN:
				set_floor(floor_k + 1)
			KEY_HOME:
				views.frame_all()
			KEY_K:
				toggle_cut()
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
				canvas.zoom_by(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT:
				canvas.zoom_by(0.8)
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ barre rapide

const MOUSE := -1


## La souris est-elle en main (case Souris, ou case vide de la barre) ?
func mouse_active() -> bool:
	return String(current_item().get("id", "")) == "select"


func current_item() -> Dictionary:
	var id := String(hotbar[hot_index]) if hot_index >= 0 and hot_index < hotbar.size() else ""
	var it := MapCatalog.item(id)
	return it if not it.is_empty() else MapCatalog.item("select")


func tool() -> String:
	return String(current_item().get("tool", "select"))


## i : case 0 à 8, ou MOUSE (-1) pour la souris.
func select_slot(i: int) -> void:
	hot_index = clampi(i, MOUSE, 8)
	if hot_index >= 0:
		last_slot = hot_index
	place_rot = 0
	place_variant = ""
	canvas.cancel()
	canvas.preview = {}
	canvas.refusal = ""
	var it := current_item()
	set_status("%s — %s" % [MapCatalog.name_of(it), Lang.t(String(it.get("hint_fr", "")), String(it.get("hint_en", "")))])
	hotbar_ui.queue_redraw_slots()
	canvas.queue_redraw()
	views.dock_redraw()


## Souris en main (case fixe à gauche de la barre).
func select_mouse() -> void:
	select_slot(MOUSE)


## Molette : la souris est la position avant la case 1 (10 positions en boucle).
func cycle_hotbar(d: int) -> void:
	select_slot(posmod(hot_index + 1 + d, 10) - 1)


func set_hotbar(i: int, item_id: String) -> void:
	# La souris n'est pas un objet de la barre : elle a sa case fixe.
	if item_id == "select":
		select_mouse()
		return
	if i < 0 or i >= 9:
		return
	while hotbar.size() < 9:
		hotbar.append("")
	hotbar[i] = item_id
	select_slot(i)


## Objet pris dans l'inventaire : dans la case choisie ; souris en main, dans
## la première case vide (sinon la dernière case choisie), qui devient la case
## en main. La souris garde toujours sa case.
func pick_item(item_id: String) -> void:
	if item_id == "select":
		select_mouse()
		return
	var i := hot_index
	if i < 0:
		i = hotbar.find("")
		if i < 0 or i >= 9:
			i = last_slot
	set_hotbar(i, item_id)


## Barre rapide relue (préférences, ancienne sauvegarde) : MapHotbar.migrate.
func load_hotbar(items: Array) -> void:
	hotbar = MapHotbar.migrate(items)
	if hotbar_ui != null:
		hotbar_ui.queue_redraw_slots()


func toggle_inventory() -> void:
	inventory.visible = not inventory.visible
	if inventory.visible:
		inventory.open()
	canvas.cancel()


# ------------------------------------------------------------------ carte

func raster() -> MapRaster:
	if _raster_dirty or _raster == null:
		_raster = MapRaster.build(doc)
		_raster_dirty = false
	return _raster


func zone_color(zid: String) -> Color:
	var i := 0
	for z in doc.zones:
		if String(z.id) == zid:
			break
		i += 1
	var c := Color.from_hsv(fmod(0.08 + i * 0.137, 1.0), 0.5, 0.75)
	if zid == doc.depart:
		c = Color(0.95, 0.85, 0.45)
	return Color(c, 0.3)


## Annuler : la carte d'avant est mémorisée ici ; changed() calcule le diff
## (MapOps) et l'inscrit dans l'historique de la session (MapHistory, par
## auteur), qui l'envoie aux autres éditeurs. Plusieurs push_undo avant le
## même changed() : la plus ancienne carte compte.
func push_undo() -> void:
	push_undo_snapshot(doc.snapshot())


func push_undo_snapshot(s: Dictionary) -> void:
	if _before.is_empty():
		_before = s


## Changement en cours (push_undo puis modification) inscrit dans
## l'historique s'il a vraiment changé la carte.
func _commit_change() -> void:
	if _before.is_empty() or collab == null:
		return
	var before := _before
	_before = {}
	var ops := MapOps.diff(before, doc)
	if not ops.is_empty():
		collab.submit_local(ops, MapOps.describe(ops, before), before)


## Après une modification : grille, vérification, dessin, panneaux.
func changed(rebuild_panels := true) -> void:
	_commit_change()
	_refresh(rebuild_panels)


func _refresh(rebuild_panels := true) -> void:
	_sync_view()
	# doc_version : l'étoile « non enregistrée » est recalculée (dirty).
	doc_version += 1
	_hit_dirty = true
	_raster_dirty = true
	validation_stale = true
	_validate_t = 1.0
	if doc.find(selected).is_empty():
		selected = ""
	_prune_group()
	if hover_id != "" and doc.find(hover_id).is_empty():
		hover_id = ""
	_update_invalid()
	canvas.queue_redraw()
	if rebuild_panels:
		panels.refresh()
	object_list.mark_dirty()
	_update_title()


## Modification en direct (glissement) : dessin seulement.
func moved_live() -> void:
	doc_version += 1
	_hit_dirty = true
	_raster_dirty = true
	validation_stale = true
	canvas.queue_redraw()


func _update_invalid() -> void:
	invalid.clear()
	# Emprises calculées une fois pour toute la carte (rapide avec 2000 objets).
	MapRules.begin_batch(doc)
	for list in [doc.pieces, doc.ouvertures, doc.objets]:
		for e in list:
			var r := MapRules.check_existing(doc, e)
			if not r.ok:
				invalid[String(e.id)] = MapRules.why(r)
	MapRules.end_batch()


## Ctrl+Z : annule ma dernière action encore active ou celle de mon Claude
## (la plus récente des deux) ; un élément modifié entre-temps par un autre
## participant n'est pas touché (message).
func undo() -> void:
	canvas.cancel()
	views.cancel_drags()
	_commit_change()
	var r := collab.request_undo()
	if r.is_empty():
		set_status(Lang.t("Rien à annuler", "Nothing to undo"))
		return
	if r.has("queued"):
		set_status(Lang.t("Annulation dès la confirmation de l'hôte…", "Undo as soon as the host confirms…"))
		return
	var e := collab.history.entry(String(r.undo))
	var conflict := collab.conflict_text(r)
	var txt := Lang.t("Annulé : %s (%d étape(s) restante(s))", "Undone: %s (%d step(s) left)") % [String(e.get("label", "")), collab.history.undo_count(collab.my_id)]
	set_status(txt + ("  —  " + conflict if conflict != "" else ""), conflict != "")


func redo() -> void:
	canvas.cancel()
	views.cancel_drags()
	_commit_change()
	var r := collab.request_redo()
	if r.is_empty():
		set_status(Lang.t("Rien à rétablir", "Nothing to redo"))
		return
	if r.has("queued"):
		set_status(Lang.t("Rétablissement dès la confirmation de l'hôte…", "Redo as soon as the host confirms…"))
		return
	var conflict := collab.conflict_text(r)
	set_status(Lang.t("Rétabli : %s", "Redone: %s") % String(collab.history.entry(String(r.redo)).get("label", "")) + ("  —  " + conflict if conflict != "" else ""), conflict != "")


## « Annuler cette action » du panneau Historique : une de mes entrées ou
## de mon Claude (même règle de conflit que Ctrl+Z). Rend le résultat de
## MapCollab.request_undo_of ({} si impossible).
func undo_entry(cid: String) -> Dictionary:
	canvas.cancel()
	views.cancel_drags()
	_commit_change()
	var r := collab.request_undo_of(cid)
	if r.is_empty():
		set_status(Lang.t("Cette action ne peut plus être annulée", "This action can no longer be undone"), true)
		return r
	if r.has("queued"):
		set_status(Lang.t("Annulation dès la confirmation de l'hôte…", "Undo as soon as the host confirms…"))
		return r
	var conflict := collab.conflict_text(r)
	set_status(Lang.t("Annulé : %s", "Undone: %s") % String(collab.history.entry(cid).get("label", "")) + ("  —  " + conflict if conflict != "" else ""), conflict != "")
	return r


# ------------------------------------------------------------------ collaboration

func _setup_collab() -> void:
	# Retour d'un TESTER à plusieurs : la session d'édition, gardée pendant la
	# partie (CollabPlaytest), est reprise telle quelle (carte, historique).
	var pt := CollabPlaytest.take(self)
	if pt != null:
		collab = pt.collab
		doc = collab.doc
		var msg := pt.return_message()
		# Session perdue pendant la partie : son message l'emporte sur celui
		# de fin de partie.
		if msg == "" and pt.last_error:
			msg = pt.last_message
		_playtest_back = {"state": pt.editor_state, "message": msg, "error": msg != "" and pt.last_error}
	elif not _test_keep.is_empty() and is_instance_valid(_test_keep.get("collab")):
		# Retour d'un TESTER en solo : même session (carte et historique
		# d'annulation intacts, rien n'a été enregistré).
		collab = _test_keep.collab
		var st: Dictionary = _test_keep.state
		_test_keep = {}
		add_child(collab)
		doc = collab.doc
		_playtest_back = {"state": st, "message": "", "error": false}
	else:
		_test_keep = {}
		collab = MapCollab.new(doc)
		collab.name = "Collab"
		collab.my_name = CollabPanel.default_name()
		collab._reset_peers()
		add_child(collab)
	collab.playtest_message.connect(_on_playtest_message)
	collab.applied.connect(_on_collab_applied)
	collab.map_replaced.connect(_on_map_replaced)
	collab.message.connect(func(t, err): set_status(t, err))
	collab.presence_changed.connect(func(_p):
		canvas.queue_redraw()
		views.redraw_overlays())
	collab.peers_changed.connect(canvas.queue_redraw)
	collab.saved.connect(func(by):
		# Invité : la carte de la session vient d'être enregistrée chez l'hôte.
		if is_guest():
			dirty = false
			_update_title()
		set_status(Lang.t("Carte enregistrée par %s (hôte)", "Map saved by %s (host)") % by))
	collab.session_changed.connect(_on_session_changed)
	_was_guest = is_guest()
	_host_map_shown = _was_guest
	collab_ui = CollabPanel.new()
	collab_ui.name = "CollabUi"
	add_child(collab_ui)
	collab_ui.setup(self)
	collab_view = CollabView.new()
	collab_view.name = "CollabView"
	add_child(collab_view)
	collab_view.setup(self)
	panels.history.setup(self)
	# IA (MCP) : le serveur est celui du jeu (autoload McpServer, docs/MCP.md) ;
	# la liaison lui donne les commandes de cet éditeur tant qu'il est ouvert.
	agent_link = MapAgentLink.new()
	agent_link.name = "AgentLink"
	agent_link.collab = collab
	agent_link.editor = self
	add_child(agent_link)
	agent_link.animate_requested.connect(_on_agent_animate)


## Serveur MCP du jeu (autoload McpServer) ; null hors du jeu.
static func mcp_server() -> Node:
	return MapAgentLink.server()


## Option « Autoriser Claude (MCP) » (réglage du jeu Settings.mcp_enabled) :
## démarre ou arrête le serveur MCP du jeu.
func set_claude_allowed(on: bool) -> void:
	var srv := mcp_server()
	if srv == null:
		return
	srv.set_enabled(on)
	if not on:
		set_status(Lang.t("Serveur MCP désactivé : aucune IA ne peut se connecter", "MCP server disabled: no AI can connect"))
	elif srv.is_running():
		set_status(Lang.t("Serveur MCP activé : %s (Collaboration > Connecter une IA)", "MCP server enabled: %s (Collaboration > Connect an AI)") % srv.url())
	else:
		set_status(Lang.t("Serveur MCP : %s", "MCP server: %s") % String(srv.error), true)


## La session a changé la carte (autre participant, annulation, Claude) :
## les copies tenues ici (carte d'avant un changement en cours, glissement)
## reçoivent le même état, puis tout est redessiné.
func _on_collab_applied(ops: Array, author: String, label: String, local: bool) -> void:
	if not _before.is_empty():
		MapOps.apply(_before, ops)
	if canvas.drag.has("snap"):
		MapOps.apply(canvas.drag.snap, ops)
	# Glissements en élévation (élément, étiquette de niveau, plafond) : leur
	# carte de départ reçoit le changement (sinon il serait effacé).
	for snap in views.drag_snaps():
		MapOps.apply(snap, ops)
	# Format 14 : geste d'anneau de la vue 3D (sa carte de départ, ses caches).
	if preview != null and preview.gizmo != null:
		preview.gizmo.map_changed(ops)
	_sync_view()
	_refresh()
	if not local and label != "":
		set_status("%s : %s" % [collab.peer_name(author), label])
	elif local and MapHistory.is_agent(author):
		set_status(label)


## Carte entière reçue (arrivée dans une session, rattrapage).
func _on_map_replaced() -> void:
	_before = {}
	# Glissement en cours abandonné SANS remettre sa copie (l'ancienne carte).
	canvas.drag = {}
	canvas.cancel()
	views.drop_drags()
	_sync_view()
	if collab.role == MapCollab.Role.GUEST:
		map_dir = ""
		example = false
	if doc.find(selected).is_empty():
		selected = ""
	_prune_group()
	doc_version += 1
	# Invité : carte de l'hôte, rien à enregistrer ici (étoile d'après les
	# enregistrements de l'hôte, signal « saved »).
	if collab.role == MapCollab.Role.GUEST:
		dirty = false
		_host_map_shown = true
	_hit_dirty = true
	_raster_dirty = true
	validation_stale = true
	_update_invalid()
	panels.refresh()
	object_list.mark_dirty()
	_update_title()
	canvas.queue_redraw()


## Session ouverte, rejointe ou quittée. Un invité qui part garde une copie
## de la carte de l'hôte, sans dossier : elle n'est pas « à lui », rien n'est
## à enregistrer tant qu'il ne la modifie pas. Tentative de rejoindre
## échouée (carte de l'hôte jamais reçue) : sa propre carte reste telle quelle
## (dossier, étoile, récupération).
func _on_session_changed() -> void:
	var guest := is_guest()
	if _was_guest and not guest and _host_map_shown:
		map_dir = ""
		example = false
		dirty = false
		_update_title()
	if not guest:
		_host_map_shown = false
	_was_guest = guest


## Invité : la carte de l'hôte a remplacé la carte d'ici (map_replaced).
var _host_map_shown := false


## Lot de Claude (apply avec animate) : déjà sur la carte et dans
## l'historique en entier ; les éléments apparaissent un par un sur le plan
## (CollabView), bulle « Claude : <label> ».
func _on_agent_animate(ids: Array, label: String) -> void:
	if ids.is_empty():
		return
	collab_view.animate(ids, label)
	set_status(Lang.t("Claude : %s", "Claude: %s") % label)


## Commande highlight de Claude : contour pulsé et bulle avec le message,
## vue amenée sur les éléments s'ils sont hors champ (CollabView).
## Un geste de l'utilisateur est-il en cours dans une vue (glissement,
## anneau, poignée, tracé) ? Une sélection venue de Claude (editor_highlight
## « select ») attend alors : elle annulerait le geste (MapAgentLink).
func gesture_busy() -> bool:
	return views != null and views.busy()


func agent_highlight(ids: Array, message: String) -> void:
	collab_view.highlight(ids, message)
	set_status(Lang.t("Claude : %s", "Claude: %s") % message if message != "" else Lang.t("Claude montre %d élément(s)", "Claude shows %d element(s)") % ids.size())


func select(eid: String) -> void:
	if agent_link != null and (eid != selected or not group.is_empty()):
		agent_link.notify_selection([eid] if eid != "" else [])
	selected = eid
	group = []
	sel_version += 1
	var e := doc.find(eid)
	if not e.is_empty() and e.has("altitude") and doc.level_of(e) >= 0 and doc.level_of(e) != floor_k:
		floor_k = doc.level_of(e)
		_view_alt = doc.level_alt(floor_k)
		_raster_dirty = true
		_update_title()
	# Gizmo de toutes les vues (Dessus, élévations, 3D) : suit la sélection,
	# un geste sur l'élément quitté est annulé, aucune trace ne reste.
	if views != null:
		views.sync_selection()
	if invalid.has(eid):
		set_status(invalid[eid], true)
	panels.refresh()
	object_list.refresh_rows()
	canvas.queue_redraw()
	send_presence()


# ------------------------------------------------------------------ sélection multiple (MapGroup)

## La sélection : les éléments du groupe, l'élément choisi seul, ou [].
func sel_ids() -> Array:
	if group.size() >= 2:
		return group.duplicate()
	return [selected] if selected != "" else []


func is_selected(eid: String) -> bool:
	return eid != "" and (eid == selected or group.has(eid))


## Choisit plusieurs éléments (rectangle, Ctrl+A, collage, Claude) ; un seul :
## comme select ; aucun : désélectionne. Les zones et les identifiants
## inconnus sont ignorés. L'étage courant ne change pas.
func select_many(ids: Array) -> void:
	var list := MapGroup.clean_ids(doc, ids)
	if list.size() <= 1:
		select(String(list[0]) if list.size() == 1 else "")
		return
	if agent_link != null and list != group:
		agent_link.notify_selection(list)
	group = list
	selected = ""
	sel_version += 1
	# Plus d'élément seul : gestes du gizmo annulés, vues redessinées.
	views.sync_selection()
	panels.refresh()
	object_list.refresh_rows()
	send_presence()
	var bad := list.filter(func(i): return invalid.has(i))
	if not bad.is_empty():
		set_status(Lang.t("%d éléments sélectionnés — %s", "%d elements selected — %s") % [list.size(), invalid[bad[0]]], true)
	else:
		set_status(Lang.t("%d éléments sélectionnés (glisser : déplacer · R : pivoter · Ctrl+D : dupliquer · clic droit : menu)",
			"%d elements selected (drag: move · R: rotate · Ctrl+D: duplicate · right click: menu)") % list.size())


## Maj + clic : ajoute l'élément à la sélection, ou l'en retire.
func toggle_selected(eid: String) -> void:
	if eid == "":
		return
	var ids := sel_ids()
	if ids.has(eid):
		ids.erase(eid)
	else:
		ids.append(eid)
	select_many(ids)


## Ctrl+A : tous les éléments de l'étage affiché (pièces, ouvertures, objets).
func select_all() -> void:
	var ids := []
	for list in [doc.rooms_on(floor_k), doc.openings_on(floor_k), doc.objects_on(floor_k)]:
		for e in list:
			ids.append(String(e.id))
	if ids.is_empty():
		set_status(Lang.t("Rien à sélectionner au niveau %s", "Nothing to select on level %s") % EditorMap.alt_text(view_alt(), not Lang.is_en()))
		return
	select_many(ids)


## Sélection retirée des éléments disparus (annulation, autre participant) ;
## un seul restant : il redevient l'élément choisi.
func _prune_group() -> void:
	if group.is_empty():
		return
	var kept := MapGroup.clean_ids(doc, group)
	if kept.size() == group.size():
		return
	sel_version += 1
	if kept.size() >= 2:
		group = kept
	else:
		group = []
		selected = String(kept[0]) if kept.size() == 1 else ""


## Refus d'une action de groupe : message près du curseur et dans la barre
## d'état, élément fautif entouré de rouge à la place refusée (MapGroup.named).
func show_group_refusal(r: Dictionary) -> void:
	canvas.show_refusal(r)
	canvas.refusal_elems = [r.el] if r.get("el") is Dictionary else []
	views.redraw_overlays()


## Supprime la sélection (un élément : delete_element, avec son contenu ;
## un groupe : MapGroup, en une étape d'annulation).
func delete_selection() -> void:
	var ids := sel_ids()
	if ids.is_empty():
		return
	if edit_blocked():
		return
	if ids.size() == 1:
		delete_element(ids[0])
		return
	var r := MapGroup.delete_ids(self, ids)
	if not r.ok:
		show_group_refusal(r)
		return
	set_status(Lang.t("%d éléments supprimés (Ctrl+Z : annuler)", "%d elements deleted (Ctrl+Z: undo)") % int(r.n))


## Flèches : la sélection avance d'un pas (grille 1 m, grille fine ; 0,1 m
## sans grille), en une étape d'annulation par appui.
func nudge_selection(dir: Vector2) -> void:
	var ids := sel_ids()
	if ids.is_empty() or edit_blocked():
		return
	var s := canvas.step() if canvas.mode_now() != "libre" else 0.1
	var delta := dir * s
	var snap := doc.snapshot()
	var res := {}
	if ids.size() == 1:
		var e := doc.find(ids[0])
		res = try_move(e.duplicate(true), attached_to(e), delta, snap)
		if not res.ok:
			doc.restore(snap)
			moved_live()
	else:
		res = MapGroup.move(self, MapGroup.movers(doc, ids), delta, 0, snap)
	if not res.ok:
		if res.has("el"):
			show_group_refusal(res)
		else:
			canvas.show_refusal(res)
		return
	push_undo_snapshot(snap)
	changed()
	set_status(Lang.t("Déplacé de %s m (flèches)", "Moved by %s m (arrow keys)") % MapRules._m(s, not Lang.is_en()))


## Ctrl+D : copie de la sélection posée à côté d'elle (MapGroup.duplicate_ids),
## qui devient la sélection.
func duplicate_selection() -> void:
	var ids := sel_ids()
	if ids.is_empty():
		set_status(Lang.t("Dupliquer : choisissez d'abord un ou plusieurs éléments", "Duplicate: pick one or more elements first"))
		return
	if edit_blocked():
		return
	var r := MapGroup.duplicate_ids(self, ids)
	if not r.ok:
		show_group_refusal(r)
		return
	set_status(Lang.t("Dupliqué %s : %d élément(s) (Ctrl+Z : annuler)", "Duplicated %s: %d element(s) (Ctrl+Z: undo)") % [Lang.t(r.dir[0], r.dir[1]), (r.ids as Array).size()])


## Ctrl+X : copie EXACTEMENT ce qui va être supprimé (la sélection et ses
## rattachés : contenu d'une pièce, portes de ses bords), puis supprime (une
## étape d'annulation) ; Ctrl+V rend le tout (identifiants neufs). Suppression
## refusée : le presse-papiers n'est pas touché.
func cut_selected() -> void:
	var ids := sel_ids()
	if ids.is_empty() or edit_blocked():
		return
	var items := MapGroup.copies(doc, MapGroup.movers(doc, ids))
	var before := doc_version
	delete_selection()
	if doc_version == before or not MapGroup.clean_ids(doc, ids).is_empty():
		return
	clipboard = {"items": items}
	set_status(Lang.t("Coupé : %d élément(s), contenu compris (Ctrl+V pour coller sous le curseur)", "Cut: %d element(s), content included (Ctrl+V to paste under the cursor)") % items.size())


## Créer une prefab de la sélection (Ctrl+G, clic droit, propriétés) : la
## boîte de MapPrefabTools.
func create_prefab_from_selection() -> void:
	if edit_blocked():
		return
	var ids := sel_ids()
	if ids.is_empty():
		set_status(Lang.t("Créer une prefab : sélectionnez d'abord du décor posé (Maj + clic, ou un rectangle)",
			"Create a prefab: select placed props first (Shift + click, or a rectangle)"), true)
		return
	prefab_tools.create_dialog_for(ids)


## Clic droit sans tracé ni glissement en cours (toutes les vues) : sur un
## élément non choisi, il est choisi d'abord ; puis le menu (MapContextMenu)
## en `screen_pos` (pixels de l'écran). `at_m` : point du plan pour « Coller
## ici » (Vector2.INF hors de la vue Dessus).
func open_context_menu(screen_pos: Vector2, at_m: Vector2, eid: String, vertex := {}) -> MapContextMenu:
	if eid != "" and not is_selected(eid):
		select(eid)
	if context_menu == null:
		context_menu = MapContextMenu.new()
		context_menu.ed = self
		add_child(context_menu)
	# Clic droit sur un sommet ou un côté du contour choisi (MapCanvas) :
	# {id, vertex} ou {id, edge, p} -> « Supprimer ce point », « Ajouter un point ici ».
	context_menu.vertex = vertex
	context_menu.open(screen_pos, at_m)
	return context_menu


## Survol d'un élément sur la carte : sa ligne est surlignée dans la liste des
## objets (qui saute à la bonne page) et l'élément est entouré sur la carte.
func map_hovered(eid: String) -> void:
	if eid == hover_id:
		return
	hover_id = eid
	object_list.show_hover(eid)
	canvas.queue_redraw()


## Survol d'une ligne de la liste : l'élément est entouré sur la carte, la vue
## ne bouge pas.
func list_hovered(eid: String) -> void:
	if eid == hover_id:
		return
	hover_id = eid
	canvas.queue_redraw()


## Double-clic sur une ligne : vue centrée et zoomée sur l'élément.
func zoom_to_element(eid: String) -> void:
	focus_element(eid)
	var e := doc.find(eid)
	if e.is_empty():
		return
	var r := MapGeom.bbox(doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
	var avail := canvas.size * 0.6
	canvas.zoom = clampf(minf(avail.x / maxf(r.size.x, 1.0), avail.y / maxf(r.size.y, 1.0)), MapCanvas.MIN_ZOOM, 60.0)
	canvas.center_on(r.get_center() if not String(e.get("type", "")) in MapRules.ouvertures_types() else MapGeom.v2(e.position))


## Centre la vue sur un élément et le choisit.
func focus_element(eid: String) -> void:
	select(eid)
	var e := doc.find(eid)
	if e.is_empty():
		return
	var r := MapGeom.bbox(doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
	if String(e.get("type", "")) in MapRules.ouvertures_types():
		r = Rect2(MapGeom.v2(e.position), Vector2.ZERO)
	canvas.center_on(r.get_center())


func default_door_price() -> int:
	var n := doc.ouvertures.filter(func(o): return String(o.type) in ["porte", "debris"]).size()
	return MapCatalog.DOOR_PRICES[mini(n, MapCatalog.DOOR_PRICES.size() - 1)]


## Ajoute un élément posé par un outil (pièce, ouverture, objet) au niveau `k`.
func add_object(o: Dictionary, k: int) -> Dictionary:
	push_undo()
	var e := o.duplicate(true)
	doc.set_level(e, k)
	insert_element(e)
	selected = String(e.id)
	group = []
	sel_version += 1
	canvas.refusal = ""
	changed()
	set_status(Lang.t("%s posé", "%s placed") % _label(e))
	return e


## Boîte de confirmation de la découpe (MapCarve, docs/MAP_AUTHORING.md § 3) :
## pièce `obj` tracée à l'étage `k` par-dessus d'autres (`plan` : la découpe
## prévue). « Découper » (Entrée) : carve_room ; « Annuler » (Échap, croix) :
## rien n'est créé.
func confirm_carve(obj: Dictionary, k: int, plan: Dictionary) -> ConfirmationDialog:
	if is_instance_valid(carve_dialog):
		carve_dialog.queue_free()
	var d := ConfirmationDialog.new()
	d.name = "CarveDialog"
	d.title = Lang.t("Découper des pièces", "Cut rooms")
	d.dialog_text = MapCarve.describe(plan) + "\n\n" + Lang.t("Continuer ?", "Continue?")
	d.dialog_autowrap = true
	d.min_size = Vector2i(int(EditorUi.px(520.0)), 0)
	d.ok_button_text = Lang.t("Découper", "Cut")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	add_child(d)
	# Pièce et parties retirées affichées tant que la boîte est ouverte.
	canvas.carve_pending = {"poly": MapGeom.poly(obj.get("contour", [])), "plan": plan}
	canvas.queue_redraw()
	var state := {"done": false}
	d.confirmed.connect(func():
		if state.done:
			return
		state.done = true
		d.queue_free()
		canvas.carve_pending = {}
		carve_room(obj, k))
	d.canceled.connect(func():
		if state.done:
			return
		state.done = true
		d.queue_free()
		canvas.carve_pending = {}
		canvas.queue_redraw()
		set_status(Lang.t("Découpe annulée : rien n'a été créé", "Cut cancelled: nothing was created")))
	d.popup_centered()
	# Entrée = Découper : le bouton a le focus.
	d.get_ok_button().grab_focus.call_deferred()
	carve_dialog = d
	return d


## Boîte « Découper des pièces » ouverte (null sinon).
var carve_dialog: ConfirmationDialog


## Pose la pièce `obj` à l'étage `k` et découpe celles qu'elle recouvre : UNE
## étape d'annulation (et un seul lot d'opérations pour la session). Rend le
## résultat de MapCarve.carve (refus : rien n'est changé, raison affichée).
func carve_room(obj: Dictionary, k: int) -> Dictionary:
	push_undo()
	var back := doc.snapshot()
	var e := obj.duplicate(true)
	doc.set_level(e, k)
	insert_element(e)
	var rep := MapCarve.carve(doc, e)
	if not rep.ok:
		doc.restore(back)
		_commit_change()
		canvas.show_refusal(rep)
		_refresh()
		return rep
	selected = String(e.id)
	group = []
	sel_version += 1
	canvas.refusal = ""
	changed()
	set_status(Lang.t("%s posée ; %s (Ctrl+Z : tout annuler)", "%s placed; %s (Ctrl+Z: undo all)") % [_label(e), MapCarve.short(rep)])
	return rep


## Ajoute l'élément `e` (son « altitude » déjà mise) à la carte, sans étape
## d'annulation ni rafraîchissement (add_object, collage d'un groupe) :
## identifiant neuf ; pièce : nom et zone par défaut ; porte : prix par
## défaut ; boîte de départ : la seule.
func insert_element(e: Dictionary) -> void:
	if e.has("contour"):
		e["id"] = doc.new_id("p")
		var n := doc.pieces.size() + 1
		var named := e.has("nom")
		if not named:
			e["nom"] = Lang.t("Pièce %d", "Room %d") % n
		# Par défaut, une zone par pièce (même nom, en français et en anglais).
		if doc.zone(String(e.get("zone", ""))).is_empty():
			var z := doc.add_zone(String(e.nom) if named else "Pièce %d" % n, String(e.nom) if named else "Room %d" % n)
			e["zone"] = String(z.id)
		doc.pieces.append(e)
	elif String(e.get("type", "")) in MapRules.ouvertures_types():
		e["id"] = doc.new_id("o")
		if String(e.type) in ["porte", "debris"] and not e.has("prix"):
			e["prix"] = default_door_price()
		if String(e.type) == "fenetre":
			e.erase("largeur")
		doc.ouvertures.append(e)
	else:
		var prefix: String = {"atout": "a", "arme": "w", "boite": "b", "depart": "s", "escalier": "e", "pilier": "x", "mur": "m", "mur_courbe": "m",
			"piege": "t", "levier": "l", "prefab": "d", "luminaire": "lu", "bloc_invisible": "i", "effet": "fx"}.get(String(e.get("type", "")), "x")
		e["id"] = doc.new_id(prefix)
		# Un seul départ de la boîte.
		if String(e.type) == "boite" and e.get("depart", false):
			for q in doc.objets:
				if String(q.get("type", "")) == "boite":
					q["depart"] = false
		doc.objets.append(e)


func _label(e: Dictionary) -> String:
	if e.has("contour"):
		return Lang.t("Pièce « %s »", "Room \"%s\"") % e.get("nom", "")
	return MapCatalog.name_of(MapCatalog.item_for(e))


## Éléments rattachés à une pièce (qui bougent et pivotent avec elle).
func attached_to(e: Dictionary) -> Array:
	return MapTransform.attached(doc, e)


## Élément sous le point `m` de l'étage courant (ouvertures et objets avant les pièces).
func element_at(m: Vector2) -> Dictionary:
	for o in doc.openings_on(floor_k):
		if MapRules.hit(doc, o, m):
			return o
	# Le plus petit objet touché d'abord (une lampe sur un bureau). Seuls les
	# objets rangés dans la case de 4 m du point sont essayés (survol fluide
	# avec 2000 objets).
	var best := {}
	var best_area := INF
	for o in _hit_candidates(m):
		if MapRules.hit(doc, o, m):
			var a := MapRules.footprint_rect(o).get_area()
			if a < best_area:
				best_area = a
				best = o
	if not best.is_empty():
		return best
	for p in doc.rooms_on(floor_k):
		if MapRules.hit(doc, p, m):
			return p
	return {}


## Index des objets par cases de 4 m (étage -> {case: [objets]}), refait
## après chaque modification (clic, survol : seulement les objets proches).
const HIT_BUCKET := 4.0
var _hit_index: Dictionary = {}
var _hit_dirty := true


func _hit_candidates(m: Vector2) -> Array:
	if _hit_dirty:
		_hit_dirty = false
		_hit_index = {}
		for o in doc.objets:
			var r := MapRules.footprint_rect(o).grow(0.35)
			# Un escalier se choisit aussi depuis l'étage où il arrive.
			var ks := [doc.level_of(o)]
			if String(o.get("type", "")) == "escalier":
				ks.append(ks[0] + 1)
			for kk in ks:
				var grid: Dictionary = _hit_index.get_or_add(kk, {})
				for j in range(floori(r.position.y / HIT_BUCKET), floori(r.end.y / HIT_BUCKET) + 1):
					for i in range(floori(r.position.x / HIT_BUCKET), floori(r.end.x / HIT_BUCKET) + 1):
						grid.get_or_add(Vector2i(i, j), []).append(o)
	return _hit_index.get(floor_k, {}).get(Vector2i(floori(m.x / HIT_BUCKET), floori(m.y / HIT_BUCKET)), [])


func delete_element(eid: String) -> void:
	var e := doc.find(eid)
	if e.is_empty():
		return
	# § 7 : un décor qui en porte un autre ne disparaît pas seul.
	if not MapVertical.resting_on(doc, e, attached_to(e)).is_empty():
		canvas.show_refusal(MapRules.refuse("un décor est posé dessus : supprimez-le d'abord", "a prop stands on it: delete that one first"))
		return
	push_undo()
	var n := 1
	for a in attached_to(e):
		doc.remove(a)
		n += 1
	doc.remove(eid)
	doc.tidy_zones()
	if selected == eid:
		selected = ""
	changed()
	set_status(Lang.t("%s supprimé", "%s deleted") % _label(e) + (Lang.t(" (avec %d élément(s) rattaché(s))", " (with %d attached element(s))") % (n - 1) if n > 1 else ""))


## Remplace un élément par sa nouvelle version (même identifiant).
func _replace(e: Dictionary) -> void:
	var list := doc.list_of(String(e.id))
	for i in list.size():
		if String(list[i].id) == String(e.id):
			list[i] = e
			return


static func _shift(o: Dictionary, delta: Vector2) -> Dictionary:
	var e := o.duplicate(true)
	if e.has("contour"):
		var pts := []
		for p in e.contour:
			pts.append(MapGeom.arr(MapGeom.v2(p) + delta))
		e.contour = pts
		if e.has("forme") and MapShapes.valid(e.forme):
			e.forme = MapShapes.shifted(e.forme, delta)
	if e.has("sommets"):
		# Barrière invisible en polygone (format 9).
		var pts := []
		for p in e.sommets:
			pts.append(MapGeom.arr(MapGeom.v2(p) + delta))
		e.sommets = pts
	for key in ["position", "a", "b", "centre"]:
		if e.has(key):
			e[key] = MapGeom.arr(MapGeom.v2(e[key]) + delta)
	if e.has("rect"):
		var r := MapGeom.rect_of(e.rect)
		r.position += delta
		e.rect = MapGeom.rect_arr(r)
	return e


## Déplacement pendant un glissement : essaie `orig` décalé de `delta`
## (depuis la carte `snap0`), l'applique s'il est valide.
func try_move(orig: Dictionary, attached: Array, delta: Vector2, snap0: Dictionary) -> Dictionary:
	var k := doc.level_of(orig)
	var cand := _shift(orig, delta)
	var t := String(orig.get("type", ""))
	var res := {"ok": true}
	if orig.has("contour"):
		res = MapRules.check_room(doc, k, doc.room_poly(cand), String(orig.id))
	elif t in MapRules.ouvertures_types():
		res = MapRules.place_opening(doc, k, t, MapGeom.v2(cand.position), MapRules.opening_width(orig), String(orig.id))
		if res.ok:
			cand.position = res.position
	elif t == "boite":
		# Boîte mystère (format 16) : son centre suit le curseur ; près d'un mur
		# elle s'y colle, décollée elle se pose au sol (Alt : sans aimant).
		res = MapRules.place_box(doc, k, orig, MapGeom.centroid(MapRules.exact_poly(cand)), String(orig.id), canvas.mode_now() != "libre", not canvas.angle_free())
		if res.ok:
			MapRules.apply_box(cand, res)
	else:
		match MapCatalog.tool_of(orig):
			"wall_item":
				res = MapRules.place_wall_item(doc, k, orig, MapRules.footprint_rect(cand).get_center(), String(orig.id), canvas.mode_now() != "libre")
				if res.ok:
					cand.position = res.position
					MapRules.apply_wall(cand, res)
			"floor_item":
				res = MapRules.place_floor_item(doc, k, orig, MapGeom.v2(cand.position), String(orig.id), canvas.mode_now() != "libre")
				if res.ok:
					cand.position = res.position
			"rect":
				res = MapRules.check_rect(doc, k, t, MapGeom.rect_of(cand.rect), String(orig.id), MapGeom.rot_of(cand))
			"poly":
				res = MapRules.check_clip(MapRaster.clip_poly(cand))
			"wall":
				res = MapRules.check_wall(MapGeom.v2(cand.a), MapGeom.v2(cand.b))
			"arc":
				res = MapRules.check_arc(cand)
	if not res.ok:
		return res
	# § 7 : les décors posés dessus le restent (sinon refus, dernière place gardée).
	var held := MapVertical.resting_on(doc, orig, attached)
	var last := {}
	if not held.is_empty():
		for eid in [String(orig.id)] + attached:
			var cur := doc.find(String(eid))
			if not cur.is_empty():
				last[String(eid)] = cur.duplicate(true)
	doc.restore(snap0)
	_replace(cand)
	for aid in attached:
		var a := doc.find(aid)
		if not a.is_empty():
			_replace(_shift(a, delta))
	if not held.is_empty():
		var rest := MapVertical.check_rests(doc, held)
		if not rest.ok:
			doc.restore(snap0)
			for eid in last:
				_replace(last[eid].duplicate(true))
			moved_live()
			return rest
	if t in ["mur", "mur_courbe"]:
		# Objets accrochés au mur libre : raccrochés à sa face (un mur déplacé
		# hors de la grille devient un vrai mur oblique).
		for aid in attached:
			var a := doc.find(aid)
			if a.is_empty():
				continue
			var r := MapRules.place_wall_item(doc, k, a, MapGeom.v2(a.position) - MapGeom.item_wall_dir(a) * 0.3, aid)
			if r.ok:
				a["position"] = r.position
				MapRules.apply_wall(a, r)
	moved_live()
	return res


## Déplacement dans une élévation (docs/EDITOR_VIEWS.md, § 6.1) : `orig`
## décalé de `delta` dans le plan, à l'étage `k_new` (une pièce emporte son
## contenu), à la hauteur de pose `z_local` (m au-dessus du sol de l'étage ;
## NAN : inchangée), depuis la carte `snap0` ; appliqué s'il est valide
## (règles de pose de l'étage cible, MapRules ; bornes et décor posé sur un
## autre, MapVertical.check_pose). Sinon la carte reste à `snap0`.
func try_move_3d(orig: Dictionary, attached: Array, delta: Vector2, k_new: int, z_local: float, snap0: Dictionary) -> Dictionary:
	if k_new < 0 or k_new >= doc.level_count():
		return MapRules.refuse("pas de niveau à cette hauteur", "no level at that height")
	if String(orig.get("type", "")) == "escalier" and k_new >= doc.level_count() - 1:
		return MapRules.refuse("un escalier ne peut pas aller sur le dernier niveau", "stairs cannot go on the top level")
	return try_move_alt(orig, attached, delta, doc.level_alt(k_new) - EditorMap.alt_of(orig), z_local, snap0)


## Comme try_move_3d, mais monté (ou descendu) de `dalt` m (format 17 :
## propriété « Altitude du sol » d'une pièce, qui emporte son contenu). Une
## pièce peut créer un niveau ; refus si deux niveaux se retrouvent à moins de
## 3,1 m (restriction de l'étape 1a) ou si un élément n'a plus de pièce sous lui.
func try_move_alt(orig: Dictionary, attached: Array, delta: Vector2, dalt: float, z_local: float, snap0: Dictionary) -> Dictionary:
	if not is_finite(dalt):
		return MapRules.refuse("altitude invalide", "invalid altitude")
	# Refus : l'élément (et son contenu) reste à sa DERNIÈRE place valide (§ 6.1),
	# pas à celle du début du glissement.
	var last := {}
	for eid in [String(orig.id)] + attached:
		var cur := doc.find(String(eid))
		if not cur.is_empty():
			last[String(eid)] = cur.duplicate(true)
	var refuse := func(r: Dictionary) -> Dictionary:
		doc.restore(snap0)
		for eid in last:
			_replace(last[eid].duplicate(true))
		moved_live()
		return r
	doc.restore(snap0)
	var held := MapVertical.resting_on(doc, orig, attached)
	var base := orig.duplicate(true)
	# Hauteur de pose d'abord (un décor posé sur un autre ne le chevauche pas).
	if not is_nan(z_local):
		MapVertical.set_pose_z(doc, raster().v, base, z_local)
	var snap1 := snap0
	var moved_up := absf(dalt) > EditorMap.ALT_EQ
	if moved_up or not is_nan(z_local):
		EditorMap.shift_alt(base, dalt)
		_replace(base.duplicate(true))
		for aid in attached:
			var a := doc.find(aid)
			if not a.is_empty():
				EditorMap.shift_alt(a, dalt)
		snap1 = doc.snapshot()
	if moved_up:
		if doc.level_of(base) < 0:
			return refuse.call(MapRules.refuse("pas de pièce à cette altitude (%s)" % EditorMap.alt_text(EditorMap.alt_of(base)),
				"no room at that altitude (%s)" % EditorMap.alt_text(EditorMap.alt_of(base), false)))
		if not doc.level_gap_issue().is_empty():
			var gt := MapGroup.gap_text(doc)
			return refuse.call(MapRules.refuse(gt[0], gt[1]))
	var k_new := doc.level_of(base)
	var res := try_move(base, attached, delta, snap1)
	if not res.ok:
		return refuse.call(res)
	if moved_up:
		# Contenu emporté (pièce) : valide aussi sur l'étage visé (portes sur un
		# bord commun, escalier jamais sur le dernier étage, objets contre un mur).
		MapRules.begin_batch(doc)
		var bad := {}
		for aid in attached:
			var a := doc.find(aid)
			if a.is_empty():
				continue
			if String(a.get("type", "")) == "escalier" and doc.level_of(a) >= doc.level_count() - 1:
				bad = MapRules.refuse("son escalier ne peut pas aller sur le dernier niveau", "its stairs cannot go on the top level")
				break
			var r := MapRules.check_existing(doc, a)
			if not r.ok:
				bad = MapRules.refuse("son contenu ne tient pas au niveau %s : %s (%s)" % [EditorMap.alt_text(doc.level_alt(k_new)), _label(a), MapRules.why(r)],
					"its content does not fit on level %s: %s (%s)" % [EditorMap.alt_text(doc.level_alt(k_new), false), _label(a), MapRules.why(r)])
				break
		MapRules.end_batch()
		if not bad.is_empty():
			return refuse.call(bad)
	if not is_nan(z_local):
		var now := doc.find(String(orig.id))
		MapVertical.set_pose_z(doc, raster().v, now, z_local)
		var chk := MapVertical.check_pose(doc, raster().v, now)
		if not chk.ok:
			return refuse.call(chk)
		moved_live()
	# § 7 : un décor qui en porte un autre (bloquant) ne bouge pas seul.
	var rest := MapVertical.check_rests(doc, held)
	if not rest.ok:
		return refuse.call(rest)
	return res


## Poignée `h` de l'élément `orig` amenée au point `p`.
func try_handle(orig: Dictionary, h: int, p: Vector2, snap0: Dictionary) -> Dictionary:
	var k := doc.level_of(orig)
	var cand := orig.duplicate(true)
	var res := {"ok": true}
	if orig.has("contour"):
		var poly := doc.room_poly(orig)
		var np := PackedVector2Array()
		if MapGeom.is_axis_rect(poly) and not orig.has("forme"):
			var r := MapGeom.bbox(poly)
			var x0 := r.position.x
			var y0 := r.position.y
			var x1 := r.end.x
			var y1 := r.end.y
			# Coins 0-3 (haut-gauche, haut-droit, bas-droit, bas-gauche), milieux 4-7 (haut, droite, bas, gauche).
			if h in [0, 3, 7]:
				x0 = p.x
			if h in [1, 2, 5]:
				x1 = p.x
			if h in [0, 1, 4]:
				y0 = p.y
			if h in [2, 3, 6]:
				y1 = p.y
			np = MapGeom.rect_poly(Rect2(Vector2(x0, y0), Vector2.ZERO).expand(Vector2(x1, y1)))
		else:
			np = poly.duplicate()
			np[h] = p
		cand.contour = MapGeom.poly_arr(np)
		# Sommet déplacé à la main : la forme de base d'origine ne se régénère plus.
		cand.erase("forme")
		res = MapRules.check_room(doc, k, np, String(orig.id))
	elif orig.has("sommets"):
		# Barrière invisible en polygone (format 9) : le sommet `h` suit le curseur.
		var np := MapGeom.poly(orig.sommets)
		if h >= 0 and h < np.size():
			np[h] = p
		cand.sommets = MapGeom.poly_arr(np)
		res = MapRules.check_clip(np)
	elif orig.has("rect") and MapGeom.rot_of(orig) != 0:
		# Rectangle tourné : le coin opposé reste en place, dans le repère du rectangle.
		var rot := float(MapGeom.rot_of(orig))
		var corners := MapRaster.rect_poly(orig)
		var opp: Vector2 = corners[(h + 2) % 4]
		var local := (p - opp).rotated(-deg_to_rad(rot))
		var sz := local.abs()
		var c := opp + (local * 0.5).rotated(deg_to_rad(rot))
		var nr := Rect2(c - sz * 0.5, sz)
		cand.rect = MapGeom.rect_arr(nr)
		res = MapRules.check_rect(doc, k, String(orig.type), nr, String(orig.id), int(rot))
	elif orig.has("rect"):
		var r := MapGeom.rect_of(orig.rect)
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var opp: Vector2 = corners[(h + 2) % 4]
		var nr := Rect2(opp, Vector2.ZERO).expand(p)
		cand.rect = MapGeom.rect_arr(nr)
		res = MapRules.check_rect(doc, k, String(orig.type), nr, String(orig.id))
	elif String(orig.get("type", "")) == "mur":
		cand["a" if h == 0 else "b"] = MapGeom.arr(p)
		res = MapRules.check_wall(MapGeom.v2(cand.a), MapGeom.v2(cand.b))
	elif String(orig.get("type", "")) == "effet":
		# Format 11 : zone de l'effet, le côté opposé reste en place, bornes de l'effet.
		cand = MapTransform.effect_resized(orig, h, p)
		res = MapRules.check_existing(doc, cand)
	if not res.ok:
		return res
	doc.restore(snap0)
	_replace(cand)
	moved_live()
	return res


# ------------------------------------------------------------------ points d'un contour libre

## Point `p` ajouté au contour de `orig` (pièce, barrière invisible) après le
## sommet `edge`, depuis l'état `snap0` (poignée « + » glissée, MapVertex) :
## mêmes règles qu'un sommet déplacé. Une pièce rectangle devient un polygone.
func try_insert_vertex(orig: Dictionary, edge: int, p: Vector2, snap0: Dictionary) -> Dictionary:
	var poly := MapVertex.poly_of(orig)
	if edge < 0 or edge >= poly.size():
		return MapRules.refuse("côté introuvable", "side not found")
	if poly.size() >= MapVertex.max_points(orig):
		return MapRules.refuse("%d sommets au plus" % MapVertex.max_points(orig), "%d corners at most" % MapVertex.max_points(orig))
	var w := MapVertex.with_poly(doc, orig, MapVertex.inserted(poly, edge, p))
	if not w.res.ok:
		return w.res
	doc.restore(snap0)
	_replace(w.cand)
	moved_live()
	return w.res


## Sommet `i` retiré du contour de `orig` depuis l'état `snap0` (jamais moins
## de 3 sommets, mêmes règles qu'un sommet déplacé).
func try_remove_vertex(orig: Dictionary, i: int, snap0: Dictionary) -> Dictionary:
	var poly := MapVertex.poly_of(orig)
	if i < 0 or i >= poly.size():
		return MapRules.refuse("sommet introuvable", "corner not found")
	var w := MapVertex.with_poly(doc, orig, MapVertex.removed(poly, i))
	if not w.res.ok:
		return w.res
	doc.restore(snap0)
	_replace(w.cand)
	moved_live()
	return w.res


## Ajoute le point `p` au contour de l'élément `eid` après le sommet `edge`
## (double-clic sur un côté, menu du clic droit) : une étape d'annulation,
## diffusée aux autres participants ; refus expliqué dans la barre d'état.
func insert_vertex(eid: String, edge: int, p: Vector2) -> Dictionary:
	var e := doc.find(eid)
	if e.is_empty() or not MapVertex.editable(e):
		return MapRules.refuse("cet élément n'a pas de contour libre", "this element has no free outline")
	var snap0 := doc.snapshot()
	var res := try_insert_vertex(e.duplicate(true), edge, p, snap0)
	_vertex_done(res, snap0, eid, true)
	return res


## Supprime le sommet `i` du contour de l'élément `eid` (Suppr sur un sommet
## survolé, menu du clic droit) : une étape d'annulation.
func remove_vertex(eid: String, i: int) -> Dictionary:
	var e := doc.find(eid)
	if e.is_empty() or not MapVertex.editable(e):
		return MapRules.refuse("cet élément n'a pas de contour libre", "this element has no free outline")
	var snap0 := doc.snapshot()
	var res := try_remove_vertex(e.duplicate(true), i, snap0)
	_vertex_done(res, snap0, eid, false)
	return res


## Fin d'un ajout ou d'une suppression de point : historique et diffusion, ou
## refus montré sur la carte.
func _vertex_done(res: Dictionary, snap0: Dictionary, eid: String, added: bool) -> void:
	if not res.ok:
		canvas.show_refusal(res)
		return
	push_undo_snapshot(snap0)
	changed()
	vertex_status(eid, added)


## Barre d'état après un point ajouté ou supprimé.
func vertex_status(eid: String, added: bool) -> void:
	var n := MapVertex.poly_of(doc.find(eid)).size()
	set_status((Lang.t("Point ajouté : %d sommets (Ctrl+Z : annuler)", "Point added: %d corners (Ctrl+Z: undo)") if added
		else Lang.t("Point supprimé : %d sommets (Ctrl+Z : annuler)", "Point deleted: %d corners (Ctrl+Z: undo)")) % n)


## Élément tourné de 90° (sens horaire) autour de `c` (MapTransform.rotated).
static func _rot(o: Dictionary, c: Vector2) -> Dictionary:
	return MapTransform.rotated(o, c, 90.0)


## Emprise d'un objet au sol pivoté : sa position est ré-aimantée pour que ses
## cases tombent sur la grille (un prefab 3 × 2 devient 2 × 3).
func _resnap(o: Dictionary) -> void:
	MapTransform.resnap(o)


## R : pivote de 90° l'objet tenu (prefab, luminaire : avant de le poser),
## sinon l'élément choisi (une pièce pivote avec son contenu).
func rotate_selected() -> void:
	var held := current_item()
	if String(held.get("tool", "")) == "room_rect":
		# Pièce rectangle : R bascule entre un rectangle droit et un rectangle
		# tourné de 45° (losange), tracé d'un coin à l'autre.
		place_rot = 45 if place_rot != 45 else 0
		canvas.queue_redraw()
		set_status(Lang.t("Pièce rectangle : tournée de 45° (R pour revenir droite)", "Rectangle room: turned 45° (R to go back straight)") if place_rot == 45
			else Lang.t("Pièce rectangle : droite (R pour la tourner de 45°)", "Rectangle room: straight (R to turn it 45°)"))
		return
	if held.get("rotates", false):
		place_rot = (place_rot + 90) % 360
		canvas._update_preview()
		canvas.queue_redraw()
		set_status(Lang.t("%s : rotation %d°", "%s: rotation %d°") % [MapCatalog.name_of(held), place_rot])
		return
	rotate_selection()


## Pivote la sélection de 90° : un élément autour de son centre (une pièce
## avec son contenu), un groupe autour du centre du groupe (MapGroup.rotate).
func rotate_selection() -> void:
	if edit_blocked():
		return
	if group.size() >= 2:
		var snap := doc.snapshot()
		var c := MapGroup.pivot(doc, group, canvas.mode_now() == "libre")
		var r := MapGroup.rotate(self, MapGroup.movers(doc, group), c, 90.0, snap)
		if not r.ok:
			show_group_refusal(r)
			return
		push_undo_snapshot(snap)
		changed()
		set_status(Lang.t("Groupe pivoté de 90° autour de son centre", "Group rotated 90° around its centre"))
		return
	var e := doc.find(selected)
	if e.is_empty():
		set_status(Lang.t("Choisissez d'abord un élément (outil Sélection)", "Pick an element first (Select tool)"))
		return
	if not MapTransform.can_rotate(e):
		set_status(Lang.t("Cet élément suit son mur : déplacez-le plutôt", "This element follows its wall: move it instead"))
		return
	var before := doc.snapshot()
	var c := MapTransform.pivot(doc, e)
	if e.has("contour") and not e.has("forme"):
		c = MapGeom.bbox(doc.room_poly(e)).get_center()
	# Sur la grille, un quart de tour garde les sommets sur la grille.
	if not e.has("position") and canvas.mode_now() != "libre" and not (e.has("forme") or String(e.get("type", "")) == "mur_courbe"):
		c = Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
	var attached := attached_to(e)
	var held_on := MapVertical.resting_on(doc, e, attached)
	var re := _rot(e, c)
	_resnap(re)
	_replace(re)
	for aid in attached:
		var ra := _rot(doc.find(aid), c)
		_resnap(ra)
		_replace(ra)
	var ne := doc.find(selected)
	var res := MapRules.check_existing(doc, ne)
	if res.ok:
		res = MapVertical.check_rests(doc, held_on)
	if not res.ok:
		doc.restore(before)
		_hit_dirty = true
		canvas.show_refusal(res)
		return
	push_undo_snapshot(before)
	changed()
	set_status(Lang.t("Pivoté de 90°", "Rotated 90°"))


## V : variante suivante (aspect) de l'objet tenu (avant de le poser), sinon
## de l'élément choisi (MapCatalog.VARIANTS : portes, débris, armes murales).
func cycle_variant() -> void:
	var held := current_item()
	var make: Dictionary = held.get("make", {})
	var ht := String(make.get("type", ""))
	if MapCatalog.variants(ht).size() > 1 and String(held.get("tool", "")) != "select":
		var cur := place_variant if place_variant != "" else MapCatalog.default_variant(ht)
		place_variant = MapCatalog.next_variant(ht, cur)
		canvas._update_preview()
		canvas.queue_redraw()
		set_status(Lang.t("%s : %s (V : aspect suivant)", "%s: %s (V: next look)") % [MapCatalog.name_of(held), MapCatalog.variant_name(ht, place_variant)])
		return
	var e := doc.find(selected)
	if e.is_empty():
		set_status(Lang.t("Choisissez d'abord une porte, des débris, une arme murale ou un escalier (outil Sélection)",
			"Pick a door, debris, a wall weapon or stairs first (Select tool)"))
		return
	var t := String(e.get("type", ""))
	if MapCatalog.variants(t).size() < 2:
		set_status(Lang.t("Cet élément n'a qu'un seul aspect", "This element has only one look"))
		return
	if t == "fenetre":
		# Entrée des zombies (format 8) : la porte double (2 m) doit tenir à sa
		# place ; sinon le type suivant qui tient, ou rien.
		var v := MapCatalog.variant_of(e)
		var res := {}
		for _i in MapCatalog.variants(t).size() - 1:
			v = MapCatalog.next_variant(t, v)
			res = MapRules.apply_variant(doc, e.duplicate(true), v)
			if res.ok:
				break
		if not res.ok:
			canvas.show_refusal(res)
			return
		push_undo()
		MapRules.apply_variant(doc, e, v)
		changed()
		set_status(Lang.t("Type : %s (V : suivant)", "Type: %s (V: next)") % MapCatalog.variant_name(t, v))
		return
	push_undo()
	MapCatalog.set_variant(e, MapCatalog.next_variant(t, MapCatalog.variant_of(e)))
	MapCatalog.tidy_stair(e)
	changed()
	set_status(Lang.t("Aspect : %s (V : suivant)", "Look: %s (V: next)") % MapCatalog.variant_name(t, MapCatalog.variant_of(e)))


func copy_selected() -> void:
	if group.size() >= 2:
		clipboard = {"items": MapGroup.copies(doc, group)}
		set_status(Lang.t("Copié : %d éléments (Ctrl+V pour coller sous le curseur)", "Copied: %d elements (Ctrl+V to paste under the cursor)") % (clipboard.items as Array).size())
		return
	var e := doc.find(selected)
	if e.is_empty():
		return
	clipboard = e.duplicate(true)
	set_status(Lang.t("Copié : %s (Ctrl+V pour coller sous le curseur)", "Copied: %s (Ctrl+V to paste under the cursor)") % _label(e))


## Ctrl+V : colle sous le curseur de la vue Dessus (`at` : point du plan, m ;
## Vector2.INF : la souris). Un groupe copié : MapGroup.paste (tout ou rien,
## les copies deviennent la sélection).
func paste(at := Vector2.INF) -> void:
	if clipboard.is_empty():
		set_status(Lang.t("Rien à coller", "Nothing to paste"))
		return
	if edit_blocked():
		return
	var where: Vector2 = canvas.mouse_m if at == Vector2.INF else at
	if clipboard.has("items"):
		var r := MapGroup.paste(self, clipboard.items, where)
		if not r.ok:
			show_group_refusal(r)
			return
		set_status(Lang.t("Collé : %d éléments (Ctrl+Z : annuler)", "Pasted: %d elements (Ctrl+Z: undo)") % (r.ids as Array).size())
		return
	var e := clipboard.duplicate(true)
	var c := MapRules.footprint_rect(e).get_center()
	if e.has("contour"):
		c = MapGeom.bbox(MapGeom.poly(e.contour)).get_center()
	elif e.has("position"):
		c = MapGeom.v2(e.position)
	var target := canvas.snap(where)
	var delta := target - (c if canvas.mode_now() == "libre" else Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5)))
	e = _shift(e, delta)
	e.erase("id")
	doc.set_level(e, floor_k)
	var t := String(e.get("type", ""))
	var res := {"ok": true}
	if e.has("contour"):
		e.erase("zone")
		res = MapRules.check_room(doc, floor_k, MapGeom.poly(e.contour))
	elif t in MapRules.ouvertures_types():
		res = MapRules.place_opening(doc, floor_k, t, MapGeom.v2(e.position), MapRules.opening_width(e))
		if res.ok:
			e.position = res.position
	elif t == "boite":
		# Boîte mystère (format 16) : au sol sous le curseur, ou contre le mur proche.
		res = MapRules.place_box(doc, floor_k, e, target, "", canvas.mode_now() != "libre", not canvas.angle_free())
		if res.ok:
			MapRules.apply_box(e, res)
	else:
		match MapCatalog.tool_of(e):
			"wall_item":
				res = MapRules.place_wall_item(doc, floor_k, e, target, "", canvas.mode_now() != "libre")
				if res.ok:
					e.position = res.position
					MapRules.apply_wall(e, res)
			"floor_item":
				res = MapRules.place_floor_item(doc, floor_k, e, target, "", canvas.mode_now() != "libre")
				if res.ok:
					e.position = res.position
			"rect":
				# Escalier collé : son sens (« monte ») et son type comptent.
				res = MapRules.check_rect(doc, floor_k, t, MapGeom.rect_of(e.rect), "", MapGeom.rot_of(e), MapCatalog.stair_kind(e), e if t == "escalier" else {})
			"poly":
				res = MapRules.check_clip(MapRaster.clip_poly(e))
			"wall":
				res = MapRules.check_wall(MapGeom.v2(e.a), MapGeom.v2(e.b))
			"arc":
				res = MapRules.check_arc(e)
	if not res.ok:
		canvas.show_refusal(res)
		return
	if e.has("contour"):
		e.erase("nom")
	add_object(e, floor_k)


# ------------------------------------------------------------------ zones et étages

func set_room_zone(room_id: String, zid: String) -> void:
	var r := doc.find(room_id)
	if r.is_empty():
		return
	push_undo()
	if zid == "":
		var z := doc.add_zone(String(r.get("nom", "")), String(r.get("nom", "")))
		zid = String(z.id)
	r["zone"] = zid
	doc.tidy_zones()
	changed()


func merge_zones(src: String, dst: String) -> void:
	if src == dst or doc.zone(src).is_empty() or doc.zone(dst).is_empty():
		return
	push_undo()
	for p in doc.rooms_of_zone(src):
		p["zone"] = dst
	if doc.depart == src:
		doc.depart = dst
	doc.tidy_zones()
	changed()
	set_status(Lang.t("Zones fusionnées : « %s »", "Zones merged: \"%s\"") % doc.zone_name(dst))


## Une zone par pièce (la première pièce garde la zone).
func split_zone(zid: String) -> void:
	var rooms := doc.rooms_of_zone(zid)
	if rooms.size() < 2:
		set_status(Lang.t("Cette zone n'a qu'une pièce", "This zone has a single room"))
		return
	push_undo()
	for i in range(1, rooms.size()):
		var z := doc.add_zone(String(rooms[i].get("nom", "")), String(rooms[i].get("nom", "")))
		rooms[i]["zone"] = String(z.id)
	changed()
	set_status(Lang.t("Zone séparée : une zone par pièce", "Zone split: one zone per room"))


func set_start_zone(zid: String) -> void:
	if doc.zone(zid).is_empty():
		return
	push_undo()
	doc.depart = zid
	changed()


## Altitude du niveau affiché (m).
func view_alt() -> float:
	return doc.level_alt(floor_k)


## Le niveau affiché suit son altitude quand les niveaux changent : un niveau
## vidé de ses pièces reste affiché (niveau vide de l'éditeur, jamais enregistré).
func _sync_view() -> void:
	if doc == null:
		return
	var k := doc.level_index(_view_alt)
	if k < 0:
		doc.view_levels.append(_view_alt)
		k = doc.level_index(_view_alt)
	floor_k = maxi(0, k)


func set_floor(k: int) -> void:
	var nk := clampi(k, 0, doc.level_count() - 1)
	_view_alt = doc.level_alt(nk)
	if nk == floor_k:
		return
	floor_k = nk
	canvas.cancel()
	selected = ""
	group = []
	sel_version += 1
	# Gestes des élévations et de la 3D sur l'élément quitté : annulés.
	if views != null:
		views.sync_selection()
	_raster_dirty = true
	panels.refresh()
	_update_title()
	canvas.queue_redraw()
	send_presence()


## Nouveau niveau vide 3,5 m au-dessus du plus haut (format 17 : un niveau
## existe par ses pièces ; vide, il n'est pas enregistré).
func add_floor() -> void:
	var top := doc.level_count() - 1
	doc.view_levels.append(snappedf(doc.level_alt(top) + EditorMap.FLOOR_STEP, 0.01))
	_raster_dirty = true
	set_floor(doc.level_count() - 1)
	panels.refresh()


## Met le niveau `k` à l'altitude `alt` (m) : tout ce qui y est posé (et
## l'arrivée des escaliers qui y montent) suit, en une étape d'annulation.
## Refus nommé si deux niveaux se retrouvent à moins de 3,1 m (étape 1a).
func move_level(k: int, alt: float) -> Dictionary:
	if k < 0 or k >= doc.level_count() or not is_finite(alt):
		return MapRules.refuse("niveau introuvable", "level not found")
	var dalt := snappedf(alt, 0.0001) - doc.level_alt(k)
	if absf(dalt) <= EditorMap.ALT_EQ:
		return {"ok": true}
	var snap := doc.snapshot()
	var views_before := doc.view_levels.duplicate()
	doc.shift_level(k, dalt)
	var moved_view := _view_alt
	if absf(_view_alt - (alt - dalt)) <= EditorMap.ALT_EQ:
		moved_view = alt
	if doc.level_index(alt) < 0 or not doc.level_gap_issue().is_empty():
		var gt := MapGroup.gap_text(doc)
		doc.restore(snap)
		doc.view_levels = views_before
		var res := MapRules.refuse(gt[0] if gt[0] != "" else "ce niveau en rejoint un autre", gt[1] if gt[1] != "" else "this level would merge with another")
		canvas.show_refusal(res)
		panels.refresh()
		return res
	push_undo_snapshot(snap)
	_view_alt = moved_view
	changed()
	set_status(Lang.t("Niveau déplacé à %s", "Level moved to %s") % EditorMap.alt_text(alt, not Lang.is_en()))
	return {"ok": true}


## Retire le niveau le plus haut s'il est vide (niveau vide de l'éditeur).
func remove_top_floor() -> void:
	var top := doc.level_count() - 1
	if top == 0:
		return
	var used := doc.rooms_on(top).size() + doc.objects_on(top).size() + doc.openings_on(top).size()
	if used > 0:
		set_status(Lang.t("Le niveau %s n'est pas vide (%d élément(s))", "Level %s is not empty (%d element(s))") % [EditorMap.alt_text(doc.level_alt(top)), used], true)
		return
	var a := doc.level_alt(top)
	doc.view_levels = doc.view_levels.filter(func(x): return absf(float(x) - a) > EditorMap.ALT_EQ)
	if floor_k >= top:
		_view_alt = doc.level_alt(top - 1)
	_sync_view()
	_raster_dirty = true
	_update_title()
	panels.refresh()
	canvas.queue_redraw()


# ------------------------------------------------------------------ vérification

func validate() -> MapValidator:
	_validate_t = -1.0
	validator = MapRaster.build(doc).v
	validator.analyze()
	validation_stale = false
	panels.show_validation()
	_update_title()
	return validator


## Clic sur un problème : étage, vue centrée, cases en évidence.
func focus_problem(m: Dictionary) -> void:
	var cells: Array = m.get("cells", [])
	if cells.is_empty():
		return
	var k := int(m.get("floor", -1))
	if k >= 0:
		set_floor(k)
	canvas.highlight = cells
	canvas.highlight_floor = floor_k
	var c := Vector2.ZERO
	for cc in cells:
		c += MapGeom.cell_center(cc)
	canvas.center_on(c / cells.size())


# ------------------------------------------------------------------ fichiers

func _reset(d: EditorMap) -> void:
	doc = d
	collab.reset_doc(d)
	_doc_shown()
	dirty = false
	_update_title()
	views.frame_all.call_deferred()


## Nouvelle carte affichée (ouverte, ou reprise au retour d'un test) :
## sélection, vérification, panneaux remis à zéro.
func _doc_shown() -> void:
	doc_version += 1
	_hit_dirty = true
	_before = {}
	if collab_view != null:
		collab_view.clear()
		panels.history.mark_dirty()
	selected = ""
	group = []
	sel_version += 1
	hover_id = ""
	floor_k = 0
	_view_alt = doc.level_alt(0)
	validator = null
	canvas.cancel()
	canvas.highlight = []
	object_list.mark_dirty()
	_raster_dirty = true
	validation_stale = true
	_update_invalid()
	panels.refresh()


## État de l'éditeur gardé pendant un TESTER (solo : _test_keep ; à
## plusieurs : CollabPlaytest), retrouvé au retour par _resume_playtest ;
## « saved_sig » : empreinte de l'état enregistré (étoile exacte au retour).
func playtest_state() -> Dictionary:
	return {"map_dir": map_dir, "example": example, "dirty": dirty, "saved_sig": _saved_sig, "floor_k": floor_k, "selected": selected,
		"zoom": canvas.zoom, "origin": canvas.origin}


## Retour d'un TESTER : la session (carte, historique, autres participants)
## n'a pas bougé ; la vue, l'étage et la sélection reviennent. La copie de
## travail jouée (MapUnsaved.test_dir) est effacée.
func _resume_playtest(back: Dictionary) -> void:
	var st: Dictionary = back.state
	_doc_shown()
	map_dir = String(st.get("map_dir", ""))
	example = bool(st.get("example", false))
	if st.get("saved_sig") is String:
		_saved_sig = String(st.saved_sig)
		_dirty_ver = -1
	else:
		dirty = bool(st.get("dirty", false))
	MapUnsaved._remove(MapUnsaved.test_dir())
	if collab.role == MapCollab.Role.GUEST:
		map_dir = ""
		example = false
	floor_k = clampi(int(st.get("floor_k", 0)), 0, doc.level_count() - 1)
	_view_alt = doc.level_alt(floor_k)
	var sel := String(st.get("selected", ""))
	if sel != "" and not doc.find(sel).is_empty():
		selected = sel
	_update_title()
	if st.has("zoom"):
		canvas.zoom = float(st.zoom)
		canvas.origin = st.origin
	_refresh()
	canvas.queue_redraw()
	var text := String(back.get("message", ""))
	var err := bool(back.get("error", false))
	if Router.pending_message != "":
		# Fin de la partie (« Partie terminée — ... ») ; sauf si l'hôte est
		# parti en pleine partie ou la session perdue (message plus précis).
		if text == "":
			text = Router.pending_message
			err = false
		Router.pending_message = ""
	if text == "":
		text = Lang.t("Retour du test : session toujours ouverte (%d participant(s))", "Back from the play test: session still open (%d participant(s))") % collab.peers.size() \
			if collab.is_session() else Lang.t("Retour du test", "Back from the play test")
	set_status(text, err)


## Message de TESTER à plusieurs reçu par la session : l'hôte invite à sa
## partie de test (les autres messages vont à CollabPlaytest).
func _on_playtest_message(m: Dictionary) -> void:
	if String(m.get("t", "")) == "playtest" and collab.role == MapCollab.Role.GUEST and CollabPlaytest.current == null:
		CollabPlaytest.guest_join(self, int(m.port))


func new_map(force := false) -> void:
	if refuse_guest():
		return
	if not force:
		confirm_unsaved(Lang.t("créer une nouvelle carte", "create a new map"), func(): new_map(true))
		return
	map_dir = ""
	example = false
	_reset(EditorMap.blank("nouvelle_carte", Lang.t("NOUVELLE CARTE", "NEW MAP"), Lang.t("NOUVELLE CARTE", "NEW MAP")))
	set_status(Lang.t("Nouvelle carte : prenez « Pièce rectangle » (touche 2) et glissez dans la grille", "New map: take \"Rectangle room\" (key 2) and drag in the grid"))


func open_dir(dir: String, is_example := false) -> void:
	if refuse_guest():
		return
	var d := EditorMap.load_dir(dir)
	if not d.load_errors.is_empty():
		_info(Lang.t("Ouverture", "Open"), "\n".join(d.load_errors.map(func(e): return Lang.t(e[0], e[1]))))
	map_dir = "" if is_example else dir
	example = is_example
	_reset(d)
	if not is_example:
		_add_recent(dir)
	set_status(Lang.t("Carte « %s » ouverte", "Map \"%s\" opened") % doc.display_name())


func open_example(ex_id: String) -> void:
	open_dir(EditorMap.EXAMPLES[ex_id], true)


## Enregistre (dans son dossier, sinon dans user://maps/<id>/).
func save() -> bool:
	# Invité d'une session : seul l'hôte enregistre la carte.
	if refuse_guest():
		return false
	if map_dir == "" or example:
		var mid := doc.id()
		if example or mid == "nouvelle_carte" or mid == "":
			mid = EditorMap.slug(String(doc.carte.get("nom", {}).get("fr", mid)))
		return save_as(_free_id(mid) if map_dir == "" else mid)
	var err := doc.save_dir(map_dir)
	if err != OK:
		set_status(Lang.t("Échec de l'enregistrement (%s)", "Save failed (%s)") % error_string(err), true)
		return false
	dirty = false
	_drop_recovery()
	_add_recent(map_dir)
	_update_title()
	set_status(Lang.t("Enregistrée dans %s", "Saved to %s") % map_dir)
	collab.notify_saved()
	return true


## Fichier > éléments réservés à l'hôte quand on a rejoint une session
## (Nouvelle, Ouvrir, Enregistrer, Enregistrer sous, Exporter, Importer,
## Cartes récentes) : ouvrir ou enregistrer la carte est l'affaire de l'hôte.
const HOST_ONLY_FILE_IDS := [0, 1, 2, 3, 4, 5, 6]


## Invité d'une session (rejointe, ou en train de la rejoindre).
func is_guest() -> bool:
	return collab != null and collab.role == MapCollab.Role.GUEST


## Invité : refuse l'action (message dans la barre d'état) et rend true.
func refuse_guest() -> bool:
	if not is_guest():
		return false
	set_status(Lang.t("Réservé à l'hôte de la session : seul l'hôte ouvre et enregistre la carte", "Host only: only the session host opens and saves the map"), true)
	return true


## Fichier : éléments réservés à l'hôte grisés (avec une bulle) chez l'invité,
## actifs sinon (appelé à l'ouverture du menu et à chaque changement de session).
func update_file_menu() -> void:
	if file_menu == null:
		return
	var fm := file_menu.get_popup()
	var guest := is_guest()
	for id in HOST_ONLY_FILE_IDS:
		var i := fm.get_item_index(id)
		if i < 0:
			continue
		fm.set_item_disabled(i, guest)
		fm.set_item_tooltip(i, Lang.t("Réservé à l'hôte de la session", "Host only") if guest else "")


func _free_id(base: String) -> String:
	var id := base
	var n := 2
	while EditorMap.is_map_dir(EditorMap.map_dir(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


func save_as(map_id: String) -> bool:
	if refuse_guest():
		return false
	var mid := EditorMap.slug(map_id)
	doc.carte["id"] = mid
	map_dir = EditorMap.map_dir(mid)
	example = false
	return save()


## Fenêtre Enregistrer sous : nom proposé libre (_free_id), sauf la carte
## elle-même ; rendue (tests), null chez un invité.
func save_as_dialog() -> ConfirmationDialog:
	if refuse_guest():
		return null
	var d := ConfirmationDialog.new()
	d.name = "SaveAsDialog"
	d.title = Lang.t("Enregistrer sous", "Save as")
	var box := VBoxContainer.new()
	d.add_child(box)
	var l := Label.new()
	l.text = Lang.t("Nom du dossier (dans %s) :", "Folder name (in %s):") % EditorMap.maps_root()
	box.add_child(l)
	var e := LineEdit.new()
	e.name = "Name"
	var own := map_dir != "" and not example and _same_dir(map_dir, EditorMap.map_dir(doc.id()))
	e.text = doc.id() if own else _free_id(EditorMap.slug(doc.id()) if doc.id() != "" else "carte")
	e.custom_minimum_size = Vector2(360, 0)
	box.add_child(e)
	d.ok_button_text = Lang.t("Enregistrer", "Save")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	d.set_meta("name", e)
	add_child(d)
	d.confirmed.connect(func():
		d.queue_free()
		request_save_as(e.text))
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	e.grab_focus.call_deferred()
	return d


## Enregistrer sous `map_id` : un AUTRE dossier de carte du même nom existe
## déjà : confirmation d'écrasement d'abord (rendue ; null : enregistrée ou
## refusée tout de suite).
func request_save_as(map_id: String) -> ConfirmationDialog:
	var target := EditorMap.map_dir(EditorMap.slug(map_id))
	if target != "" and EditorMap.is_map_dir(target) and not (map_dir != "" and not example and _same_dir(map_dir, target)):
		return _confirm(Lang.t("Enregistrer sous", "Save as"),
			Lang.t("La carte « %s » existe déjà. La remplacer ?", "The map \"%s\" already exists. Replace it?") % target.get_file(),
			func(): save_as(map_id))
	save_as(map_id)
	return null


static func _same_dir(a: String, b: String) -> bool:
	return a != "" and b != "" and EditorMap._abs(a).trim_suffix("/") == EditorMap._abs(b).trim_suffix("/")


## Fenêtre Ouvrir (exemples livrés + cartes du joueur) ; « Supprimer » (ou
## la touche Suppr) efface une carte du joueur après confirmation, jamais un
## exemple. Rend la fenêtre (tests).
func open_dialog() -> ConfirmationDialog:
	if refuse_guest():
		return null
	var d := ConfirmationDialog.new()
	d.name = "OpenDialog"
	d.title = Lang.t("Ouvrir une carte", "Open a map")
	var box := VBoxContainer.new()
	d.add_child(box)
	var list := ItemList.new()
	list.name = "Maps"
	list.custom_minimum_size = Vector2(460, 300)
	box.add_child(list)
	var entries := []
	var hint := Label.new()
	hint.text = Lang.t("Dossier des cartes : %s", "Maps folder: %s") % ProjectSettings.globalize_path(EditorMap.maps_root())
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(hint)
	d.ok_button_text = Lang.t("Ouvrir", "Open")
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	var del := d.add_button(Lang.t("Supprimer", "Delete"), false, "delete")
	d.set_meta("list", list)
	d.set_meta("delete", del)
	add_child(d)
	# Entrées : [dossier, exemple ?, nom affiché].
	var fill := func():
		list.clear()
		entries.clear()
		for ex in EditorMap.EXAMPLES:
			entries.append([EditorMap.EXAMPLES[ex], true, ex.to_upper()])
			list.add_item(Lang.t("Exemple : %s", "Example: %s") % ex.to_upper())
		for m in EditorMap.list_maps():
			entries.append([m.dir, false, String(m.name)])
			list.add_item("%s   (%s)" % [m.name, m.id])
	var update_del := func():
		var sel := list.get_selected_items()
		var own := not sel.is_empty() and not bool(entries[sel[0]][1])
		del.disabled = not own
		del.tooltip_text = "" if own or sel.is_empty() else Lang.t("Les exemples livrés avec le jeu ne peuvent pas être supprimés", "Examples shipped with the game cannot be deleted")
	var ask_delete := func():
		var sel := list.get_selected_items()
		if sel.is_empty() or bool(entries[sel[0]][1]):
			return
		var en: Array = entries[sel[0]]
		var on_ok := func():
			delete_map(String(en[0]))
			if is_instance_valid(list):
				fill.call()
				update_del.call()
		_confirm(Lang.t("Supprimer la carte", "Delete the map"),
			Lang.t("Supprimer définitivement la carte « %s » ?\n(%s)", "Permanently delete the map \"%s\"?\n(%s)") % [String(en[2]), String(en[0]).get_file()],
			on_ok, Callable(), d)
	fill.call()
	update_del.call()
	list.item_selected.connect(func(_i): update_del.call())
	list.gui_input.connect(func(ev):
		if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_DELETE:
			ask_delete.call()
			list.accept_event())
	d.custom_action.connect(func(action):
		if action == "delete":
			ask_delete.call())
	var go := func():
		var sel := list.get_selected_items()
		# Fenêtre Ouvrir (exclusive) cachée AVANT la confirmation (double-clic :
		# deux fenêtres exclusives à la fois sinon).
		d.hide()
		d.queue_free()
		if not sel.is_empty():
			var en: Array = entries[sel[0]]
			# Modifications non enregistrées : confirmation avant de la remplacer.
			confirm_unsaved(Lang.t("ouvrir une autre carte", "open another map"), func(): open_dir(String(en[0]), bool(en[1])))
	d.confirmed.connect(go)
	list.item_activated.connect(func(_i): go.call())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	return d


## Supprime la carte du joueur rangée dans `dir` (EditorMap.delete_map :
## dossier des cartes seulement, jamais un exemple). Carte ouverte ici : elle
## reste à l'écran, sans dossier (le prochain Enregistrer lui en redonne un) ;
## sa copie de récupération est effacée (puis réécrite, sans dossier
## d'origine, au prochain passage : la carte est à enregistrer).
func delete_map(dir: String) -> bool:
	if refuse_guest():
		return false
	var name_shown := dir.get_file()
	if not EditorMap.delete_map(dir):
		set_status(Lang.t("Impossible de supprimer la carte « %s »", "Could not delete the map \"%s\"") % name_shown, true)
		return false
	var gone := EditorMap._abs(dir).trim_suffix("/")
	var auto_src := String(MapUnsaved.read_meta(MapUnsaved.recovery_dir()).get("source", ""))
	if map_dir != "" and EditorMap._abs(map_dir).trim_suffix("/") == gone:
		map_dir = ""
		example = false
		dirty = true
		_drop_recovery()
		_update_title()
		set_status(Lang.t("Carte « %s » supprimée : elle reste ouverte, non enregistrée", "Map \"%s\" deleted: it stays open, not saved") % name_shown)
	else:
		if auto_src != "" and EditorMap._abs(auto_src).trim_suffix("/") == gone and not _recovery_pending:
			_drop_recovery()
		set_status(Lang.t("Carte « %s » supprimée", "Map \"%s\" deleted") % name_shown)
	return true


## Importer / Exporter une archive : explorateur du système (FilePick ; la
## fenêtre de Godot seulement sans dialogue natif). Le chemin choisi (absolu)
## repasse par export_zip / import_zip et leurs contrôles.
func _zip_dialog(save_mode: bool) -> void:
	if refuse_guest():
		return
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()
	var chosen := func(path: String):
		if save_mode:
			export_zip(path)
		else:
			# L'archive remplace la carte ouverte : confirmation avant.
			confirm_unsaved(Lang.t("importer une archive", "import an archive"), func(): import_zip(path))
	_file_dialog = FilePick.pick(self,
		Lang.t("Exporter l'archive", "Export the archive") if save_mode else Lang.t("Importer une archive", "Import an archive"),
		FilePick.Mode.SAVE if save_mode else FilePick.Mode.OPEN,
		PackedStringArray(["*.zip ; " + Lang.t("Archive de carte", "Map archive")]),
		chosen, doc.id() + ".zip" if save_mode else "", "", ui_scale)


func export_zip(path: String) -> bool:
	if refuse_guest():
		return false
	var err := doc.export_zip(path)
	if err != OK:
		set_status(Lang.t("Échec de l'export (%s)", "Export failed (%s)") % error_string(err), true)
		return false
	set_status(Lang.t("Archive exportée : %s", "Archive exported: %s") % path)
	return true


func import_zip(path: String) -> bool:
	if refuse_guest():
		return false
	var d := EditorMap.import_zip(path)
	if not d.load_errors.is_empty() and d.pieces.is_empty():
		_info(Lang.t("Import", "Import"), "\n".join(d.load_errors.map(func(e): return Lang.t(e[0], e[1]))))
		return false
	map_dir = ""
	example = false
	_reset(d)
	dirty = true
	_update_title()
	set_status(Lang.t("Archive importée : enregistrez-la (Ctrl+S) pour la garder", "Archive imported: save it (Ctrl+S) to keep it"))
	return true


# ------------------------------------------------------------------ récents

static func _cfg_path() -> String:
	return EditorMap.maps_root().path_join("_editeur.cfg")


## Réglage mémorisé de l'éditeur (_editeur.cfg, section « editeur »).
## Réglages de l'éditeur lus sans décoder d'objet (SafeConfig : un .cfg piégé
## pourrait sinon exécuter du code) ; fichier vide s'il est absent ou refusé.
static func _load_cfg() -> ConfigFile:
	var cf := SafeConfig.load_file(_cfg_path())
	return cf if cf != null else ConfigFile.new()


static func pref(key: String, default: Variant) -> Variant:
	var v: Variant = _load_cfg().get_value("editeur", key, default)
	return v if typeof(v) == typeof(default) else default


static func set_pref(key: String, value: Variant) -> void:
	var cf := _load_cfg()
	cf.set_value("editeur", key, value)
	DirAccess.make_dir_recursive_absolute(EditorMap.maps_root())
	var err := cf.save(_cfg_path())
	if err != OK:
		push_warning("[MapEditor] préférences non enregistrées (%s)" % error_string(err))


static func recent_maps() -> Array:
	var list: Variant = _load_cfg().get_value("editeur", "recentes", [])
	if not list is Array:
		return []
	return (list as Array).filter(func(d): return d is String and EditorMap.is_map_dir(d))


func _add_recent(dir: String) -> void:
	var list := recent_maps()
	list.erase(dir)
	list.push_front(dir)
	var cf := _load_cfg()
	cf.set_value("editeur", "recentes", list.slice(0, RECENT_MAX))
	DirAccess.make_dir_recursive_absolute(EditorMap.maps_root())
	var err := cf.save(_cfg_path())
	if err != OK:
		push_warning("[MapEditor] préférences non enregistrées (%s)" % error_string(err))


func _fill_recent() -> void:
	_recent_menu.clear()
	for d in recent_maps():
		_recent_menu.add_item(String(d).get_file())
	if _recent_menu.item_count == 0:
		_recent_menu.add_item(Lang.t("(aucune)", "(none)"))
		_recent_menu.set_item_disabled(0, true)


# ------------------------------------------------------------------ non enregistré, récupération

## Modifications à confirmer avant de les perdre : jamais chez un invité (la
## carte de la session est celle de l'hôte, qui l'enregistre).
func needs_save_prompt() -> bool:
	return dirty and not is_guest()


## Avant une action qui remplacerait ou fermerait la carte (`what` : « quitter
## l'éditeur », « ouvrir une autre carte »...) : sans modification non
## enregistrée, `proceed` tout de suite ; sinon la boîte « Enregistrer /
## Quitter sans enregistrer / Annuler » (MapUnsaved.ask), rendue (null sans
## boîte). Enregistrer : `proceed` seulement si l'enregistrement réussit ; une
## carte jamais enregistrée (ou un exemple) ouvre Enregistrer sous et l'action
## n'a pas lieu. Quitter sans enregistrer : copie de récupération effacée.
func confirm_unsaved(what: String, proceed: Callable) -> ConfirmationDialog:
	if not needs_save_prompt():
		proceed.call()
		return null
	var text := Lang.t("La carte « %s » a des modifications non enregistrées.\nLes enregistrer avant de %s ?", "The map \"%s\" has unsaved changes.\nSave them before you %s?") % [doc.display_name(), what]
	# Boîte déjà ouverte (ex. Alt+F4 pendant une autre confirmation) : elle
	# sert à la DERNIÈRE action demandée (texte et rappel remplacés).
	_unsaved_proceed = proceed
	if is_instance_valid(_unsaved_dialog):
		_unsaved_dialog.dialog_text = text
		_unsaved_dialog.grab_focus()
		return _unsaved_dialog
	canvas.cancel()
	views.cancel_drags()
	_unsaved_dialog = MapUnsaved.ask(self, Lang.t("Modifications non enregistrées", "Unsaved changes"), text,
		func(choice: String): _on_unsaved_choice(choice, _unsaved_proceed))
	return _unsaved_dialog


## Boîte « non enregistrée » ouverte (null sinon) : une seule à la fois ;
## `_unsaved_proceed` : l'action qu'elle confirme (la dernière demandée).
var _unsaved_dialog: ConfirmationDialog
var _unsaved_proceed: Callable


func _on_unsaved_choice(choice: String, proceed: Callable) -> void:
	_unsaved_dialog = null
	match choice:
		"save":
			if map_dir == "" or example:
				save_as_dialog()
				set_status(Lang.t("Choisissez un nom, enregistrez, puis recommencez", "Choose a name, save, then try again"))
				return
			if save():
				proceed.call()
		"discard":
			_drop_recovery()
			_recovery_sig = ""
			proceed.call()
		_:
			set_status(Lang.t("Annulé : la carte reste ouverte", "Cancelled: the map stays open"))


## Copie de récupération (MapUnsaved) : écrite s'il y a des modifications non
## enregistrées et du nouveau depuis la dernière ; jamais chez un invité, ni
## tant qu'une copie restée d'un plantage attend sa réponse. Rend vrai si la
## copie est à jour.
func write_recovery() -> bool:
	if _recovery_pending or is_guest() or doc == null or not dirty:
		return false
	var sig := MapUnsaved.signature(doc)
	if sig == _recovery_sig:
		return true
	if MapUnsaved.write_recovery(doc, map_dir, example) != OK:
		push_warning("[MapEditor] copie de récupération non écrite")
		return false
	_recovery_sig = sig
	return true


func _drop_recovery() -> void:
	if _recovery_pending:
		return
	MapUnsaved.drop_recovery()
	_recovery_sig = ""


## Copie de récupération restée d'un plantage ou d'une fermeture forcée :
## « Récupérer » (Entrée ; aussi Échap ou la croix : rien n'est perdu) la
## rouvre, modifiée, avec son dossier d'origine ; « Ignorer » l'efface. Rend
## la boîte (null sans copie).
func offer_recovery() -> ConfirmationDialog:
	var dir := MapUnsaved.pending_dir()
	if dir == "":
		return null
	_recovery_pending = true
	var meta := MapUnsaved.read_meta(dir)
	var nm := String(meta.get("name", "")).left(80)
	var d := ConfirmationDialog.new()
	d.name = "RecoveryDialog"
	d.title = Lang.t("Récupération", "Recovery")
	d.dialog_text = Lang.t("L'éditeur s'est fermé sans enregistrer la carte « %s ».\nUne copie de récupération du %s contient ses modifications non enregistrées.\nLa récupérer ?",
		"The editor closed without saving the map \"%s\".\nA recovery copy from %s holds its unsaved changes.\nRecover it?") % [nm, MapUnsaved.when_text(meta)]
	d.dialog_autowrap = true
	d.min_size = Vector2i(int(EditorUi.px(460.0)), 0)
	d.ok_button_text = Lang.t("Récupérer", "Recover")
	# « Ignorer » efface la copie : bouton à part, jamais Échap ni la croix.
	d.get_cancel_button().visible = false
	d.add_button(Lang.t("Ignorer", "Ignore"), true, "ignore").name = "Ignore"
	add_child(d)
	var state := {"done": false}
	var finish := func(recover: bool) -> void:
		if state.done:
			return
		state.done = true
		d.queue_free()
		_recovery_pending = false
		if recover:
			_resume_recovery(dir)
		else:
			_drop_recovery()
			set_status(Lang.t("Copie de récupération ignorée (effacée)", "Recovery copy ignored (deleted)"))
	d.confirmed.connect(func(): finish.call(true))
	d.canceled.connect(func(): finish.call(true))
	d.custom_action.connect(func(action: StringName):
		if action == &"ignore":
			finish.call(false))
	d.popup_centered()
	d.get_ok_button().grab_focus.call_deferred()
	return d


## Rouvre la copie de récupération `dir` : contenu de la copie, dossier
## d'origine (l'enregistrer y écrit) ; l'étoile compare au fichier d'origine.
## La copie reste sur le disque jusqu'au prochain enregistrement.
func _resume_recovery(dir: String) -> void:
	var meta := MapUnsaved.read_meta(dir)
	var d := EditorMap.load_dir(dir)
	var src := String(meta.get("source", ""))
	var ex := bool(meta.get("example", false))
	# meta.json venu du disque : le dossier d'origine n'est repris que s'il est
	# une carte du dossier des cartes (enfant direct, identifiant admis, pas un
	# dossier interne « _ ») ; sinon la carte revient non enregistrée.
	if not MapUnsaved.source_ok(src):
		src = ""
	map_dir = src
	example = ex
	_reset(d)
	var on_disk := src if src != "" and EditorMap.is_map_dir(src) else ""
	if ex:
		map_dir = ""
	if on_disk != "":
		_saved_sig = MapUnsaved.signature(EditorMap.load_dir(on_disk))
		_dirty_ver = -1
	else:
		dirty = true
	_recovery_sig = ""
	write_recovery()
	_update_title()
	set_status(Lang.t("Travail non enregistré récupéré : enregistrez-le (Ctrl+S) pour le garder", "Unsaved work recovered: save it (Ctrl+S) to keep it"))


## Sortie de l'éditeur sans rien à perdre (enregistré, ou abandonné) : la
## copie de récupération n'a plus lieu d'être.
func _leaving() -> void:
	_flush_prefs()
	if not is_guest():
		_drop_recovery()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_close()


## Fermeture de la fenêtre (croix, Alt+F4) : confirmation s'il y a des
## modifications non enregistrées. Rend la boîte (null : fermeture lancée).
func request_close() -> ConfirmationDialog:
	return confirm_unsaved(Lang.t("quitter l'éditeur", "quit the editor"), func():
		_leaving()
		get_tree().quit())


func _exit_tree() -> void:
	# Hors de l'éditeur (menu, partie de TESTER) : la fenêtre se ferme de nouveau
	# directement.
	get_tree().set_auto_accept_quit(true)


## Disposition des vues et aperçu 3D : réglages en attente écrits avant de partir.
func _flush_prefs() -> void:
	if views != null:
		views.flush_prefs()
	if preview != null:
		preview.flush_prefs()


# ------------------------------------------------------------------ menus

func _on_file_menu(id: int) -> void:
	match id:
		0:
			new_map()
		1:
			open_dialog()
		2:
			save()
		3:
			save_as_dialog()
		4:
			_zip_dialog(true)
		5:
			_zip_dialog(false)
		7:
			quit_to_menu()
		8:
			open_options()


func _on_edit_menu(id: int) -> void:
	match id:
		0:
			undo()
		1:
			redo()
		2:
			copy_selected()
		3:
			paste()
		4:
			rotate_selected()
		5:
			delete_selection()
		6:
			toggle_inventory()
		7:
			views.frame_all()
		8:
			cycle_variant()
		9:
			cut_selected()
		10:
			duplicate_selection()
		11:
			select_all()
		12:
			create_prefab_from_selection()


## Fichier > Retour au menu principal (confirmation s'il y a des modifications
## non enregistrées). Rend la boîte (null : retour lancé).
func quit_to_menu() -> ConfirmationDialog:
	return confirm_unsaved(Lang.t("revenir au menu principal", "go back to the main menu"), func():
		_leaving()
		get_tree().change_scene_to_file(Router.MENU_SCENE))


## TESTER : vérifie, puis lance une partie sur la carte TELLE QU'ELLE EST,
## sans l'enregistrer : une copie de travail (MapUnsaved.test_dir, « perso:_tester »)
## est jouée, le dossier de la carte n'est pas touché ; copie de récupération
## écrite avant. Solo, ou avec tous les participants de la session (hôte,
## CollabPlaytest) ; la fin de partie ramène dans l'éditeur, sur la même
## carte, avec son historique d'annulation et son étoile « non enregistrée ».
func test_map() -> bool:
	if collab.role == MapCollab.Role.GUEST:
		_info(Lang.t("Tester", "Play test"), Lang.t("Seul l'hôte de la session lance le test : vous rejoindrez sa partie automatiquement.\nPour tester seul : quittez la session (la carte reste ici), puis TESTER.",
			"Only the session host starts the play test: you will join their game automatically.\nTo test alone: leave the session (the map stays here), then PLAY TEST."))
		return false
	if CollabPlaytest.current != null:
		set_status(Lang.t("Test déjà en préparation", "Play test already being prepared"), true)
		return false
	validate()
	panels.show_tab("check")
	if not validator.ok():
		_info(Lang.t("Tester", "Play test"), Lang.t("La carte n'est pas jouable : %d erreur(s). Corrigez-les (onglet Vérification, clic sur une erreur pour la voir).",
			"The map is not playable: %d error(s). Fix them (Check tab, click an error to see it).") % validator.errors().size())
		return false
	# Plantage pendant la partie : le travail non enregistré reste récupérable.
	write_recovery()
	# Copie de travail jouée (jamais le dossier de la carte du joueur).
	var tdir := MapUnsaved.test_dir()
	MapUnsaved._remove(tdir)
	var err := doc.save_dir(tdir)
	if err != OK:
		set_status(Lang.t("Test impossible : copie de travail non écrite (%s)", "Cannot play test: working copy not written (%s)") % error_string(err), true)
		return false
	# Même contrôle que le jeu au lancement (EditorMapDef.custom) : une carte
	# refusée là démarrerait sur la carte par défaut sans prévenir.
	var guard := CustomMapGuard.load_local(tdir, false)
	if not guard.ok:
		_info(Lang.t("Tester", "Play test"), Lang.t("La carte est refusée par le contrôle du jeu :\n%s", "The map is refused by the game's check:\n%s")
			% CustomMapGuard.reasons_text(guard.reasons))
		return false
	# Session ouverte (même sans invité pour l'instant) : elle reste ouverte
	# pendant le test, et ceux qui sont là jouent avec l'hôte.
	if collab.role == MapCollab.Role.HOST:
		return CollabPlaytest.host_start(self, tdir)
	Router.return_scene = SCENE
	CrashGuard.context("éditeur de cartes : TESTER « %s »" % doc.display_name(), true)
	# Router.start_solo, avec le refus du lancement pris en compte (on reste
	# alors dans l'éditeur).
	Net.start_solo(Settings.player_name)
	if not Net.start_match(EditorMapDef.CUSTOM_PREFIX + MapUnsaved.TEST_ID):
		Net.leave()
		Router.return_scene = ""
		set_status(Lang.t("Test impossible : la partie n'a pas pu démarrer", "Cannot play test: the game could not start"), true)
		return false
	# La partie se charge (changement de scène différé) : la session part avec elle.
	_keep_for_test()
	return true


## TESTER en solo : la session d'édition (carte, historique d'annulation)
## quitte l'éditeur, qui va disparaître, sans être fermée ; l'éditeur qui
## revient la reprend (_setup_collab). Plus aucun lien vers cet éditeur.
func _keep_for_test() -> void:
	var st := playtest_state()
	for s in collab.get_signal_list():
		for c in collab.get_signal_connection_list(s.name):
			var cb: Callable = c.callable
			var o: Object = cb.get_object()
			if o == null or o == self or (o is Node and is_ancestor_of(o)):
				collab.disconnect(s.name, cb)
	collab.keep_alive = true
	remove_child(collab)
	collab.keep_alive = false
	_test_keep = {"collab": collab, "state": st}


## Session gardée pendant un TESTER en solo, jamais reprise (tests, retour
## ailleurs que dans l'éditeur) : libérée.
static func drop_test_keep() -> void:
	var c: Variant = _test_keep.get("collab")
	_test_keep = {}
	if c is Node and is_instance_valid(c) and not (c as Node).is_inside_tree():
		(c as Node).free()
