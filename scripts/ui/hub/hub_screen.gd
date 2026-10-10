class_name HubScreen
extends MenuScreen
## HUB du scientifique (docs/HUB_PLAN.md, maquette docs/hub_mockup/index.html,
## écran 1) : écran de menu à sept onglets à plat entre deux parties — LABO,
## ARSENAL, PIÈCES, CONTRATS, ÉCHANGES, DÉPART, PARTIE. Ouvert par JOUER au
## menu titre (MainMenu.SCREENS.hub).
##
## Cadre commun : barre du haut (niveau, XP, touche du menu), barre des
## onglets (Q / E, Page préc. / suiv., LB / RB, clic), zone centrale (panneau
## de l'onglet, HubPanel), barre d'invites (touches du périphérique utilisé en
## dernier, aide de l'élément qui a le focus). Échap / B / clic droit : retour
## (le panneau ferme sa fiche, sinon le menu du hub s'ouvre) ; Start : menu du
## hub (HubMenu : REPRENDRE, OPTIONS, DOSSIER DE COMBAT, ÉCRAN TITRE, QUITTER
## LE JEU).
##
## PANNEAUX : un par onglet, indépendants (HUB_PLAN §3.9), tous construits à
## l'ouverture et gardés en vie (le salon de l'onglet PARTIE reste connecté
## d'un onglet à l'autre, D4). Un onglet sans script enregistré affiche un
## panneau « à venir » (HubPlaceholderPanel). Pour brancher un panneau (lots
## C, D, E) : une ligne dans PANELS, voir l'API de HubPanel.
##
## FOND : un seul point, `backdrop` (HUB_PLAN §3.9) : aujourd'hui le fond 3D
## du menu assombri, quadrillé ; plus tard la scène du laboratoire.
##
## TAILLE DES MENUS (Settings.menu_ui_scale) : tout est construit avec
## HubStyle.px / fs ; un changement reconstruit l'écran (rebuild).

## Onglets, dans l'ordre (identifiants stables : profil, tests, lots C à E).
const TABS := ["lab", "arsenal", "parts", "contracts", "exchanges", "loadout", "play"]
const TAB_NAMES := {
	"lab": ["LABO", "LAB"], "arsenal": ["ARSENAL", "ARSENAL"], "parts": ["PIÈCES", "PARTS"],
	"contracts": ["CONTRATS", "CONTRACTS"], "exchanges": ["ÉCHANGES", "EXCHANGES"],
	"loadout": ["DÉPART", "LOADOUT"], "play": ["PARTIE", "PLAY"],
}
## Script du panneau de chaque onglet (HubPanel). Onglet absent : panneau
## provisoire « à venir ». Les lots C (arsenal, parts, loadout), D
## (contracts, exchanges) et E (play) ajoutent leur ligne ici.
const PANELS := {
	"lab": "res://scripts/ui/hub/lab_panel.gd",
	# Provisoire jusqu'au lot E : SOLO / COOP par les écrans actuels.
	"play": "res://scripts/ui/hub/hub_play_stub_panel.gd",
}
## Hauteur de la zone centrale à 100 % (720 − 100 − 12 − 16 − 36).
const CONTENT_SIZE := Vector2(1248, 556)

## Panneaux enregistrés à l'exécution (tests) : identifiant -> GDScript.
static var _registered: Dictionary = {}
## Onglet affiché la dernière fois (retour des options, du dossier de combat).
static var last_tab := "lab"

## Le menu titre masque son habillage (caméra de surveillance, voile) et
## calme son post-traitement sous cet écran plein cadre (MainMenu).
var full_frame := true
var profile: PlayerProfile
var tab := ""
var panels: Dictionary = {}  # identifiant -> HubPanel
var backdrop: Control
var top_bar: HubTopBar
var tab_bar: HubTabBar
var prompts: HubPrompts
var content: Control
var hub_menu: HubMenu
var _root: VBoxContainer

signal tab_changed(id: String)
signal profile_changed


## Enregistre (ou remplace) le panneau d'un onglet à l'exécution ; `script`
## null : retire l'enregistrement.
static func register_panel(id: String, script: GDScript) -> void:
	if script == null:
		_registered.erase(id)
	else:
		_registered[id] = script


## Script du panneau de l'onglet `id` (enregistré, sinon PANELS, sinon le
## panneau provisoire).
static func panel_script(id: String) -> GDScript:
	if _registered.has(id):
		return _registered[id]
	if PANELS.has(id):
		var s := load(PANELS[id]) as GDScript
		if s:
			return s
	return HubPlaceholderPanel


static func tab_label(id: String) -> String:
	var n: Array = TAB_NAMES.get(id, [id.to_upper(), id.to_upper()])
	return Lang.t(n[0], n[1])


