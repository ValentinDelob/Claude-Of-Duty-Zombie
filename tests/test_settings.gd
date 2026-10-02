extends TestCase
## Réglages : touches et boutons de manette réaffectables (une commande par
## action et par colonne, conflits, InputMap, anciens fichiers), noms des
## boutons Xbox / PlayStation et invites, sticks (zone morte, vue), options
## graphiques et de contrôle ajoutées, enregistrement puis rechargement.
## Tout se fait dans un fichier temporaire : les réglages du joueur ne sont
## jamais touchés, et l'état de Settings est restauré après chaque test.

const TMP := "user://settings_unittest.cfg"
const SAVED_KEYS := ["bindings", "pad_bindings", "pad_look_sensitivity", "using_pad", "pad_device",
	"render_scale", "max_fps", "brightness", "ads_sensitivity",
	"mouse_sensitivity", "invert_y", "language", "fov", "film_grain", "quality", "editor_ui_scale", "character"]

var _saved := {}


func before_each() -> void:
	for k in SAVED_KEYS:
		var v = Settings.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary else v
	Settings.reset_bindings()


func after_each() -> void:
	for k in SAVED_KEYS:
		Settings.set(k, _saved[k])
	Settings.apply_bindings()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func _has_key(action: String, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return true
	return false


func _has_mouse(action: String, button: MouseButton) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			return true
	return false


func _has_pad_button(action: String, button: JoyButton) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false


func _has_pad_axis(action: String, axis: JoyAxis, sign_: float) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == axis \
				and signf((ev as InputEventJoypadMotion).axis_value) == sign_:
			return true
	return false


func _k(key: Key) -> String:
	return "key:%d" % key


func test_one_key_per_action_by_default() -> void:
	@warning_ignore("static_called_on_instance")
	var d := Settings.default_bindings()
	assert_eq(d.size(), Settings.REBINDABLE.size())
	assert_eq(d.crouch, _k(KEY_C), "S'ACCROUPIR : C seulement")
	assert_eq(d.interact, _k(KEY_F), "INTERAGIR : F seulement (l'invite dit F)")
	assert_eq(d.switch_weapon, _k(KEY_1), "CHANGER D'ARME : 1 (+ molette)")
	assert_eq(d.fire, "mouse:%d" % MOUSE_BUTTON_LEFT)
	assert_eq(d.aim, "mouse:%d" % MOUSE_BUTTON_RIGHT)
	assert_true(_has_key("move_forward", KEY_W), "Z/W avance")
	assert_true(_has_key("interact", KEY_F) and not _has_key("interact", KEY_E), "F interagit, E ne fait plus rien")
	assert_false(_has_key("crouch", KEY_CTRL), "Ctrl libre")
	assert_false(_has_key("switch_weapon", KEY_2), "2 libre")
	assert_true(_has_mouse("fire", MOUSE_BUTTON_LEFT), "clic gauche tire")
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_UP), "molette : changement d'arme")
	assert_true(_has_key("pause", KEY_ESCAPE), "Échap : pause (fixe)")
	# Une seule commande par colonne : jamais deux actions sur la même.
	var seen := {}
	for a in Settings.REBINDABLE:
		assert_true(d[a] is String and d[a] != "", "%s : une touche" % a)
		assert_false(seen.has(d[a]), "%s : touche unique" % a)
		seen[d[a]] = true


func test_default_pad_layout() -> void:
	@warning_ignore("static_called_on_instance")
	var p := Settings.default_pad_bindings()
	assert_eq(p.size(), Settings.REBINDABLE.size())
	var expect := {
		"jump": "joy:%d" % JOY_BUTTON_A, "crouch": "joy:%d" % JOY_BUTTON_B,
		"interact": "joy:%d" % JOY_BUTTON_X, "switch_weapon": "joy:%d" % JOY_BUTTON_Y,
		"reload": "joy:%d" % JOY_BUTTON_RIGHT_SHOULDER, "grenade": "joy:%d" % JOY_BUTTON_LEFT_SHOULDER,
		"tactical": "joy:%d" % JOY_BUTTON_DPAD_RIGHT, "sprint": "joy:%d" % JOY_BUTTON_LEFT_STICK,
		"melee": "joy:%d" % JOY_BUTTON_RIGHT_STICK, "scoreboard": "joy:%d" % JOY_BUTTON_BACK,
		"aim": "joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT, "fire": "joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT,
		"move_forward": "joyaxis:%d:-1" % JOY_AXIS_LEFT_Y, "move_back": "joyaxis:%d:1" % JOY_AXIS_LEFT_Y,
		"move_left": "joyaxis:%d:-1" % JOY_AXIS_LEFT_X, "move_right": "joyaxis:%d:1" % JOY_AXIS_LEFT_X,
	}
	assert_eq(p, expect)
	var seen := {}
	for a in Settings.REBINDABLE:
		assert_false(seen.has(p[a]), "%s : bouton unique" % a)
		seen[p[a]] = true
	assert_true(_has_pad_button("jump", JOY_BUTTON_A), "A / Croix saute")
	assert_true(_has_pad_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0), "RT / R2 tire")
	assert_true(_has_pad_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0), "stick gauche vers le haut : avancer")
	assert_true(_has_pad_button("pause", JOY_BUTTON_START), "Start / Options : pause (fixe)")
	assert_near(InputMap.action_get_deadzone("move_forward"), Settings.MOVE_DEADZONE, 0.001, "zone morte du déplacement")
	# Menus à la manette : A valide, B revient, LB / RB changent d'onglet.
	assert_true(_has_pad_button("ui_accept", JOY_BUTTON_A) and _has_pad_button("ui_cancel", JOY_BUTTON_B))
	assert_true(_has_pad_button("ui_page_up", JOY_BUTTON_LEFT_SHOULDER) and _has_pad_button("ui_page_down", JOY_BUTTON_RIGHT_SHOULDER))
	# Toutes manettes (branchement à chaud) : device -1.
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventJoypadButton:
			assert_eq(ev.device, -1)


