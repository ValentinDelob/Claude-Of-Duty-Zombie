class_name Hub2Screen
extends MenuScreen
## Hub v2 (maquettes validées docs/hub_v2, architecture docs/HUB_PLAN.md §9) :
## le cadre commun à tous les écrans du hub.
##
##  - Fond : le fond 3D du menu en direct (MenuBackdrop de MainMenu, couloir
##    et zombie qui marche ; l'habillage du menu titre est masqué :
##    `full_frame`), assombri par le voile de l'écran affiché (Hub2Veil).
##  - Barre du haut (Hub2TopBar) : niveau, XP, onglets LABO · ARSENAL ·
##    INVENTAIRE · CODEX (LB / RB, Q / E, Page préc. / suiv., clic), bouton
##    JOUER (START, P, clic).
##  - Fil d'Ariane des sous-écrans (« ‹ LABO / CONTRATS ») ; B / Échap / clic
##    droit : retour (sous-écran -> parent, onglet -> LABO, JOUER -> écran
##    d'avant, LABO -> menu du hub : REPRENDRE, OPTIONS, DOSSIER DE COMBAT,
##    ÉCRAN TITRE, QUITTER LE JEU).
##  - Barre d'invites (Hub2Prompts) : touches du périphérique utilisé en
##    dernier, aide de l'écran ou du bouton qui a le focus.
##  - Écrans : un Hub2Panel par maquette (SCREENS), construit au premier
##    affichage et gardé en vie.
##
## Ouverture (provisoire, tant que l'ancien hub reste celui du jeu) : réglage
## caché `Settings.hub_v2` ([interface] hub_v2=true dans settings.cfg) ou
## argument `--hub2` : JOUER au menu titre ouvre ce hub (MainMenu.SCREENS.hub2).

## Onglets de la barre du haut, dans l'ordre.
const TABS := ["lab", "arsenal", "inventory", "codex"]
## Écrans : identifiant -> script, onglet allumé dans la barre du haut,
## parent (sous-écran : fil d'Ariane et retour), titre [fr, en].
const SCREENS := {
	"lab": {"script": "res://scripts/ui/hub2/screens/hub2_lab_panel.gd", "tab": "lab", "title": ["LABO", "LAB"]},
	"contracts": {"script": "res://scripts/ui/hub2/screens/hub2_contracts_panel.gd", "tab": "lab", "parent": "lab",
		"title": ["CONTRATS", "CONTRACTS"]},
	"exchanges": {"script": "res://scripts/ui/hub2/screens/hub2_exchanges_panel.gd", "tab": "lab", "parent": "lab",
		"title": ["ÉCHANGES", "EXCHANGES"]},
	"arsenal": {"script": "res://scripts/ui/hub2/screens/hub2_arsenal_panel.gd", "tab": "arsenal", "title": ["ARSENAL", "ARSENAL"]},
	"inventory": {"script": "res://scripts/ui/hub2/screens/hub2_inventory_panel.gd", "tab": "inventory",
		"title": ["INVENTAIRE", "INVENTORY"]},
	"codex": {"script": "res://scripts/ui/hub2/screens/hub2_codex_panel.gd", "tab": "codex", "title": ["CODEX", "CODEX"]},
	"play": {"script": "res://scripts/ui/hub2/screens/hub2_play_panel.gd", "tab": "", "title": ["JOUER", "PLAY"]},
	"recap": {"script": "res://scripts/ui/hub2/screens/hub2_recap_panel.gd", "tab": "", "title": ["RETOUR AU LABO", "BACK AT THE LAB"]},
}

## Écran affiché la dernière fois (retour des options, du dossier de combat).
static var last_screen := "lab"
## Scripts remplacés à l'exécution (tests) : identifiant -> GDScript.
static var _registered: Dictionary = {}

## Le menu titre masque son habillage sous cet écran plein cadre (MainMenu),
## sauf son voile de gauche, présent dans l'image de fond des maquettes.
var full_frame := true
var backdrop_shade := true
var profile: PlayerProfile
var profile_path := ""
var _no_disk := false
## Écran affiché, et écran d'où l'on est venu sur JOUER (retour).
var current_id := ""
var _play_return := "lab"
var panels: Dictionary = {}  # identifiant -> Hub2Panel (construits)

