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
## Carte retirée du jeu (KINO, GAME_CONCEPT §6) : un choix mémorisé dessus
## retombe sur BUNKER K-7 au chargement des réglages.
const RETIRED_MAPS := ["kino"]
## Serveur MCP du jeu (McpServer, docs/MCP.md) : une IA peut piloter
## l'éditeur de cartes (127.0.0.1 seulement, jeton). Activé par défaut.
var mcp_enabled := true
## Préréglage automatique (QualityProbe) : compte rendu de la détection faite
## au premier lancement ("" : pas faite). Elle ne se refait jamais ensuite.
var quality_auto := ""
var _needs_probe := false
var _probe: QualityProbe
## Limite d'images imposée par la ligne de commande (--max-fps, tests) : elle
## l'emporte sur l'option.
var _cmdline_max_fps := 0
## Valeur de `fullscreen` déjà appliquée à la fenêtre (null : jamais) : le mode
## de la fenêtre n'est touché que si l'option change (voir window_mode_for).
var _applied_fullscreen = null

## Actions -> touche par défaut (clavier AZERTY et QWERTY : on mappe par
## keycode physique pour que ZQSD/WASD tombe au même endroit). Une seule
## touche d'origine par action (la deuxième case est vide) : « Appuyez sur
## F » désigne toujours la première.
const DEFAULT_BINDINGS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_SHIFT,
	"crouch": KEY_C,
	"interact": KEY_F,
	"reload": KEY_R,
	"melee": KEY_V,
	"grenade": KEY_G,
	# Arme suivante : Q (A en AZERTY) et la molette ; 1 à 3 choisissent
	# directement l'arme en main (GAME_CONCEPT §4.12 : trois armes).
	"switch_weapon": KEY_Q,
	"weapon_1": KEY_1,
	"weapon_2": KEY_2,
	"weapon_3": KEY_3,
	"inventory": KEY_I,
	"scoreboard": KEY_TAB,
	"pause": KEY_ESCAPE,
}
const MOUSE_BINDINGS := {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
}
## Manette par défaut. Xbox et PlayStation : JoyButton / JoyAxis suivent la
## disposition standard SDL, une seule table sert aux deux. Proche de la
## disposition « par défaut » de BO1 sur console, une seule commande par
## bouton (README.md, « Commandes ») : boutons...
const DEFAULT_PAD_BUTTONS := {
	"jump": JOY_BUTTON_A,
	"crouch": JOY_BUTTON_B,
	"interact": JOY_BUTTON_X,
	"switch_weapon": JOY_BUTTON_Y,
	"reload": JOY_BUTTON_RIGHT_SHOULDER,
	"grenade": JOY_BUTTON_LEFT_SHOULDER,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"melee": JOY_BUTTON_RIGHT_STICK,
	"scoreboard": JOY_BUTTON_BACK,
	# Croix : inventaire en haut, armes 1 à 3 à gauche, en bas, à droite.
	"inventory": JOY_BUTTON_DPAD_UP,
	"weapon_1": JOY_BUTTON_DPAD_LEFT,
	"weapon_2": JOY_BUTTON_DPAD_DOWN,
	"weapon_3": JOY_BUTTON_DPAD_RIGHT,
}
## ... et axes [axe, sens] : stick gauche (déplacement analogique), gâchettes.
const DEFAULT_PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1],
	"move_back": [JOY_AXIS_LEFT_Y, 1],
	"move_left": [JOY_AXIS_LEFT_X, -1],
	"move_right": [JOY_AXIS_LEFT_X, 1],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1],
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1],
}

## Actions réaffectables, dans l'ordre de l'écran OPTIONS > COMMANDES.
## « pause » (Échap, Start / Options) reste fixe : c'est aussi ce qui annule
## une réaffectation. La molette change d'arme, en plus de la touche, sauf
## dans un sens affecté à une action (wheel_switch_events).
const REBINDABLE := ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch",
	"sprint", "fire", "aim", "reload", "interact", "melee", "grenade",
	"switch_weapon", "weapon_1", "weapon_2", "weapon_3", "inventory", "scoreboard"]