func test_codes_roundtrip() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_T
	k.pressed = true
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(k), _k(KEY_T))
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(esc), "", "Échap : jamais affectable")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(wheel), "", "molette exclue")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(mb), "mouse:%d" % MOUSE_BUTTON_XBUTTON1)
	@warning_ignore("static_called_on_instance")
	assert_true(Settings.event_from_code(_k(KEY_T)) is InputEventKey)
	@warning_ignore("static_called_on_instance")
	assert_true(Settings.event_from_code("mouse:%d" % MOUSE_BUTTON_MIDDLE) is InputEventMouseButton)
	for bad in ["", "key:", "key:abc", "mouse:4", "pad:1", _k(KEY_ESCAPE)]:
		@warning_ignore("static_called_on_instance")
		assert_true(Settings.event_from_code(bad) == null, "code invalide « %s »" % bad)


func test_pad_codes_roundtrip_and_sanitized() -> void:
	# Boutons.
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_Y
	jb.pressed = true
	@warning_ignore("static_called_on_instance")
	var code := Settings.code_from_event(jb)
	assert_eq(code, "joy:%d" % JOY_BUTTON_Y)
	@warning_ignore("static_called_on_instance")
	var back := Settings.event_from_code(code) as InputEventJoypadButton
	assert_true(back != null and back.button_index == JOY_BUTTON_Y and back.device == -1, "bouton relu, toutes manettes")
	for reserved in [JOY_BUTTON_START, JOY_BUTTON_GUIDE]:
		jb.button_index = reserved
		@warning_ignore("static_called_on_instance")
		assert_eq(Settings.code_from_event(jb), "", "Start / Guide réservés")
	# Gâchettes et stick gauche : seulement bien enfoncés ; stick droit : la vue.
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_TRIGGER_RIGHT
	jm.axis_value = 0.9
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(jm), "joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT)
	jm.axis_value = 0.3
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(jm), "", "gâchette à peine enfoncée")
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = -0.8
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(jm), "joyaxis:%d:-1" % JOY_AXIS_LEFT_X)
	jm.axis = JOY_AXIS_RIGHT_Y
	jm.axis_value = 1.0
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(jm), "", "stick droit non affectable")
	@warning_ignore("static_called_on_instance")
	var ax := Settings.event_from_code("joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT) as InputEventJoypadMotion
	assert_true(ax != null and ax.axis == JOY_AXIS_TRIGGER_LEFT and ax.axis_value == 1.0 and ax.device == -1)
	for bad in ["joy:", "joy:-1", "joy:%d" % JOY_BUTTON_START, "joy:%d" % JOY_BUTTON_GUIDE, "joy:999", "joy:x",
			"joyaxis:4", "joyaxis:4:2", "joyaxis:4:-1", "joyaxis:%d:1" % JOY_AXIS_RIGHT_X, "joyaxis:a:1",
			"joyaxis:9:1", "joyaxis:0:1:1"]:
		@warning_ignore("static_called_on_instance")
		assert_true(Settings.event_from_code(bad) == null, "code de manette invalide « %s »" % bad)
	@warning_ignore("static_called_on_instance")
	assert_true(Settings.is_pad_code("joy:0") and Settings.is_pad_code("joyaxis:4:1") and not Settings.is_pad_code(_k(KEY_J)))


func test_rebind_updates_input_map() -> void:
	var taken := Settings.bind("reload", _k(KEY_T))
	assert_eq(taken, "")
	assert_eq(Settings.bindings.reload, _k(KEY_T), "une seule touche : T remplace R")
	assert_true(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "R -> T dans l'InputMap")
	assert_eq(Settings.pad_bindings.reload, "joy:%d" % JOY_BUTTON_RIGHT_SHOULDER, "le bouton de manette reste")
	Settings.bind("reload", "mouse:%d" % MOUSE_BUTTON_XBUTTON2)
	assert_eq(Settings.bindings.reload, "mouse:%d" % MOUSE_BUTTON_XBUTTON2)
	assert_true(_has_mouse("reload", MOUSE_BUTTON_XBUTTON2) and not _has_key("reload", KEY_T), "bouton 5 de la souris")
	# Colonne manette : ne touche pas à la touche.
	Settings.bind("reload", "joy:%d" % JOY_BUTTON_DPAD_UP)
	assert_eq(Settings.pad_bindings.reload, "joy:%d" % JOY_BUTTON_DPAD_UP)
	assert_eq(Settings.bindings.reload, "mouse:%d" % MOUSE_BUTTON_XBUTTON2)
	assert_true(_has_pad_button("reload", JOY_BUTTON_DPAD_UP) and not _has_pad_button("reload", JOY_BUTTON_RIGHT_SHOULDER))
	assert_eq(Settings.bind("reload", "joy:bogus"), "", "code invalide refusé")
	assert_eq(Settings.pad_bindings.reload, "joy:%d" % JOY_BUTTON_DPAD_UP)


func test_conflict_removes_key_from_other_action() -> void:
	var taken := Settings.bind("reload", _k(KEY_G))
	assert_eq(taken, "grenade", "G retiré de GRENADE")
	assert_eq(Settings.bindings.grenade, "")
	assert_false(_has_key("grenade", KEY_G), "plus de G sur la grenade")
	assert_true(_has_key("reload", KEY_G))
	assert_eq(Settings.pad_bindings.grenade, "joy:%d" % JOY_BUTTON_LEFT_SHOULDER, "la manette n'est pas touchée")
	# Tir sur une touche : le clic gauche reste libre de toute action.
	assert_eq(Settings.bind("aim", "mouse:%d" % MOUSE_BUTTON_LEFT), "fire")
	assert_false(_has_mouse("fire", MOUSE_BUTTON_LEFT))


func test_pad_conflict_stays_in_pad_column() -> void:
	# Y (changer d'arme) sur RECHARGER : retiré de CHANGER D'ARME, côté manette seulement.
	var taken := Settings.bind("reload", "joy:%d" % JOY_BUTTON_Y)
	assert_eq(taken, "switch_weapon")
	assert_eq(Settings.pad_bindings.switch_weapon, "")
	assert_eq(Settings.bindings.switch_weapon, _k(KEY_1), "la touche 1 reste")
	assert_false(_has_pad_button("switch_weapon", JOY_BUTTON_Y))
	# Gâchette : même règle.
	assert_eq(Settings.bind("melee", "joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT), "fire")
	assert_eq(Settings.pad_bindings.fire, "")
	assert_true(_has_pad_axis("melee", JOY_AXIS_TRIGGER_RIGHT, 1.0))
	assert_true(_has_mouse("fire", MOUSE_BUTTON_LEFT), "le clic gauche tire toujours")


func test_clear_binding_per_column() -> void:
	Settings.clear_binding("crouch")
	assert_eq(Settings.bindings.crouch, "")
	assert_false(_has_key("crouch", KEY_C))
	assert_true(_has_pad_button("crouch", JOY_BUTTON_B), "B accroupit toujours")
	Settings.clear_binding("crouch", true)
	assert_eq(Settings.pad_bindings.crouch, "")
	assert_true(InputMap.action_get_events("crouch").is_empty())
	assert_eq(Settings.action_label("crouch"), "?", "aucune commande : « ? »")


func test_reset_bindings() -> void:
	Settings.bind("jump", _k(KEY_W))
	Settings.bind("jump", "joy:%d" % JOY_BUTTON_X)
	assert_false(_has_key("move_forward", KEY_W))
	Settings.reset_bindings()
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.bindings, Settings.default_bindings())
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.pad_bindings, Settings.default_pad_bindings(), "colonne manette rétablie aussi")
	assert_true(_has_key("move_forward", KEY_W) and _has_key("jump", KEY_SPACE))
	assert_true(_has_pad_button("interact", JOY_BUTTON_X) and _has_pad_button("jump", JOY_BUTTON_A))


func test_save_and_reload() -> void:
	Settings.bind("reload", _k(KEY_T))
	Settings.bind("melee", "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	Settings.bind("reload", "joy:%d" % JOY_BUTTON_DPAD_DOWN)
	Settings.bind("grenade", "joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT)
	Settings.render_scale = 0.7
	Settings.max_fps = 144
	Settings.brightness = 1.25
	Settings.ads_sensitivity = 0.6
	Settings.pad_look_sensitivity = 1.7
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_eq(Array(cfg.get_value("bindings", "reload")), [_k(KEY_T)], "touche dans settings.cfg (format des versions précédentes)")
	assert_eq(cfg.get_value("pad_bindings", "reload"), "joy:%d" % JOY_BUTTON_DPAD_DOWN, "bouton de manette dans settings.cfg")
	# Retour aux valeurs d'origine, puis rechargement du fichier.
	Settings.reset_bindings()
	Settings.render_scale = 1.0
	Settings.max_fps = 0
	Settings.brightness = 1.0
	Settings.ads_sensitivity = 1.0
	Settings.pad_look_sensitivity = 1.0
	assert_true(Settings.load_from(TMP), "fichier relu")
	Settings.apply_bindings()
	assert_eq(Settings.bindings.reload, _k(KEY_T))
	assert_eq(Settings.bindings.melee, "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	assert_eq(Settings.pad_bindings.reload, "joy:%d" % JOY_BUTTON_DPAD_DOWN)
	assert_eq(Settings.pad_bindings.grenade, "joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT)
	assert_eq(Settings.pad_bindings.aim, "", "LT pris par GRENADE")
	assert_true(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "InputMap rechargée")
	assert_true(_has_pad_axis("grenade", JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_near(Settings.render_scale, 0.7)
	assert_eq(Settings.max_fps, 144)
	assert_near(Settings.brightness, 1.25)
	assert_near(Settings.ads_sensitivity, 0.6)
	assert_near(Settings.pad_look_sensitivity, 1.7)


func test_old_two_key_file_migrates() -> void:
	# Fichier d'une version précédente : deux touches par action, pas de
	# colonne manette. La première touche valide est gardée, la manette a
	# sa disposition d'origine.
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "crouch", PackedStringArray([_k(KEY_CTRL), _k(KEY_C)]))
	cfg.set_value("bindings", "interact", PackedStringArray([_k(KEY_F), _k(KEY_E)]))
	cfg.set_value("bindings", "switch_weapon", PackedStringArray([_k(KEY_1), _k(KEY_2)]))
	cfg.set_value("bindings", "reload", PackedStringArray(["bogus", _k(KEY_T), _k(KEY_Y)]))
	cfg.set_value("bindings", "melee", PackedStringArray([]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	Settings.apply_bindings()
	assert_eq(Settings.bindings.crouch, _k(KEY_CTRL), "première touche gardée")
	assert_eq(Settings.bindings.interact, _k(KEY_F))
	assert_eq(Settings.bindings.switch_weapon, _k(KEY_1))
	assert_eq(Settings.bindings.reload, _k(KEY_T), "première touche VALIDE")
	assert_eq(Settings.bindings.melee, "", "touche effacée par le joueur : reste vide")
	assert_eq(Settings.bindings.grenade, _k(KEY_G), "action absente : touche d'origine")
	assert_false(_has_key("interact", KEY_E), "E n'interagit plus")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.pad_bindings, Settings.default_pad_bindings(), "manette : disposition d'origine")


func test_invalid_file_values_are_sanitized() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "render_scale", 3.0)
	cfg.set_value("video", "max_fps", 77)
	cfg.set_value("video", "brightness", -1.0)
	cfg.set_value("controls", "pad_look_sensitivity", 99.0)
	# Touche en double, code invalide ; « tactical » absent du fichier : sa
	# touche d'origine Q, déjà prise par « jump », n'est pas remise.
	cfg.set_value("bindings", "jump", PackedStringArray([_k(KEY_Q), "bogus", _k(KEY_Q)]))
	cfg.set_value("bindings", "reload", PackedStringArray([_k(KEY_R), _k(KEY_T), _k(KEY_Y)]))
	# Code de manette dans la colonne des touches (et l'inverse) : refusé.
	cfg.set_value("bindings", "melee", PackedStringArray(["joy:%d" % JOY_BUTTON_A]))
	cfg.set_value("pad_bindings", "melee", _k(KEY_V))
	# Manette : doublon (A déjà pris par « jump »), codes piégés, mauvais type.
	cfg.set_value("pad_bindings", "jump", "joy:%d" % JOY_BUTTON_A)
	cfg.set_value("pad_bindings", "interact", "joy:%d" % JOY_BUTTON_A)
	cfg.set_value("pad_bindings", "fire", "joyaxis:%d:1" % JOY_AXIS_RIGHT_X)
	cfg.set_value("pad_bindings", "aim", 42)
	cfg.set_value("pad_bindings", "reload", PackedStringArray(["joy:%d" % JOY_BUTTON_START, "joy:%d" % JOY_BUTTON_DPAD_UP]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	assert_near(Settings.render_scale, Settings.RENDER_SCALE_RANGE.y)
	assert_eq(Settings.max_fps, 0, "limite inconnue -> illimitée")
	assert_near(Settings.brightness, Settings.BRIGHTNESS_RANGE.x)
	assert_near(Settings.pad_look_sensitivity, Settings.PAD_SENSITIVITY_RANGE.y)
	assert_eq(Settings.bindings.jump, _k(KEY_Q))
	assert_eq(Settings.bindings.reload, _k(KEY_R), "une seule touche")
	assert_eq(Settings.bindings.tactical, "", "Q déjà pris")
	assert_eq(Settings.bindings.grenade, _k(KEY_G), "action absente : touche d'origine")
	assert_eq(Settings.bindings.melee, "", "bouton de manette refusé dans la colonne des touches")
	assert_eq(Settings.pad_bindings.melee, "", "touche refusée dans la colonne manette")
	assert_eq(Settings.pad_bindings.jump, "joy:%d" % JOY_BUTTON_A)
	assert_eq(Settings.pad_bindings.interact, "", "A déjà pris")
	assert_eq(Settings.pad_bindings.fire, "", "stick droit refusé")
	assert_eq(Settings.pad_bindings.aim, "", "mauvais type")
	assert_eq(Settings.pad_bindings.reload, "joy:%d" % JOY_BUTTON_DPAD_UP, "Start refusé, valeur suivante")
	assert_eq(Settings.pad_bindings.switch_weapon, "joy:%d" % JOY_BUTTON_Y, "action absente : bouton d'origine")


# ------------------------------------------------------------------ taille de l'interface de l'éditeur

func test_editor_ui_scale_default_and_bounds() -> void:
	assert_near(Settings.EDITOR_UI_SCALE_DEFAULT, 0.8, 0.001, "80 % par défaut (l'ancienne taille était trop grosse)")
	assert_near(Settings.EDITOR_UI_SCALE_RANGE.x, 0.6)
	assert_near(Settings.EDITOR_UI_SCALE_RANGE.y, 1.5)
	# Plage et pas de 5 % imposés à toute écriture (options, raccourcis, fichier).
	Settings.editor_ui_scale = 3.0
	assert_near(Settings.editor_ui_scale, 1.5, 0.001, "trop grand -> 150 %")
	Settings.editor_ui_scale = 0.1
	assert_near(Settings.editor_ui_scale, 0.6, 0.001, "trop petit -> 60 %")
	Settings.editor_ui_scale = 0.83
	assert_near(Settings.editor_ui_scale, 0.85, 0.001, "arrondi au pas de 5 %")
	@warning_ignore("static_called_on_instance")
	assert_near(Settings.clamp_editor_ui_scale(NAN), 0.8, 0.001, "valeur non finie -> défaut")
	@warning_ignore("static_called_on_instance")
	assert_near(Settings.clamp_editor_ui_scale(INF), 0.8, 0.001)


func test_editor_ui_scale_signal() -> void:
	Settings.editor_ui_scale = 0.8
	var got := []
	var cb := func(v): got.append(v)
	Settings.editor_ui_scale_changed.connect(cb)
	Settings.editor_ui_scale = 1.1
	Settings.editor_ui_scale = 1.1
	Settings.editor_ui_scale = 1.12
	Settings.editor_ui_scale_changed.disconnect(cb)
	assert_eq(got.size(), 1, "un seul signal (valeurs égales après arrondi ignorées) : %s" % str(got))


func test_editor_ui_scale_saved_and_sanitized() -> void:
	Settings.editor_ui_scale = 1.25
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_near(float(cfg.get_value("interface", "editor_ui_scale")), 1.25, 0.001, "enregistré dans settings.cfg")
	Settings.editor_ui_scale = 0.8
	assert_true(Settings.load_from(TMP))
	assert_near(Settings.editor_ui_scale, 1.25, 0.001, "relu")
	# Valeurs piégées ou hors plage dans le fichier : ramenées dans la plage.
	for bad in [[9.0, 1.5], [-2.0, 0.6], [0.0, 0.6], ["énorme", 0.8], [Vector2(2, 2), 0.8], [0.7777, 0.8]]:
		Settings.editor_ui_scale = 0.8
		var c := ConfigFile.new()
		c.set_value("interface", "editor_ui_scale", bad[0])
		c.save(TMP)
		assert_true(Settings.load_from(TMP))
		assert_near(Settings.editor_ui_scale, float(bad[1]), 0.001, "fichier : %s" % str(bad[0]))
	# Clé absente (ancien fichier) : la taille courante reste.
	var old := ConfigFile.new()
	old.set_value("game", "language", "fr")
	old.save(TMP)
	Settings.editor_ui_scale = 0.9
	assert_true(Settings.load_from(TMP))
	assert_near(Settings.editor_ui_scale, 0.9, 0.001, "clé absente")


func test_labels_follow_language() -> void:
	Settings.language = "fr"
	assert_eq(Lang.t("REPRENDRE", "RESUME"), "REPRENDRE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("mouse:%d" % MOUSE_BUTTON_LEFT), "CLIC GAUCHE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_k(KEY_SPACE)), "ESPACE")
	Settings.language = "en"
	assert_eq(Lang.t("REPRENDRE", "RESUME"), "RESUME")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("mouse:%d" % MOUSE_BUTTON_LEFT), "LEFT CLICK")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_k(KEY_SPACE)), "SPACE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_k(KEY_R)), "R")
	Settings.using_pad = false
	assert_eq(Settings.action_label("interact"), "F")


# ------------------------------------------------------------------ manette : noms et invites

func test_pad_style_from_joy_name() -> void:
	assert_eq(PadNames.style_of("Xbox Series Controller"), PadNames.XBOX)
	assert_eq(PadNames.style_of("XInput Controller"), PadNames.XBOX)
	assert_eq(PadNames.style_of(""), PadNames.XBOX, "manette inconnue : noms Xbox")
	assert_eq(PadNames.style_of("PS4 Controller"), PadNames.PLAYSTATION)
	assert_eq(PadNames.style_of("Sony DualShock 4"), PadNames.PLAYSTATION)
	assert_eq(PadNames.style_of("PS5 Controller"), PadNames.PS5)
	assert_eq(PadNames.style_of("DualSense Wireless Controller"), PadNames.PS5)
	assert_true(PadNames.is_playstation(PadNames.PS5) and not PadNames.is_playstation(PadNames.XBOX))


func test_pad_button_names() -> void:
	Settings.language = "fr"
	var x := "joy:%d" % JOY_BUTTON_X
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(x, PadNames.XBOX), "X")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(x, PadNames.PLAYSTATION), "CARRÉ")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_A, PadNames.PLAYSTATION), "CROIX")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_DPAD_RIGHT, PadNames.PLAYSTATION), "FLÈCHE DROITE", "flèche : pas « croix »")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT, PadNames.XBOX), "RT")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT, PadNames.PLAYSTATION), "R2")
	Settings.language = "en"
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(x, PadNames.PLAYSTATION), "SQUARE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_B, PadNames.PS5), "CIRCLE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_BACK, PadNames.PS5), "CREATE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_BACK, PadNames.PLAYSTATION), "SHARE")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_LEFT_SHOULDER, PadNames.XBOX), "LB")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_RIGHT_STICK, PadNames.PLAYSTATION), "R3")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label("joy:%d" % JOY_BUTTON_DPAD_UP, PadNames.XBOX), "D-PAD UP")
	assert_eq(PadNames.button_label(JOY_BUTTON_START, PadNames.XBOX), "START")
	assert_eq(PadNames.button_label(JOY_BUTTON_START, PadNames.PLAYSTATION), "OPTIONS")
	# Chaque bouton affectable a un nom dans les deux styles et les deux langues.
	for lang in ["fr", "en"]:
		Settings.language = lang
		for b in JOY_BUTTON_SDL_MAX:
			for style in [PadNames.XBOX, PadNames.PLAYSTATION, PadNames.PS5]:
				assert_true(PadNames.button_label(b, style) != "", "bouton %d (%s, %s)" % [b, style, lang])


