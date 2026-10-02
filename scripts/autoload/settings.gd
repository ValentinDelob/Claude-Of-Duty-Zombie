extends Node
## Settings — options persistantes (user://settings.cfg) et actions d'entrée.

const PATH := "user://settings.cfg"
## Fichier utilisé : les tests automatisés écrivent ailleurs pour ne jamais
## écraser les réglages du joueur (et partent des valeurs par défaut), un
## fichier par processus (check.sh lance les scénarios en parallèle), effacé à
## la sortie.
const TEST_PATH_PREFIX := "user://settings_autotest_"
var path := PATH

enum Quality { LOW, MEDIUM, HIGH }

signal changed
## Les touches d'une action ont changé (OPTIONS > COMMANDES).
signal bindings_changed

var player_name := "Claude"
## Personnage incarné (OPTIONS > JEU > PERSONNAGE) : « auto » (personnage
## libre tiré par l'hôte, comme BO1) ou un identifiant de CharacterDB.IDS.
## Pris en compte au lancement de la partie suivante.
var character := CharacterDB.AUTO
var mouse_sensitivity := 0.25
## Multiplicateur de la sensibilité en visée (1 = celle de l'arme, comme BO1).
var ads_sensitivity := 1.0
const ADS_SENSITIVITY_RANGE := Vector2(0.3, 2.0)
var invert_y := false
var fov := 80.0
var master_volume := 0.9
var music_volume := 0.7
var sfx_volume := 0.9
## Volume des répliques des personnages (bus « Voice »).
var voice_volume := 1.0
var fullscreen := false
var vsync := true
var quality: Quality = Quality.MEDIUM
## Intensité du grain de film en jeu (0 = désactivé, 1 = maximum).
var film_grain := 0.5
## Échelle de la résolution 3D (1 = 100 %), multipliée par celle du préréglage
## de qualité (RenderQuality : 85 % en BASSE). L'interface reste nette.
var render_scale := 1.0
const RENDER_SCALE_RANGE := Vector2(0.5, 1.0)
## Limite d'images par seconde (0 = illimitée).
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]
var max_fps := 0
## Luminosité (gamma de sortie, comme le réglage de BO1) : 1 = neutre,
## < 1 plus sombre, > 1 plus clair. Appliquée par la table d'étalonnage de la
## carte (WorldLook.grade_lut, via RenderQuality).
var brightness := 1.0
const BRIGHTNESS_RANGE := Vector2(0.5, 1.5)
## Taille de l'interface de l'éditeur de cartes (OPTIONS > JEU > INTERFACE, ou
## Ctrl + / Ctrl - / Ctrl 0 dans l'éditeur) : un seul facteur appliqué à tout
## l'éditeur (EditorUi). 80 % par défaut : l'ancienne taille (100 %) était
## jugée trop grosse. Bornée et arrondie au pas de 5 % (clamp_editor_ui_scale).
const EDITOR_UI_SCALE_RANGE := Vector2(0.6, 1.5)
const EDITOR_UI_SCALE_STEP := 0.05
const EDITOR_UI_SCALE_DEFAULT := 0.8
## La taille de l'interface de l'éditeur a changé (appliquée en direct).
signal editor_ui_scale_changed(value: float)
var editor_ui_scale := EDITOR_UI_SCALE_DEFAULT:
	set(v):
		var c := clamp_editor_ui_scale(v)
		if not is_equal_approx(c, editor_ui_scale):
			editor_ui_scale = c
			editor_ui_scale_changed.emit(c)
## Langue de l'interface (écran d'options, menu pause), des voix des
## personnages et de leurs répliques (« fr » ou « en », voir Lang.t).
## Sans fichier de réglages : celle du système si c'est le français, sinon l'anglais.
const LANGUAGES := ["fr", "en"]
var language := "fr"
var last_ip := "127.0.0.1"
var last_port := 7777
## Dernière carte choisie (sélection solo, salon de l'hôte).
var last_map := "bunker_k7"
## Préréglage automatique (QualityProbe) : compte rendu de la détection faite
## au premier lancement ("" : pas faite). Elle ne se refait jamais ensuite.
var quality_auto := ""
var _needs_probe := false
var _probe: QualityProbe
## Limite d'images imposée par la ligne de commande (--max-fps, tests) : elle
## l'emporte sur l'option.
var _cmdline_max_fps := 0