## Choix direct de l'arme en main (emplacements 1 à 3, PlayerInput.select_slot).
const WEAPON_SLOT_ACTIONS := ["weapon_1", "weapon_2", "weapon_3"]
## Commandes par action et par colonne (clavier / souris, manette) : deux
## cases, la première est celle des invites.
const SLOTS_PER_COLUMN := 2
## Crans de molette, affectables à une action comme un bouton (un cran = un
## appui bref) ; haut / bas changent d'arme tant qu'ils ne sont pas affectés.
const WHEEL_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
const WHEEL_SWITCHES_WEAPON := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
## Boutons de souris acceptés en réaffectation (molette comprise).
const BINDABLE_MOUSE := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE,
	MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
## Boutons de manette réservés : Guide / PS (système) et Start / Options
## (pause, annule une réaffectation à la manette).
const RESERVED_PAD_BUTTONS := [JOY_BUTTON_GUIDE, JOY_BUTTON_START]
## Axes de manette affectables : stick gauche et gâchettes (le stick droit
## tourne la vue, il n'est pas réaffectable).
const BINDABLE_PAD_AXES := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
## Inclinaison d'un axe retenue en réaffectation (gâchette ou stick bien
## enfoncé) ; au-delà de PAD_MOVE_THRESHOLD, la manette devient le
## périphérique courant (invites).
const CAPTURE_AXIS_THRESHOLD := 0.6
const PAD_MOVE_THRESHOLD := 0.5
## Zone morte des actions de déplacement (le stick gauche est lu en
## analogique par PlayerInput, qui applique sa propre zone morte radiale).
const MOVE_DEADZONE := 0.15
const MOVE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right"]

## Touches courantes (clavier / souris) de chaque action : action -> liste
## de 0 à SLOTS_PER_COLUMN codes dans l'ordre des cases (« key:<physical_keycode> »,
## « mouse:<bouton> », molette comprise). Jamais de case vide au milieu : la
## deuxième remonte si la première est effacée.
## Voir bind(), reset_bindings(), apply_bindings().
var bindings := {}
## Boutons de manette de chaque action : action -> liste de codes
## (« joy:<JoyButton> », « joyaxis:<JoyAxis>:<-1|1> »). Deuxième colonne des options.
var pad_bindings := {}

## Sensibilité de la vue au stick droit (multiplicateur, voir PlayerInput).
var pad_look_sensitivity := 1.0
const PAD_SENSITIVITY_RANGE := Vector2(0.3, 3.0)

## Dernier périphérique utilisé : les invites du HUD montrent le bouton de la
## manette (« Appuyer sur X ») ou la touche (« Appuyer sur F »). Voir note_input().
signal input_device_changed(pad: bool)
var using_pad := false
## Manette qui a servi en dernier (-1 : aucune) : son nom choisit les noms
## des boutons, Xbox ou PlayStation (PadNames.style_of).
var pad_device := -1
## Le dernier appui de COURIR venait-il de la manette ? Seul un appui de la
## manette verrouille le sprint (clic de L3, PlayerInput) : une touche du
## clavier, même brève, jamais (drapeau using_pad resté sur la manette).
var sprint_press_pad := false


## Taille de l'interface de l'éditeur ramenée dans la plage et au pas de 5 %
## (valeur non finie : taille par défaut).
static func clamp_editor_ui_scale(v: float) -> float:
	if not is_finite(v):
		return EDITOR_UI_SCALE_DEFAULT
	return clampf(snappedf(v, EDITOR_UI_SCALE_STEP), EDITOR_UI_SCALE_RANGE.x, EDITOR_UI_SCALE_RANGE.y)


func _ready() -> void:
	_cmdline_max_fps = Engine.max_fps
	# Suivi du périphérique courant même partie suspendue (menu pause).
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
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
	# Échap / Start (Options) : menu pause (fixe).
	InputMap.action_erase_events("pause")
	var esc := InputEventKey.new()
	esc.physical_keycode = DEFAULT_BINDINGS.pause
	InputMap.action_add_event("pause", esc)
	InputMap.action_add_event("pause", _pad_button_event(JOY_BUTTON_START))
	bindings = default_bindings()
	pad_bindings = default_pad_bindings()
	# Navigation des menus : les ui_* par défaut (flèches, croix et stick
	# gauche) plus, à la manette, A / Croix (valider), B / Rond (retour) et
	# LB / RB (onglet précédent / suivant), absents des ui_* de Godot.
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B],
			["ui_page_up", JOY_BUTTON_LEFT_SHOULDER], ["ui_page_down", JOY_BUTTON_RIGHT_SHOULDER]]:
		var ev := _pad_button_event(pair[1])
		if InputMap.has_action(pair[0]) and not InputMap.action_has_event(pair[0], ev):
			InputMap.action_add_event(pair[0], ev)