func test_prompt_label_follows_last_device() -> void:
	Settings.language = "fr"
	var key := _k(KEY_F)
	var pad := "joy:%d" % JOY_BUTTON_X
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label(key, pad, false), "F", "clavier : « Appuyer sur F »")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label(key, pad, true, PadNames.XBOX), "X", "Xbox : « Appuyer sur X »")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label(key, pad, true, PadNames.PLAYSTATION), "CARRÉ")
	Settings.language = "en"
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label(key, pad, true, PadNames.PLAYSTATION), "SQUARE", "« Press SQUARE »")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label(key, "", true), "F", "pas de bouton : la touche")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label("", pad, false), "X", "pas de touche : le bouton")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.prompt_label("", "", true), "?")
	assert_eq(Hud.bo1_prompt("[F] Buy M14 [500]", Settings.prompt_label(key, pad, true, PadNames.PLAYSTATION)),
			"Press SQUARE to buy M14 [Cost: 500]")


func test_last_device_switches_prompts() -> void:
	Settings.language = "en"
	Settings.using_pad = false
	var got := []
	var cb := func(p): got.append(p)
	Settings.input_device_changed.connect(cb)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	Settings.note_input(jb)
	assert_true(Settings.using_pad, "bouton de manette : invites manette")
	# Sans manette réellement branchée (tests) : noms Xbox.
	assert_eq(Settings.action_label("interact"), "X")
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.1
	var k := InputEventKey.new()
	k.physical_keycode = KEY_W
	k.pressed = true
	Settings.note_input(k)
	assert_false(Settings.using_pad, "touche : retour au clavier")
	Settings.note_input(drift)
	assert_false(Settings.using_pad, "stick qui dérive : ignoré")
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(0.5, 0)
	Settings.note_input(jb)
	Settings.note_input(mm)
	assert_true(Settings.using_pad, "souris à peine bougée : ignorée")
	mm.relative = Vector2(20, 0)
	Settings.note_input(mm)
	assert_false(Settings.using_pad, "souris : retour au clavier")
	assert_eq(Settings.action_label("interact"), "F")
	Settings.input_device_changed.disconnect(cb)
	assert_eq(got, [true, false, true, false], "un signal par changement : %s" % str(got))
	# Débranchement d'une manette (aucune branchée) : jamais d'erreur, clavier.
	Settings.note_input(jb)
	Settings._on_joy_connection_changed(0, false)
	assert_false(Settings.using_pad, "manette débranchée : invites clavier")
	Settings._on_joy_connection_changed(3, true)
	assert_false(Settings.using_pad)