## Actions -> touches par défaut (clavier AZERTY et QWERTY : on mappe par
## keycode physique pour que ZQSD/WASD tombe au même endroit).
const DEFAULT_BINDINGS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_F, KEY_E],
	"reload": [KEY_R],
	"melee": [KEY_V],
	"grenade": [KEY_G],
	"tactical": [KEY_Q],
	"switch_weapon": [KEY_1, KEY_2],
	"scoreboard": [KEY_TAB],
	"pause": [KEY_ESCAPE],
}
const MOUSE_BINDINGS := {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
}

## Actions réaffectables, dans l'ordre de l'écran OPTIONS > COMMANDES.
## « pause » (Échap) reste fixe : c'est aussi la touche qui annule une
## réaffectation. La molette change toujours d'arme, en plus des touches.
const REBINDABLE := ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch",
	"sprint", "fire", "aim", "reload", "interact", "melee", "grenade", "tactical",
	"switch_weapon", "scoreboard"]
## Touches par action (deux cases, comme les options de BO1 sur PC).
const MAX_KEYS := 2
## Boutons de souris acceptés en réaffectation (la molette est exclue).
const BINDABLE_MOUSE := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
	MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]

## Touches courantes : action -> codes (« key:<physical_keycode> »,
## « mouse:<bouton> »). Voir bind(), reset_bindings(), apply_bindings().
var bindings := {}


## Taille de l'interface de l'éditeur ramenée dans la plage et au pas de 5 %
## (valeur non finie : taille par défaut).
static func clamp_editor_ui_scale(v: float) -> float:
	if not is_finite(v):
		return EDITOR_UI_SCALE_DEFAULT
	return clampf(snappedf(v, EDITOR_UI_SCALE_STEP), EDITOR_UI_SCALE_RANGE.x, EDITOR_UI_SCALE_RANGE.y)


func _ready() -> void:
	_cmdline_max_fps = Engine.max_fps
	_register_inputs()
	load_settings()
	_apply_cmdline_quality()
	apply_bindings()
	apply()
	# Premier lancement : préréglage choisi d'après la carte graphique et un
	# mini-banc d'essai dans le menu (jamais en autotest ni si --quality=).
	if _needs_probe and path == PATH and not _cmdline_has_prefix("--quality=") and DisplayServer.get_name() != "headless":
		start_quality_probe()


## Détection du préréglage (QualityProbe) ; le résultat est appliqué puis
## enregistré. Appelée au premier lancement (et par le scénario quality_probe).
func start_quality_probe() -> QualityProbe:
	if _probe:
		return _probe
	_probe = QualityProbe.new()
	_probe.name = "QualityProbe"
	_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_probe)
	_probe.done.connect(func(q: int, info: String):
		quality = q as Quality
		quality_auto = info
		_needs_probe = false
		save_settings()
		changed.emit()
		_probe.queue_free()
		_probe = null)
	_probe.run.call_deferred()
	return _probe


## `--quality=low|medium|high` impose la qualité graphique (tests de perf).
func _apply_cmdline_quality() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			var q := Quality.keys().find(a.substr(10).to_upper())
			if q >= 0:
				quality = q as Quality


func _register_inputs() -> void:
	for action in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for action in MOUSE_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	# Échap : menu pause (fixe).
	InputMap.action_erase_events("pause")
	for key in DEFAULT_BINDINGS.pause:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event("pause", ev)
	bindings = default_bindings()
	# Navigation des menus à la manette/clavier : on garde les ui_* par défaut.


# --------------------------------------------------------------------------
# Touches (réaffectation)
# --------------------------------------------------------------------------

static func key_code(physical_keycode: int) -> String:
	return "key:%d" % physical_keycode


static func mouse_code(button: int) -> String:
	return "mouse:%d" % button


## Touches d'origine de chaque action réaffectable.
static func default_bindings() -> Dictionary:
	var d := {}
	for action in REBINDABLE:
		var list := []
		if MOUSE_BINDINGS.has(action):
			list.append(mouse_code(MOUSE_BINDINGS[action]))
		for key in DEFAULT_BINDINGS.get(action, []):
			list.append(key_code(key))
		d[action] = list
	return d