## Bouton de manette, toutes manettes confondues (device -1).
static func _pad_button_event(button: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button as JoyButton
	return ev


# --------------------------------------------------------------------------
# Touches (réaffectation)
# --------------------------------------------------------------------------

static func key_code(physical_keycode: int) -> String:
	return "key:%d" % physical_keycode


static func mouse_code(button: int) -> String:
	return "mouse:%d" % button


static func pad_button_code(button: int) -> String:
	return "joy:%d" % button


static func pad_axis_code(axis: int, sign_: int) -> String:
	return "joyaxis:%d:%d" % [axis, 1 if sign_ >= 0 else -1]


## Code de manette (deuxième colonne) ?
static func is_pad_code(code: String) -> bool:
	return code.begins_with("joy")


## Touche d'origine (clavier / souris) de chaque action réaffectable : une
## liste d'un code (deuxième case vide).
static func default_bindings() -> Dictionary:
	var d := {}
	for action in REBINDABLE:
		if MOUSE_BINDINGS.has(action):
			d[action] = [mouse_code(MOUSE_BINDINGS[action])]
		elif DEFAULT_BINDINGS.has(action):
			d[action] = [key_code(DEFAULT_BINDINGS[action])]
		else:
			d[action] = []
	return d


## Bouton de manette d'origine de chaque action réaffectable (liste d'un code).
static func default_pad_bindings() -> Dictionary:
	var d := {}
	for action in REBINDABLE:
		if DEFAULT_PAD_BUTTONS.has(action):
			d[action] = [pad_button_code(DEFAULT_PAD_BUTTONS[action])]
		elif DEFAULT_PAD_AXES.has(action):
			d[action] = [pad_axis_code(DEFAULT_PAD_AXES[action][0], DEFAULT_PAD_AXES[action][1])]
		else:
			d[action] = []
	return d


## Cran de molette (souris) ?
static func is_wheel_code(code: String) -> bool:
	for b in WHEEL_BUTTONS:
		if code == mouse_code(b):
			return true
	return false


## Code d'une touche, d'un bouton de souris ou de manette, d'une gâchette ou
## du stick gauche bien enfoncés, d'un cran de molette (« » si non
## réaffectable : Échap, Start, Guide, stick droit, axe à peine incliné...).
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
	if ev is InputEventJoypadButton:
		var jb := int((ev as InputEventJoypadButton).button_index)
		return pad_button_code(jb) if _pad_button_ok(jb) else ""
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		if int(jm.axis) in BINDABLE_PAD_AXES and absf(jm.axis_value) >= CAPTURE_AXIS_THRESHOLD:
			return pad_axis_code(jm.axis, 1 if jm.axis_value > 0.0 else -1)
		return ""
	return ""


static func _pad_button_ok(b: int) -> bool:
	return b >= 0 and b < JOY_BUTTON_SDL_MAX and not b in RESERVED_PAD_BUTTONS


## Événement d'entrée (pour l'InputMap) d'un code, null s'il est invalide.
## Manette : toutes manettes confondues (device -1, branchement à chaud).
static func event_from_code(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() == 3 and parts[0] == "joyaxis":
		if not parts[1].is_valid_int() or not parts[2] in ["1", "-1"]:
			return null
		var axis := parts[1].to_int()
		var sign_ := parts[2].to_int()
		# Gâchettes : enfoncées seulement (repos à 0).
		if not axis in BINDABLE_PAD_AXES or (sign_ < 0 and axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]):
			return null
		var jm := InputEventJoypadMotion.new()
		jm.device = -1
		jm.axis = axis as JoyAxis
		jm.axis_value = float(sign_)
		return jm
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
		"joy":
			if not _pad_button_ok(v):
				return null
			return _pad_button_event(v)
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
## physique W s'affiche Z en AZERTY ; bouton de manette selon `pad_style`,
## Xbox ou PlayStation, voir PadNames).
static func code_label(code: String, pad_style := PadNames.XBOX) -> String:
	var ev := event_from_code(code)
	if ev is InputEventJoypadButton:
		return PadNames.button_label((ev as InputEventJoypadButton).button_index, pad_style)
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		return PadNames.axis_label(jm.axis, int(jm.axis_value), pad_style)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return Lang.t("CLIC GAUCHE", "LEFT CLICK")
			MOUSE_BUTTON_RIGHT: return Lang.t("CLIC DROIT", "RIGHT CLICK")
			MOUSE_BUTTON_MIDDLE: return Lang.t("CLIC MOLETTE", "MIDDLE CLICK")
			MOUSE_BUTTON_XBUTTON1: return Lang.t("SOURIS 4", "MOUSE 4")
			MOUSE_BUTTON_XBUTTON2: return Lang.t("SOURIS 5", "MOUSE 5")
			MOUSE_BUTTON_WHEEL_UP: return Lang.t("MOLETTE HAUT", "WHEEL UP")
			MOUSE_BUTTON_WHEEL_DOWN: return Lang.t("MOLETTE BAS", "WHEEL DOWN")
			MOUSE_BUTTON_WHEEL_LEFT: return Lang.t("MOLETTE GAUCHE", "WHEEL LEFT")
			MOUSE_BUTTON_WHEEL_RIGHT: return Lang.t("MOLETTE DROITE", "WHEEL RIGHT")
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


## Nom de la commande d'une action pour les invites du HUD (« Appuyer sur
## F », « Appuyer sur X », « Press Square ») : le bouton de la manette si
## elle a servi en dernier (et que l'action en a un), sinon la touche. Deux
## commandes dans une colonne : la première.
func action_label(action: String) -> String:
	return prompt_label(binding(action), binding(action, true), using_pad, pad_style())


## Pure (tests) : nom à afficher d'après les deux codes d'une action.
static func prompt_label(key: String, pad: String, use_pad: bool, style := PadNames.XBOX) -> String:
	if use_pad and pad != "":
		return code_label(pad, style)
	if key != "":
		return code_label(key)
	return code_label(pad, style) if pad != "" else "?"


## Code de la case `slot` (0 : la première) de l'action, touche (clavier /
## souris) ou bouton de manette (`pad`) ; « » : case vide.
func binding(action: String, pad := false, slot := 0) -> String:
	var list: Array = (pad_bindings if pad else bindings).get(action, [])
	return String(list[slot]) if slot >= 0 and slot < list.size() else ""


## Toutes les commandes de l'action dans une colonne (copie).
func bindings_of(action: String, pad := false) -> Array:
	return ((pad_bindings if pad else bindings).get(action, []) as Array).duplicate()


## Noms de boutons de la manette courante : PlayStation (DualShock, DualSense)
## ou Xbox (toutes les autres, disposition standard). Sans manette : Xbox.
func pad_style() -> String:
	var pads := Input.get_connected_joypads()
	var dev := pad_device if pad_device in pads else (pads[0] if not pads.is_empty() else -1)
	return PadNames.style_of(Input.get_joy_name(dev)) if dev >= 0 else PadNames.XBOX


## Affecte `code` à la case `slot` (0 ou 1) de `action`, dans la colonne de
## son périphérique (touche ou manette). Une même commande peut servir à
## plusieurs actions : elle n'est retirée d'aucune autre (un appui les
## déclenche toutes). Déjà dans l'autre case de la même action, elle change
## de place (l'ancienne commande de la case visée prend la sienne). Case 1
## alors que la première est vide : elle va en première case. Retourne les
## autres actions qui ont aussi cette commande (shared_with) ; [] sinon, ou
## pour un code refusé.
func bind(action: String, code: String, slot := 0) -> Array:
	if not action in REBINDABLE or event_from_code(code) == null:
		return []
	slot = clampi(slot, 0, SLOTS_PER_COLUMN - 1)
	var col := pad_bindings if is_pad_code(code) else bindings
	var cases := []
	for i in SLOTS_PER_COLUMN:
		cases.append(binding(action, is_pad_code(code), i))
	var old := cases.find(code)
	if old >= 0 and old != slot:
		cases[old] = cases[slot]
	cases[slot] = code
	col[action] = _compact(cases)
	apply_bindings()
	return shared_with(action, code)


## Autres actions réaffectables (dans l'ordre de l'écran) qui ont aussi
## `code` dans sa colonne ; [] pour un code vide.
func shared_with(action: String, code: String) -> Array:
	return codes_shared(bindings, pad_bindings, action, code)


## Pure (tests) : shared_with() d'après les deux colonnes données.
static func codes_shared(keys: Dictionary, pads: Dictionary, action: String, code: String) -> Array:
	var out := []
	if code == "":
		return out
	var col := pads if is_pad_code(code) else keys
	for a in REBINDABLE:
		if a != action and code in (col.get(a, []) as Array):
			out.append(a)
	return out


## Codes sans case vide ni doublon (ordre conservé), SLOTS_PER_COLUMN au plus.
static func _compact(cases: Array) -> Array:
	var out := []
	for c in cases:
		if c is String and c != "" and not c in out and out.size() < SLOTS_PER_COLUMN:
			out.append(c)
	return out


## Vide la case `slot` de la touche (ou du bouton de manette, `pad`) de
## `action` ; la deuxième commande remonte alors en première case.
func clear_binding(action: String, pad := false, slot := 0) -> void:
	var list: Array = (pad_bindings if pad else bindings).get(action, [])
	if slot >= 0 and slot < list.size():
		list.remove_at(slot)
		apply_bindings()


## Rétablit les deux colonnes (touches et manette).
func reset_bindings() -> void:
	bindings = default_bindings()
	pad_bindings = default_pad_bindings()
	apply_bindings()


## Reconstruit l'InputMap des actions réaffectables d'après `bindings` et
## `pad_bindings`.
func apply_bindings() -> void:
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, MOVE_DEADZONE if action in MOVE_ACTIONS else 0.5)
		for code in bindings_of(action) + bindings_of(action, true):
			var ev := event_from_code(code)
			if ev:
				InputMap.action_add_event(action, ev)
	for w in wheel_switch_events(bindings):
		InputMap.action_add_event("switch_weapon", w)
	bindings_changed.emit()