# ------------------------------------------------------------------ manette : sticks

func test_stick_deadzone() -> void:
	assert_eq(PlayerInput.stick_deadzone(Vector2(0.1, 0.1), 0.2), Vector2.ZERO, "dans la zone morte")
	assert_eq(PlayerInput.stick_deadzone(Vector2.ZERO, 0.2), Vector2.ZERO)
	assert_near(PlayerInput.stick_deadzone(Vector2(0, 1), 0.2).y, 1.0, 0.0001, "à fond : 1")
	assert_near(PlayerInput.stick_deadzone(Vector2(0.6, 0), 0.2).x, 0.5, 0.0001, "remis à l'échelle")
	assert_near(PlayerInput.stick_deadzone(Vector2(-0.6, 0), 0.2).x, -0.5, 0.0001, "sens conservé")
	# Clavier (diagonale 1, 1) : longueur 1, comme avant.
	var diag := PlayerInput.stick_deadzone(Vector2(1, 1), 0.2)
	assert_near(diag.length(), 1.0, 0.0001)
	assert_near(diag.x, diag.y, 0.0001)
	# Zone morte radiale : la direction est gardée.
	var v := PlayerInput.stick_deadzone(Vector2(0.3, 0.4), 0.2)
	assert_near(v.normalized().dot(Vector2(0.6, 0.8)), 1.0, 0.0001)