## Code d'une touche ou d'un bouton de souris (« » si non réaffectable :
## Échap, molette...).
static func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var pk := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
		if pk == KEY_NONE or pk == KEY_ESCAPE:
			return ""
		return key_code(pk)
	if ev is InputEventMouseButton:
		var b := int((ev as InputEventMouseButton).button_index)
		return mouse_code(b) if b in BINDABLE_MOUSE else ""
	return ""


## Événement d'entrée (pour l'InputMap) d'un code, null s'il est invalide.
static func event_from_code(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var v := parts[1].to_int()
	match parts[0]:
		"key":
			if v <= 0 or v == KEY_ESCAPE:
				return null
			var ev := InputEventKey.new()
			ev.physical_keycode = v as Key
			return ev
		"mouse":
			if not v in BINDABLE_MOUSE:
				return null
			var mb := InputEventMouseButton.new()
			mb.button_index = v as MouseButton
			return mb
	return null


## Noms français / anglais des touches spéciales.
const KEY_NAMES := {
	KEY_SPACE: ["ESPACE", "SPACE"],
	KEY_SHIFT: ["MAJ", "SHIFT"],
	KEY_CTRL: ["CTRL", "CTRL"],
	KEY_ALT: ["ALT", "ALT"],
	KEY_TAB: ["TAB", "TAB"],
	KEY_ENTER: ["ENTRÉE", "ENTER"],
	KEY_KP_ENTER: ["ENTRÉE (PAVÉ)", "KEYPAD ENTER"],
	KEY_BACKSPACE: ["RETOUR ARRIÈRE", "BACKSPACE"],
	KEY_DELETE: ["SUPPR", "DELETE"],
	KEY_INSERT: ["INSER", "INSERT"],
	KEY_CAPSLOCK: ["VERR. MAJ", "CAPS LOCK"],
	KEY_UP: ["HAUT", "UP"],
	KEY_DOWN: ["BAS", "DOWN"],
	KEY_LEFT: ["GAUCHE", "LEFT"],
	KEY_RIGHT: ["DROITE", "RIGHT"],
	KEY_PAGEUP: ["PAGE PRÉC.", "PAGE UP"],
	KEY_PAGEDOWN: ["PAGE SUIV.", "PAGE DOWN"],
	KEY_HOME: ["DÉBUT", "HOME"],
	KEY_END: ["FIN", "END"],
}


## Nom affiché d'un code (touche selon la disposition du clavier : la touche
## physique W s'affiche Z en AZERTY).
static func code_label(code: String) -> String:
	var ev := event_from_code(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return Lang.t("CLIC GAUCHE", "LEFT CLICK")
			MOUSE_BUTTON_RIGHT: return Lang.t("CLIC DROIT", "RIGHT CLICK")
			MOUSE_BUTTON_MIDDLE: return Lang.t("CLIC MOLETTE", "MIDDLE CLICK")
			MOUSE_BUTTON_XBUTTON1: return Lang.t("SOURIS 4", "MOUSE 4")
			MOUSE_BUTTON_XBUTTON2: return Lang.t("SOURIS 5", "MOUSE 5")
	if ev is InputEventKey:
		var pk := (ev as InputEventKey).physical_keycode
		if KEY_NAMES.has(pk):
			return Lang.t(KEY_NAMES[pk][0], KEY_NAMES[pk][1])
		var k := pk
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_keycode_from_physical(pk)
			if local != KEY_NONE:
				k = local
		return OS.get_keycode_string(k).to_upper()
	return "—"


## Nom de la première touche d'une action (invites du HUD : « Appuyer sur F »).
func action_label(action: String) -> String:
	var list: Array = bindings.get(action, [])
	return code_label(list[0]) if not list.is_empty() else "?"


## Affecte `code` à la case `slot` de `action`. La touche est retirée de toute
## autre action (conflit) ; déjà dans l'autre case de la même action, les deux
## cases sont échangées. Retourne l'action qui l'a perdue (« » sinon).
func bind(action: String, slot: int, code: String) -> String:
	if not action in REBINDABLE or event_from_code(code) == null:
		return ""
	var taken := ""
	for a in REBINDABLE:
		if a != action and code in bindings[a]:
			(bindings[a] as Array).erase(code)
			taken = a
	var list: Array = bindings[action]
	slot = clampi(slot, 0, MAX_KEYS - 1)
	var idx := list.find(code)
	if idx < 0:
		if slot < list.size():
			list[slot] = code
		else:
			list.append(code)
	elif idx != slot and slot < list.size():
		list[idx] = list[slot]
		list[slot] = code
	apply_bindings()
	return taken


## Vide la case `slot` de `action` (la touche suivante remonte).
func clear_binding(action: String, slot: int) -> void:
	var list: Array = bindings.get(action, [])
	if slot >= 0 and slot < list.size():
		list.remove_at(slot)
		apply_bindings()


func reset_bindings() -> void:
	bindings = default_bindings()
	apply_bindings()


## Reconstruit l'InputMap des actions réaffectables d'après `bindings`.
func apply_bindings() -> void:
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for code in bindings.get(action, []):
			var ev := event_from_code(code)
			if ev:
				InputMap.action_add_event(action, ev)
	# Molette : changement d'arme (fixe).
	for dir in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var w := InputEventMouseButton.new()
		w.button_index = dir
		InputMap.action_add_event("switch_weapon", w)
	bindings_changed.emit()


## Touches lues d'un fichier : codes valides, sans doublon, deux au plus ;
## action absente du fichier (nouvelle version) : ses touches d'origine, sauf
## celles déjà prises par une autre action.
func _bindings_from_cfg(cfg: ConfigFile) -> Dictionary:
	var d := default_bindings()
	var used := {}
	for action in REBINDABLE:
		if not cfg.has_section_key("bindings", action):
			continue
		var raw: Variant = cfg.get_value("bindings", action, [])
		var list := []
		if raw is Array or raw is PackedStringArray:
			for c in raw:
				var code := str(c)
				if event_from_code(code) != null and not used.has(code) and list.size() < MAX_KEYS:
					list.append(code)
					used[code] = true
		d[action] = list
	for action in REBINDABLE:
		if not cfg.has_section_key("bindings", action):
			var keep := []
			for code in d[action]:
				if not used.has(code):
					keep.append(code)
					used[code] = true
			d[action] = keep
	return d


func _exit_tree() -> void:
	if path.begins_with(TEST_PATH_PREFIX) and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Tests en série (Autotest._reset_between) : toutes les options publiques
## reprennent leur valeur par défaut, comme dans un processus neuf (lues sur
## une instance vierge de ce script : aucune liste à tenir à jour), le
## fichier de réglages du test est effacé, puis tout est appliqué.
func reset_for_test() -> void:
	var fresh: Node = (get_script() as GDScript).new()
	for prop in get_property_list():
		var pname: String = prop.name
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not pname.begins_with("_") and pname != "path":
			set(pname, fresh.get(pname))
	fresh.free()
	if path.begins_with(TEST_PATH_PREFIX) and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	reset_bindings()
	apply()


func load_settings() -> void:
	if AutotestMode.is_running():
		path = "%s%d.cfg" % [TEST_PATH_PREFIX, OS.get_process_id()]
		return
	if not load_from(path):
		_needs_probe = true
		language = "fr" if OS.get_locale_language() == "fr" else "en"


## Lit un fichier de réglages (faux s'il n'existe pas). N'applique rien :
## appeler apply_bindings() puis apply() ensuite.
## Fichier lu par SafeConfig : jamais d'objet ni de ressource décodés (un
## .cfg piégé ne peut pas exécuter de code) ; chaque valeur est typée et bornée.
func load_from(file: String) -> bool:
	var cfg := SafeConfig.load_file(file)
	if cfg == null:
		return false
	player_name = SafeConfig.get_string(cfg, "player", "name", player_name, 64)
	character = CharacterDB.clean_choice(SafeConfig.get_string(cfg, "player", "character", CharacterDB.AUTO, 16))
	mouse_sensitivity = SafeConfig.get_float(cfg, "controls", "mouse_sensitivity", mouse_sensitivity, 0.01, 5.0)
	ads_sensitivity = SafeConfig.get_float(cfg, "controls", "ads_sensitivity", ads_sensitivity,
			ADS_SENSITIVITY_RANGE.x, ADS_SENSITIVITY_RANGE.y)
	invert_y = SafeConfig.get_bool(cfg, "controls", "invert_y", invert_y)
	bindings = _bindings_from_cfg(cfg)
	fov = SafeConfig.get_float(cfg, "video", "fov", fov, 40.0, 130.0)
	fullscreen = SafeConfig.get_bool(cfg, "video", "fullscreen", fullscreen)
	vsync = SafeConfig.get_bool(cfg, "video", "vsync", vsync)
	quality = SafeConfig.get_int(cfg, "video", "quality", quality, Quality.LOW, Quality.HIGH) as Quality
	quality_auto = SafeConfig.get_string(cfg, "video", "quality_auto", quality_auto, 32)
	_needs_probe = not cfg.has_section_key("video", "quality")
	film_grain = SafeConfig.get_float(cfg, "video", "film_grain", film_grain, 0.0, 1.0)
	render_scale = SafeConfig.get_float(cfg, "video", "render_scale", render_scale,
			RENDER_SCALE_RANGE.x, RENDER_SCALE_RANGE.y)
	max_fps = SafeConfig.get_int(cfg, "video", "max_fps", max_fps)
	if not max_fps in FPS_LIMITS:
		max_fps = 0
	brightness = SafeConfig.get_float(cfg, "video", "brightness", brightness,
			BRIGHTNESS_RANGE.x, BRIGHTNESS_RANGE.y)
	editor_ui_scale = SafeConfig.get_float(cfg, "interface", "editor_ui_scale", editor_ui_scale,
			EDITOR_UI_SCALE_RANGE.x, EDITOR_UI_SCALE_RANGE.y)
	language = SafeConfig.get_string(cfg, "game", "language", "fr" if OS.get_locale_language() == "fr" else "en", 8)
	if not language in LANGUAGES:
		language = "fr"
	master_volume = SafeConfig.get_float(cfg, "audio", "master", master_volume, 0.0, 1.0)
	music_volume = SafeConfig.get_float(cfg, "audio", "music", music_volume, 0.0, 1.0)
	sfx_volume = SafeConfig.get_float(cfg, "audio", "sfx", sfx_volume, 0.0, 1.0)
	voice_volume = SafeConfig.get_float(cfg, "audio", "voice", voice_volume, 0.0, 1.0)
	last_ip = SafeConfig.get_string(cfg, "network", "last_ip", last_ip, 64)
	last_port = SafeConfig.get_int(cfg, "network", "last_port", last_port, 0, 65535)
	last_map = SafeConfig.get_string(cfg, "game", "last_map", last_map, 128)
	return true


func save_settings() -> void:
	save_to(path)


func save_to(file: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "character", character)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "ads_sensitivity", ads_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	for action in REBINDABLE:
		cfg.set_value("bindings", action, PackedStringArray(bindings.get(action, [])))
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "quality", quality)
	if quality_auto != "":
		cfg.set_value("video", "quality_auto", quality_auto)
	cfg.set_value("video", "film_grain", film_grain)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("interface", "editor_ui_scale", editor_ui_scale)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("network", "last_ip", last_ip)
	cfg.set_value("network", "last_port", last_port)
	cfg.set_value("game", "last_map", last_map)
	cfg.set_value("game", "language", language)
	var err := cfg.save(file)
	if err != OK:
		push_warning("[Settings] réglages non enregistrés (%s) : %s" % [error_string(err), file])


## Applique les options vidéo / audio au moteur. Les réglages de rendu de la
## partie (qualité, échelle 3D, luminosité) sont appliqués par RenderQuality
## à chaque Settings.changed.
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		# En autotest, la fenêtre est gérée par Autotest (réduite puis hors écran).
		if DisplayServer.window_get_mode() != want and not _cmdline_has("--windowed") \
				and not AutotestMode.is_running():
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	# --max-fps (tests, check.sh) l'emporte sur l'option.
	if _cmdline_max_fps == 0:
		Engine.max_fps = max_fps
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)
	changed.emit()


func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


static func _cmdline_has(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args() or flag in OS.get_cmdline_args()


static func _cmdline_has_prefix(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return true
	return false