## Molette : changement d'arme (haut / bas), sauf pour un cran affecté à une
## action dans `keys` (colonne des touches ; affecté à CHANGER D'ARME, il y
## est déjà). Pure (tests).
static func wheel_switch_events(keys: Dictionary) -> Array[InputEventMouseButton]:
	var used := {}
	for a in keys:
		for c in keys[a]:
			used[c] = true
	var out: Array[InputEventMouseButton] = []
	for dir in WHEEL_SWITCHES_WEAPON:
		if not used.has(mouse_code(dir)):
			var w := InputEventMouseButton.new()
			w.button_index = dir
			out.append(w)
	return out


## Commandes lues d'un fichier, pour une colonne (section « bindings » :
## touches, « pad_bindings » : manette). `max_codes` au plus par action (deux
## par défaut) : les premières valides de la bonne colonne, sans doublon dans
## l'action ; une commande partagée par plusieurs actions reste sur chacune
## (une version précédente en écrivait une seule, en liste ou en texte :
## relue telle quelle ; les fichiers d'avant le partage n'en ont aucune).
## Action absente du fichier (nouvelle version) : ses commandes d'origine,
## sauf celles qu'une action du fichier a déjà (aucun partage que le joueur
## n'a pas choisi).
static func _bindings_from_cfg(cfg: ConfigFile, section: String, defaults: Dictionary, pad: bool,
		max_codes := SLOTS_PER_COLUMN) -> Dictionary:
	var d := defaults.duplicate(true)
	var used := {}
	for action in REBINDABLE:
		if not cfg.has_section_key(section, action):
			continue
		var raw: Variant = cfg.get_value(section, action, "")
		var list: Array = []
		if raw is String or raw is StringName:
			list = [raw]
		elif raw is Array or raw is PackedStringArray:
			list = Array(raw).slice(0, 8)  # fichier piégé : quelques valeurs au plus
		var picks := []
		for c in list:
			var code := str(c)
			if is_pad_code(code) == pad and event_from_code(code) != null and not code in picks:
				picks.append(code)
				used[code] = true
				if picks.size() >= max_codes:
					break
		d[action] = picks
	for action in REBINDABLE:
		if not cfg.has_section_key(section, action):
			var keep := []
			for code in d[action]:
				if not used.has(code):
					used[code] = true
					keep.append(code)
			d[action] = keep
	return d