func test_pad_look_is_framerate_independent() -> void:
	var stick := Vector2(0.7, -0.4)
	# Une seconde de vue à 30, 60 et 240 images par seconde : même rotation.
	var totals := []
	for fps in [30, 60, 240]:
		var sum := Vector2.ZERO
		for i in fps:
			sum += PlayerInput.pad_look_step(stick, 1.0, 1.0 / fps)
		totals.append(sum)
	assert_near(totals[0].x, totals[1].x, 0.0001)
	assert_near(totals[1].x, totals[2].x, 0.0001)
	assert_near(totals[0].y, totals[2].y, 0.0001)
	assert_eq(PlayerInput.pad_look_step(Vector2(0.1, 0.0), 1.0, 0.016), Vector2.ZERO, "zone morte : la vue ne dérive pas")
	var full := PlayerInput.pad_look_step(Vector2(1, 0), 1.0, 1.0)
	assert_near(full.x, PlayerInput.PAD_LOOK_SPEED.x, 0.0001, "à fond : vitesse maximale")
	assert_near(PlayerInput.pad_look_step(Vector2(1, 0), 2.0, 1.0).x, full.x * 2.0, 0.0001, "sensibilité multiplicatrice")
	# Courbe : à mi-course, moins de la moitié de la vitesse (précision).
	assert_true(PlayerInput.pad_look_step(Vector2(0.5, 0), 1.0, 1.0).x < full.x * 0.5)
	assert_true(PlayerInput.pad_look_step(Vector2(0, 1), 1.0, 1.0).y > 0.0, "stick vers le bas : la vue descend")