var grade: ColorRect
var veil: Hub2Veil
var pages: Control
var crumb: Hub2Breadcrumb
var top_bar: Hub2TopBar
var prompts: Hub2Prompts
var hub_menu: HubMenu
var _hint := ""

signal screen_changed(id: String)
signal profile_changed


## Remplace (ou rend, `script` null) le script d'un écran (tests).
static func register_panel(id: String, script: GDScript) -> void:
	if script == null:
		_registered.erase(id)
	else:
		_registered[id] = script


static func title_of(id: String) -> String:
	var t: Array = SCREENS.get(id, {}).get("title", [id.to_upper(), id.to_upper()])
	return Lang.t(t[0], t[1])


## Sous-écran (fil d'Ariane, retour au parent).
static func parent_of(id: String) -> String:
	return String(SCREENS.get(id, {}).get("parent", ""))


func is_sub_screen(id: String) -> bool:
	return parent_of(id) != ""


func enter(args := {}) -> void:
	HubContractsView.clear_cache()
	profile_path = String(args.get("profile_path", ""))
	_no_disk = args.get("profile") is PlayerProfile and profile_path == ""
	profile = args.profile if args.get("profile") is PlayerProfile else ProfileStore.load_profile(profile_path)
	var opened := HubContractsView.open_hub(profile)
	if opened.changed and not _no_disk:
		ProfileStore.save_profile(profile, profile_path)
	_build()
	Settings.menu_ui_scale_changed.connect(_on_scale_changed)
	var start := String(args.get("screen", last_screen))
	open(start if SCREENS.has(start) else "lab", false)


func exit() -> void:
	last_screen = current_id if current_id != "recap" else "lab"
	var p := current_panel()
	if p:
		p.hidden()
	if Settings.menu_ui_scale_changed.is_connected(_on_scale_changed):
		Settings.menu_ui_scale_changed.disconnect(_on_scale_changed)


func _build() -> void:
	# Fond : étalonnage du menu titre (sous l'interface), voile de l'écran,
	# puis nouvelle copie de l'écran pour que le verre floute le fond tel
	# qu'il est affiché (étalonné et voilé).
	grade = ColorRect.new()
	grade.name = "Grade"
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://assets/shaders/hub2_backdrop.gdshader")
	grade.material = gm
	add_child(grade)
	veil = Hub2Veil.new()
	add_child(veil)
	add_child(Hub2Style.blur_barrier())
	pages = Control.new()
	pages.name = "Pages"
	pages.set_anchors_preset(Control.PRESET_FULL_RECT)
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pages)
	crumb = Hub2Breadcrumb.new()
	crumb.position = Hub2Style.pxv(Hub2Style.SIDE, Hub2Style.MAIN_TOP_SUB)
	crumb.parent_clicked.connect(back)
	add_child(crumb)
	top_bar = Hub2TopBar.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = Hub2Style.px(Hub2Style.TOP_BAR_H)
	var tabs := []
	for id in TABS:
		tabs.append({"id": id, "label": title_of(id)})
	top_bar.set_tabs(tabs)
	top_bar.show_profile(profile)
	top_bar.tab_clicked.connect(func(id): open(id))
	top_bar.play_clicked.connect(toggle_play)
	add_child(top_bar)
	prompts = Hub2Prompts.new()
	prompts.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompts.offset_top = -Hub2Style.px(Hub2Style.PROMPTS_H)
	prompts.prompt_clicked.connect(_on_prompt_clicked)
	add_child(prompts)
	hub_menu = HubMenu.new(self)
	hub_menu.closed.connect(_on_menu_closed)
	add_child(hub_menu)
	panels.clear()


## Reconstruit tout (taille des menus changée), même écran.
func rebuild() -> void:
	var keep := current_id
	var p := current_panel()
	if p:
		p.hidden()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	current_id = ""
	_build()
	open(keep if keep != "" else "lab", false)


