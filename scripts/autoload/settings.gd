extends Node
## Settings — options persistantes (user://settings.cfg) et actions d'entrée.

const PATH := "user://settings.cfg"
## Fichier utilisé : les tests automatisés écrivent ailleurs pour ne jamais
## écraser les réglages du joueur (et partent des valeurs par défaut).
const TEST_PATH := "user://settings_autotest.cfg"
var path := PATH

enum Quality { LOW, MEDIUM, HIGH }

signal changed

var player_name := "Claude"
var mouse_sensitivity := 0.25
var invert_y := false
var fov := 80.0
var master_volume := 0.9
var music_volume := 0.7
var sfx_volume := 0.9
var fullscreen := false
var vsync := true
var quality: Quality = Quality.MEDIUM
## Intensité du grain de film en jeu (0 = désactivé, 1 = maximum).
var film_grain := 0.5
var last_ip := "127.0.0.1"
var last_port := 7777
## Dernière carte choisie (sélection solo, salon de l'hôte).
var last_map := "bunker_k7"
## Préréglage automatique (QualityProbe) : compte rendu de la détection faite
## au premier lancement ("" : pas faite). Elle ne se refait jamais ensuite.
var quality_auto := ""
var _needs_probe := false
var _probe: QualityProbe

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


func _ready() -> void:
	_register_inputs()
	load_settings()
	_apply_cmdline_quality()
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
		for key in DEFAULT_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in MOUSE_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BINDINGS[action]
		InputMap.action_add_event(action, mb)
	# Molette : changement d'arme.
	for dir in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var w := InputEventMouseButton.new()
		w.button_index = dir
		InputMap.action_add_event("switch_weapon", w)
	# Navigation des menus à la manette/clavier : on garde les ui_* par défaut.


func load_settings() -> void:
	if _cmdline_has_prefix("--autotest="):
		path = TEST_PATH
		return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		_needs_probe = true
		return
	player_name = cfg.get_value("player", "name", player_name)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = cfg.get_value("video", "fov", fov)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	quality = cfg.get_value("video", "quality", quality)
	quality_auto = cfg.get_value("video", "quality_auto", quality_auto)
	_needs_probe = not cfg.has_section_key("video", "quality")
	film_grain = cfg.get_value("video", "film_grain", film_grain)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	last_ip = cfg.get_value("network", "last_ip", last_ip)
	last_port = cfg.get_value("network", "last_port", last_port)
	last_map = cfg.get_value("game", "last_map", last_map)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "quality", quality)
	if quality_auto != "":
		cfg.set_value("video", "quality_auto", quality_auto)
	cfg.set_value("video", "film_grain", film_grain)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("network", "last_ip", last_ip)
	cfg.set_value("network", "last_port", last_port)
	cfg.set_value("game", "last_map", last_map)
	cfg.save(path)


## Applique les options vidéo / audio au moteur.
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		# En autotest, la fenêtre est gérée par Autotest (réduite puis hors écran).
		if DisplayServer.window_get_mode() != want and not _cmdline_has("--windowed") \
				and not _cmdline_has_prefix("--autotest="):
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
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