func test_brightness_gamma_lut() -> void:
	assert_near(WorldLook.gamma_curve(0.0, 1.4), 0.0)
	assert_near(WorldLook.gamma_curve(1.0, 1.4), 1.0)
	assert_true(WorldLook.gamma_curve(0.3, 1.4) > 0.3, "plus clair")
	assert_true(WorldLook.gamma_curve(0.3, 0.7) < 0.3, "plus sombre")
	var base := WorldLook.grade_lut()
	assert_true(WorldLook.grade_lut({"gamma": 1.0}) == base, "gamma 1 : table d'origine")
	var bright := WorldLook.grade_lut({"gamma": 1.3})
	assert_true(bright != base and bright == WorldLook.grade_lut({"gamma": 1.3}), "table éclaircie en cache")
	Settings.brightness = 1.0
	assert_true(WorldLook.map_lut({}) == base, "luminosité par défaut : rendu inchangé")


func test_render_scale_multiplies_preset() -> void:
	Settings.render_scale = 1.0
	assert_near(RenderQuality.scale_3d(RenderQuality.preset(Settings.Quality.LOW)), 0.85, 0.001, "défaut : préréglage seul")
	Settings.render_scale = 0.5
	assert_near(RenderQuality.scale_3d(RenderQuality.preset(Settings.Quality.MEDIUM)), 0.5)
	assert_near(RenderQuality.scale_3d(RenderQuality.preset(Settings.Quality.LOW)), 0.425)