func _on_scale_changed(_v: float) -> void:
	if is_inside_tree():
		rebuild()


func current_panel() -> Hub2Panel:
	return panels.get(current_id)


## Script de l'écran `id` (remplacé par un test, sinon SCREENS).
func panel_script(id: String) -> GDScript:
	if _registered.has(id):
		return _registered[id]
	return load(SCREENS[id].script) as GDScript


## Panneau de l'écran `id`, construit au premier appel.
func panel(id: String) -> Hub2Panel:
	if panels.has(id):
		return panels[id]
	var p: Hub2Panel = panel_script(id).new()
	p.hub = self
	p.screen_id = id
	p.name = "Screen_" + id
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.visible = false
	pages.add_child(p)
	panels[id] = p
	p.build()
	p.built = true
	return p


## Affiche l'écran `id` (onglet, sous-écran, JOUER, récapitulatif).
func open(id: String, sound := true) -> void:
	if not SCREENS.has(id):
		return
	if hub_menu and hub_menu.is_open():
		hub_menu.close()
	if id == current_id:
		return
	var old := current_panel()
	if old:
		old.visible = false
		old.hidden()
	if id == "play" and current_id != "":
		_play_return = current_id
	if sound and current_id != "":
		Audio.play_ui("menu_whoosh", -16.0)
	current_id = id
	last_screen = id
	var p := panel(id)
	p.visible = true
	_apply_frame(p)
	p.shown()
	_hint = ""
	refresh_prompts()
	refresh_badges()
	var f := p.first_focus()
	if f:
		focus_later(f)
	else:
		var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if fo and is_ancestor_of(fo):
			fo.release_focus()
	screen_changed.emit(id)


## Cadre de l'écran `p` : voile, barre du haut (onglet allumé, JOUER),
## fil d'Ariane, invites.
func _apply_frame(p: Hub2Panel) -> void:
	veil.spec = p.veil()
	top_bar.visible = p.shows_top_bar()
	top_bar.set_current(String(SCREENS[p.screen_id].tab), p.screen_id == "play")
	prompts.visible = p.shows_prompts()
	var parent := parent_of(p.screen_id)
	crumb.visible = parent != ""
	if parent != "":
		crumb.parent_label = title_of(parent)
		crumb.title = title_of(p.screen_id)


## Hauteur du fil d'Ariane (px à l'échelle).
func crumb_height() -> float:
	return crumb.get_combined_minimum_size().y if crumb else 0.0


## Onglet précédent (-1) ou suivant (+1), en boucle ; depuis un sous-écran,
## JOUER ou le récapitulatif : à partir de son onglet (LABO par défaut).
func step_tab(dir: int) -> void:
	var tab := String(SCREENS.get(current_id, {}).get("tab", ""))
	if tab == "":
		tab = String(SCREENS.get(_play_return, {}).get("tab", "lab"))
		if tab == "":
			tab = "lab"
	var i := TABS.find(tab)
	open(TABS[posmod(i + dir, TABS.size())])


## JOUER (START, P, clic) ; de nouveau sur JOUER : retour à l'écran d'avant.
func toggle_play() -> void:
	if current_id == "play":
		open(_play_return if _play_return != "play" else "lab")
	else:
		open("play")


func refresh_prompts() -> void:
	var p := current_panel()
	prompts.set_items(p.prompts() if p else [])
	_show_help()


## Pastilles jaunes des onglets (Hub2Panel.badge des écrans construits ;
## sous-écrans : sur l'onglet de leur parent).
func refresh_badges() -> void:
	var on := {}
	for id in panels:
		var tab := String(SCREENS[id].tab)
		if tab != "" and (panels[id] as Hub2Panel).badge():
			on[tab] = true
	# Onglet dont l'écran n'est pas encore construit : fonction statique
	# facultative `tab_badge(profile)` de son script.
	for id in TABS:
		if not panels.has(id) and not on.get(id, false):
			var s := panel_script(id)
			for m in s.get_script_method_list():
				if m.name == "tab_badge":
					on[id] = bool(s.call("tab_badge", profile))
					break
	for id in TABS:
		top_bar.set_badge(id, on.get(id, false))