func enter(args := {}) -> void:
	HubContractsView.clear_cache()
	# `args.profile` : profil fourni (tests), sinon celui du joueur.
	profile = args.profile if args.get("profile") is PlayerProfile else ProfileStore.load_profile()
	var start: String = args.get("tab", last_tab)
	_build()
	Settings.menu_ui_scale_changed.connect(_on_scale_changed)
	select_tab(start if start in TABS else "lab", false)


func exit() -> void:
	last_tab = tab
	if Settings.menu_ui_scale_changed.is_connected(_on_scale_changed):
		Settings.menu_ui_scale_changed.disconnect(_on_scale_changed)


func _build() -> void:
	backdrop = HubBackdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 0)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	top_bar = HubTopBar.new()
	top_bar.show_profile(profile)
	top_bar.menu_clicked.connect(open_menu)
	_root.add_child(top_bar)
	tab_bar = HubTabBar.new()
	var names := PackedStringArray()
	for id in TABS:
		names.append(tab_label(id))
	tab_bar.labels = names
	tab_bar.tab_clicked.connect(func(i): select_tab(TABS[i]))
	tab_bar.step_clicked.connect(step_tab)
	_root.add_child(tab_bar)
	var margin := HubBox.pad(Control.new(), 16, 12, 16, 16)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(margin)
	content = margin.get_child(0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompts = HubPrompts.new()
	prompts.prompt_clicked.connect(_on_prompt_clicked)
	_root.add_child(prompts)
	panels.clear()
	for id in TABS:
		var p: HubPanel = panel_script(id).new()
		p.hub = self
		p.tab_id = id
		p.name = "Panel_" + id
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		content.add_child(p)
		panels[id] = p
		p.build()
	hub_menu = HubMenu.new(self)
	hub_menu.closed.connect(_on_menu_closed)
	add_child(hub_menu)
	refresh_badges()


## Reconstruit tout l'écran (taille des menus changée), même onglet.
func rebuild() -> void:
	var keep := tab
	for c in get_children():
		remove_child(c)
		c.queue_free()
	tab = ""
	_build()
	select_tab(keep if keep != "" else "lab", false)


func _on_scale_changed(_v: float) -> void:
	if is_inside_tree():
		rebuild()


## Panneau de l'onglet affiché.
func current_panel() -> HubPanel:
	return panels.get(tab)


## Affiche l'onglet `id` ; le focus va au premier élément utile du panneau.
func select_tab(id: String, sound := true) -> void:
	if not id in TABS or not panels.has(id):
		return
	if hub_menu and hub_menu.is_open():
		hub_menu.close()
	var old: HubPanel = panels.get(tab)
	if old and id != tab:
		old.visible = false
		old.hidden()
	if sound and id != tab:
		Audio.play_ui("menu_whoosh", -16.0)
	tab = id
	last_tab = id
	tab_bar.current = TABS.find(id)
	var p: HubPanel = panels[id]
	p.visible = true
	p.shown()
	set_hint("")
	refresh_prompts()
	var f := p.first_focus()
	if f:
		focus_later(f)
	tab_changed.emit(id)


## Onglet précédent (-1) ou suivant (+1), en boucle.
func step_tab(dir: int) -> void:
	var i := TABS.find(tab)
	select_tab(TABS[posmod(i + dir, TABS.size())])


func refresh_prompts() -> void:
	var p := current_panel()
	prompts.set_items(p.prompts() if p else [])


## Pastilles des onglets (HubPanel.badge ; onglet CONTRATS provisoire : nombre
## de contrats prêts à remettre, comme la maquette).
func refresh_badges() -> void:
	for i in TABS.size():
		var id: String = TABS[i]
		var p: HubPanel = panels.get(id)
		var n := p.badge() if p else 0
		if id == "contracts" and (p == null or p is HubPlaceholderPanel):
			n = HubContractsView.ready_count(profile)
		tab_bar.set_badge(i, n)


## Texte d'aide (barre d'invites, à droite) ; MainMenu.set_hint arrive ici.
func set_hint(t: String) -> void:
	if prompts:
		prompts.hint = t


## Appelé par MainMenu.set_hint (MenuScreen.button, écrans hôtes).
func show_hint(t: String) -> void:
	set_hint(t)


# --------------------------------------------------------------------------
# Profil
# --------------------------------------------------------------------------

## Relit le profil du disque et rafraîchit tout.
func reload_profile() -> void:
	profile = ProfileStore.load_profile()
	_profile_updated()


## Enregistre le profil (une écriture par action, HUB_PLAN §5.2) et
## rafraîchit tout.
func save_profile() -> Error:
	var err := ProfileStore.save_profile(profile)
	_profile_updated()
	return err


func _profile_updated() -> void:
	top_bar.show_profile(profile)
	for p in panels.values():
		p.refresh()
	refresh_badges()
	profile_changed.emit()


# --------------------------------------------------------------------------
# Menu du hub, retour, entrées
# --------------------------------------------------------------------------

func open_menu() -> void:
	if hub_menu.is_open():
		return
	Audio.play_ui(MenuStyle.SND_SELECT, -8.0)
	hub_menu.open()
	prompts.set_items([[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")], [HubPrompts.BACK, Lang.t("Reprendre", "Resume")]])


func close_menu() -> void:
	hub_menu.close()


func _on_menu_closed() -> void:
	refresh_prompts()
	set_hint("")
	var p := current_panel()
	var f := p.first_focus() if p else null
	if f:
		focus_later(f)


## Écran du menu principal ouvert depuis le menu du hub (OPTIONS, DOSSIER DE
## COMBAT) : son RETOUR revient au hub, même onglet.
func open_screen(screen_name: String) -> void:
	last_tab = tab
	menu.show_screen(screen_name)


func to_title() -> void:
	last_tab = "lab"
	menu.show_screen("main", {}, false)


func quit_game() -> void:
	menu.fade_to_black(0.6, Router.quit_game)


## Échap / B (via MainMenu) et clic droit : le menu du hub se ferme, sinon le
## panneau ferme sa fiche, sinon le menu du hub s'ouvre.
func back() -> void:
	if hub_menu.is_open():
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		hub_menu.close()
		return
	var p := current_panel()
	if p and p.back():
		return
	open_menu()


func _active() -> bool:
	return is_visible_in_tree() and menu != null and menu.current == self and modulate.a > 0.05


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _input(event: InputEvent) -> void:
	# Clic droit : retour (avant les contrôles, qui avalent les clics).
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and _active():
		get_viewport().set_input_as_handled()
		back()


func _unhandled_input(event: InputEvent) -> void:
	if not _active():
		return
	# Start (manette) : menu du hub. Échap passe par ui_cancel (MainMenu -> back).
	if event is InputEventJoypadButton and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if hub_menu.is_open():
			hub_menu.close()
		else:
			open_menu()
		return
	if hub_menu.is_open():
		return
	if event.is_action_pressed("ui_page_up") or _key(event, KEY_Q):
		get_viewport().set_input_as_handled()
		step_tab(-1)
	elif event.is_action_pressed("ui_page_down") or _key(event, KEY_E):
		get_viewport().set_input_as_handled()
		step_tab(1)
	else:
		var p := current_panel()
		if p and p.handle_input(event):
			get_viewport().set_input_as_handled()


func _key(event: InputEvent, physical: int) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.physical_keycode == physical \
		and not k.ctrl_pressed and not k.alt_pressed and not _typing()


func _on_prompt_clicked(id: String) -> void:
	match id:
		HubPrompts.TABS:
			step_tab(1)
		HubPrompts.MENU:
			open_menu()
		HubPrompts.BACK:
			back()
		HubPrompts.ACCEPT:
			var f := get_viewport().gui_get_focus_owner()
			if f is BaseButton and is_ancestor_of(f) and not (f as BaseButton).disabled:
				(f as BaseButton).pressed.emit()
		_:
			# Action propre au panneau : comme sa touche.
			var p := current_panel()
			if p and p.has_method("on_prompt"):
				p.call("on_prompt", id)


## Fond du hub (classe .frame de la maquette) : fond sombre quadrillé (pas de
## 40 px), halo vert du labo au centre, posé sur le fond 3D du menu qui reste
## à peine visible. Plus tard : la scène du laboratoire (HUB_PLAN §3.9).
class HubBackdrop extends Control:
	var _halo: GradientTexture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Gradient.new()
		g.set_color(0, Color(69 / 255.0, 115 / 255.0, 102 / 255.0, 0.18))
		g.set_color(1, Color(0, 0, 0, 0.55))
		g.set_offset(1, 0.75)
		_halo = GradientTexture2D.new()
		_halo.gradient = g
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.4)
		_halo.fill_to = Vector2(1.05, 0.95)
		_halo.width = 256
		_halo.height = 144
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(HubStyle.FRAME_BG, 0.93))
		var step := 40.0
		var lc := Color(143 / 255.0, 173 / 255.0, 158 / 255.0, 0.045)
		var x := 0.0
		while x < r.size.x:
			draw_rect(Rect2(x, 0, 2, r.size.y), lc)
			x += step
		var y := 0.0
		while y < r.size.y:
			draw_rect(Rect2(0, y, r.size.x, 2), lc)
			y += step
		draw_texture_rect(_halo, r, false)