# ------------------------------------------------------------------ personnage

func test_character_default_saved_and_reloaded() -> void:
	var fresh: Node = (Settings.get_script() as GDScript).new()
	assert_eq(fresh.character, CharacterDB.AUTO, "par défaut : automatique")
	fresh.free()
	Settings.character = "mercer"
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_eq(cfg.get_value("player", "character"), "mercer", "choix dans settings.cfg")
	Settings.character = CharacterDB.AUTO
	assert_true(Settings.load_from(TMP), "fichier relu")
	assert_eq(Settings.character, "mercer", "choix relu")


func test_character_invalid_file_values_become_auto() -> void:
	for bad in ["zorg", "", "../mercer", 42, ["orlov"], "MERCER"]:
		var cfg := ConfigFile.new()
		cfg.set_value("player", "character", bad)
		cfg.save(TMP)
		Settings.character = "orlov"
		assert_true(Settings.load_from(TMP))
		assert_eq(Settings.character, CharacterDB.AUTO, "valeur refusée : %s" % str(bad))
	# Fichier d'une version précédente, sans la clé : automatique.
	var old := ConfigFile.new()
	old.set_value("video", "fov", 80.0)
	old.save(TMP)
	Settings.character = CharacterDB.AUTO
	assert_true(Settings.load_from(TMP))
	assert_eq(Settings.character, CharacterDB.AUTO)