## Aide de l'élément qui a le focus (MainMenu.set_hint, boutons) ; "" :
## celle de l'écran.
func set_hint(t: String) -> void:
	_hint = t
	_show_help()


func show_hint(t: String) -> void:
	set_hint(t)


func _show_help() -> void:
	if prompts == null:
		return
	var p := current_panel()
	prompts.help = _hint if _hint != "" else (p.help() if p else "")


# --------------------------------------------------------------------------
# Profil
# --------------------------------------------------------------------------

func reload_profile() -> void:
	if not _no_disk:
		profile = ProfileStore.load_profile(profile_path)
	_profile_updated()


func save_profile() -> Error:
	var err := OK if _no_disk else ProfileStore.save_profile(profile, profile_path)
	_profile_updated()
	return err


func _profile_updated() -> void:
	top_bar.show_profile(profile)
	for p in panels.values():
		p.refresh()
	refresh_badges()
	profile_changed.emit()


# --------------------------------------------------------------------------
# Menu du hub (provisoire : celui de l'ancien hub, sans maquette v2)
# --------------------------------------------------------------------------

func open_menu() -> void:
	if hub_menu.is_open():
		return
	Audio.play_ui(MenuStyle.SND_SELECT, -8.0)
	hub_menu.open()
	prompts.set_items([[Hub2Input.ACCEPT, Lang.t("Choisir", "Select")], [Hub2Input.BACK, Lang.t("Reprendre", "Resume")]])


func close_menu() -> void:
	hub_menu.close()


func _on_menu_closed() -> void:
	refresh_prompts()
	set_hint("")
	var p := current_panel()
	var f := p.first_focus() if p else null
	if f:
		focus_later(f)


## OPTIONS, DOSSIER DE COMBAT (menu du hub) : leur RETOUR revient ici.
func open_screen(screen_name: String) -> void:
	last_screen = current_id
	menu.show_screen(screen_name)


func to_title() -> void:
	last_screen = "lab"
	if Net.is_online() or Net.mode == Net.Mode.CLIENT:
		Net.leave()
		GameState.reset_to_menu()
		Router.lobby_message = ""
	menu.show_screen("main", {}, false)


func quit_game() -> void:
	menu.fade_to_black(0.6, Router.quit_game)


# --------------------------------------------------------------------------
# Retour et entrées
# --------------------------------------------------------------------------

## B / Échap (via MainMenu), clic droit, « ‹ LABO » : le menu du hub se
## ferme, sinon l'écran consomme (fiche), sinon on remonte d'un cran.
func back() -> void:
	if hub_menu.is_open():
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		hub_menu.close()
		return
	var p := current_panel()
	if p and p.back():
		return
	var parent := parent_of(current_id)
	if parent != "":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		open(parent, false)
	elif current_id == "play":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		toggle_play()
	elif current_id != "lab":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		open("lab", false)
	else:
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
	handle_event(event)


## Navigation du hub pour `event` (aussi appelée par les tests) ; vrai si
## consommé.
func handle_event(event: InputEvent) -> bool:
	if hub_menu.is_open():
		if event is InputEventJoypadButton and Hub2Input.is_play(event):
			_handled()
			hub_menu.close()
			return true
		return false
	var p := current_panel()
	if p and p.handle_input(event):
		_handled()
		return true
	if _typing():
		return false
	if Hub2Input.is_play(event):
		_handled()
		toggle_play()
		return true
	var step := Hub2Input.tab_step(event)
	if step != 0:
		_handled()
		step_tab(step)
		return true
	return false


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _on_prompt_clicked(id: String) -> void:
	match id:
		Hub2Input.TABS:
			step_tab(1)
		Hub2Input.PLAY:
			toggle_play()
		Hub2Input.BACK:
			back()
		Hub2Input.ACCEPT:
			var f := get_viewport().gui_get_focus_owner()
			if f is BaseButton and is_ancestor_of(f) and not (f as BaseButton).disabled:
				(f as BaseButton).pressed.emit()
		_:
			var p := current_panel()
			if p:
				p.on_prompt(id)