# --------------------------------------------------------------------------
# Périphérique courant (invites clavier ou manette)
# --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	note_input(event)


## Retient le dernier périphérique utilisé (appelée aussi par l'écran des
## options pendant une réaffectation, qui consomme les entrées). Une manette
## à peine effleurée (stick au repos qui dérive) ne compte pas.
func note_input(event: InputEvent) -> void:
	if InputMap.has_action("sprint") and event.is_action_pressed("sprint"):
		sprint_press_pad = event is InputEventJoypadButton or event is InputEventJoypadMotion
	var pad := using_pad
	if event is InputEventJoypadButton and event.pressed:
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= PAD_MOVE_THRESHOLD:
		pad = true
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0:
		pad = false
	else:
		return
	if pad:
		pad_device = event.device
	_set_using_pad(pad)


func _set_using_pad(pad: bool) -> void:
	if pad == using_pad:
		return
	using_pad = pad
	input_device_changed.emit(pad)


## Manette branchée ou débranchée en cours de partie : jamais d'erreur ; la
## dernière débranchée sans autre manette rend les invites au clavier.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	var pads := Input.get_connected_joypads()
	if device == pad_device:
		pad_device = pads[0] if not pads.is_empty() else -1
	if pads.is_empty():
		_set_using_pad(false)
	input_device_changed.emit(using_pad)


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
	pad_look_sensitivity = SafeConfig.get_float(cfg, "controls", "pad_look_sensitivity", pad_look_sensitivity,
			PAD_SENSITIVITY_RANGE.x, PAD_SENSITIVITY_RANGE.y)
	# Fichier sans colonne manette : versions d'avant la manette, qui
	# mettaient deux touches d'origine à certaines actions (E interagissait
	# aussi) : seule la première est gardée, comme dans les versions suivantes.
	var keys_max := SLOTS_PER_COLUMN if cfg.has_section("pad_bindings") else 1
	bindings = _bindings_from_cfg(cfg, "bindings", default_bindings(), false, keys_max)
	pad_bindings = _bindings_from_cfg(cfg, "pad_bindings", default_pad_bindings(), true)
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
	if last_map in RETIRED_MAPS:
		last_map = "bunker_k7"
	mcp_enabled = SafeConfig.get_bool(cfg, "mcp", "enabled", mcp_enabled)
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
	cfg.set_value("controls", "pad_look_sensitivity", pad_look_sensitivity)
	for action in REBINDABLE:
		# Listes de deux codes au plus (une version précédente relit la
		# première commande valide de sa colonne).
		cfg.set_value("bindings", action, PackedStringArray(bindings_of(action)))
		cfg.set_value("pad_bindings", action, PackedStringArray(bindings_of(action, true)))
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
	cfg.set_value("mcp", "enabled", mcp_enabled)
	cfg.set_value("game", "language", language)
	var err := cfg.save(file)
	if err != OK:
		push_warning("[Settings] réglages non enregistrés (%s) : %s" % [error_string(err), file])


## Applique les options vidéo / audio au moteur. Les réglages de rendu de la
## partie (qualité, échelle 3D, luminosité) sont appliqués par RenderQuality
## à chaque Settings.changed.
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		# En autotest, la fenêtre est gérée par Autotest (réduite puis hors écran).
		if fullscreen != _applied_fullscreen and not _cmdline_has("--windowed") \
				and not AutotestMode.is_running():
			var want := window_mode_for(fullscreen, DisplayServer.window_get_mode())
			if want >= 0:
				DisplayServer.window_set_mode(want)
		_applied_fullscreen = fullscreen
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	# --max-fps (tests, check.sh) l'emporte sur l'option.
	if _cmdline_max_fps == 0:
		Engine.max_fps = max_fps
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)
	changed.emit()


## Mode à donner à la fenêtre pour l'option plein écran, -1 : la laisser telle
## quelle. Une fenêtre agrandie ou réduite reste ainsi quand le plein écran est
## désactivé, et un plein écran exclusif reste plein écran.
static func window_mode_for(want_fullscreen: bool, current: int) -> int:
	var is_full := current == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fullscreen == is_full:
		return -1
	return DisplayServer.WINDOW_MODE_FULLSCREEN if want_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED


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