func test_character_berg_saved_and_reloaded() -> void:
	Settings.character = "berg"
	Settings.save_to(TMP)
	Settings.character = CharacterDB.AUTO
	assert_true(Settings.load_from(TMP), "fichier relu")
	assert_eq(Settings.character, "berg", "sixième personnage relu")


func test_character_jojo_saved_and_reloaded() -> void:
	Settings.character = "jojo"
	Settings.save_to(TMP)
	Settings.character = CharacterDB.AUTO
	assert_true(Settings.load_from(TMP), "fichier relu")
	assert_eq(Settings.character, "jojo", "septième personnage relu")


# ------------------------------------------------------------------ fenêtre

func test_window_mode_untouched_unless_fullscreen_differs() -> void:
	var DS := DisplayServer
	# Plein écran désactivé : une fenêtre agrandie, réduite ou normale reste ainsi.
	for m in [DS.WINDOW_MODE_WINDOWED, DS.WINDOW_MODE_MAXIMIZED, DS.WINDOW_MODE_MINIMIZED]:
		assert_eq(Settings.window_mode_for(false, m), -1, "fenêtre laissée (mode %d)" % m)
	assert_eq(Settings.window_mode_for(false, DS.WINDOW_MODE_FULLSCREEN), DS.WINDOW_MODE_WINDOWED)
	assert_eq(Settings.window_mode_for(false, DS.WINDOW_MODE_EXCLUSIVE_FULLSCREEN), DS.WINDOW_MODE_WINDOWED)
	# Plein écran activé : déjà plein écran (même exclusif), rien ne change.
	assert_eq(Settings.window_mode_for(true, DS.WINDOW_MODE_FULLSCREEN), -1)
	assert_eq(Settings.window_mode_for(true, DS.WINDOW_MODE_EXCLUSIVE_FULLSCREEN), -1)
	assert_eq(Settings.window_mode_for(true, DS.WINDOW_MODE_MAXIMIZED), DS.WINDOW_MODE_FULLSCREEN)
	assert_eq(Settings.window_mode_for(true, DS.WINDOW_MODE_WINDOWED), DS.WINDOW_MODE_FULLSCREEN)
