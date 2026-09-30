extends TestCase
## Réglages : touches réaffectables (conflits, cases, InputMap), options
## graphiques et de contrôle ajoutées, enregistrement puis rechargement.
## Tout se fait dans un fichier temporaire : les réglages du joueur ne sont
## jamais touchés, et l'état de Settings est restauré après chaque test.

const TMP := "user://settings_unittest.cfg"
const SAVED_KEYS := ["bindings", "render_scale", "max_fps", "brightness", "ads_sensitivity",
	"mouse_sensitivity", "invert_y", "language", "fov", "film_grain", "quality", "editor_ui_scale"]

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


func test_defaults_match_previous_bindings() -> void:
	var d := Settings.default_bindings()
	assert_eq(d.size(), Settings.REBINDABLE.size())
	assert_eq(d.crouch, ["key:%d" % KEY_CTRL, "key:%d" % KEY_C])
	assert_eq(d.fire, ["mouse:%d" % MOUSE_BUTTON_LEFT])
	assert_eq(d.aim, ["mouse:%d" % MOUSE_BUTTON_RIGHT])
	assert_true(_has_key("move_forward", KEY_W), "Z/W avance")
	assert_true(_has_key("interact", KEY_F) and _has_key("interact", KEY_E), "F et E interagissent")
	assert_true(_has_mouse("fire", MOUSE_BUTTON_LEFT), "clic gauche tire")
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_UP), "molette : changement d'arme")
	assert_true(_has_key("pause", KEY_ESCAPE), "Échap : pause (fixe)")
	for a in Settings.REBINDABLE:
		assert_true((d[a] as Array).size() <= Settings.MAX_KEYS, "%s : deux touches au plus" % a)


func test_codes_roundtrip() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_T
	k.pressed = true
	assert_eq(Settings.code_from_event(k), "key:%d" % KEY_T)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	assert_eq(Settings.code_from_event(esc), "", "Échap : jamais affectable")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	assert_eq(Settings.code_from_event(wheel), "", "molette exclue")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	assert_eq(Settings.code_from_event(mb), "mouse:%d" % MOUSE_BUTTON_XBUTTON1)
	assert_true(Settings.event_from_code("key:%d" % KEY_T) is InputEventKey)
	assert_true(Settings.event_from_code("mouse:%d" % MOUSE_BUTTON_MIDDLE) is InputEventMouseButton)
	for bad in ["", "key:", "key:abc", "mouse:4", "pad:1", "key:%d" % KEY_ESCAPE]:
		assert_true(Settings.event_from_code(bad) == null, "code invalide « %s »" % bad)


func test_rebind_updates_input_map() -> void:
	var taken := Settings.bind("reload", 0, "key:%d" % KEY_T)
	assert_eq(taken, "")
	assert_eq(Settings.bindings.reload, ["key:%d" % KEY_T])
	assert_true(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "R -> T dans l'InputMap")
	# Deuxième case, puis bouton de souris.
	Settings.bind("reload", 1, "mouse:%d" % MOUSE_BUTTON_XBUTTON2)
	assert_eq(Settings.bindings.reload, ["key:%d" % KEY_T, "mouse:%d" % MOUSE_BUTTON_XBUTTON2])
	assert_true(_has_mouse("reload", MOUSE_BUTTON_XBUTTON2), "bouton 5 de la souris")


func test_conflict_removes_key_from_other_action() -> void:
	var taken := Settings.bind("reload", 0, "key:%d" % KEY_G)
	assert_eq(taken, "grenade", "G retiré de GRENADE")
	assert_eq(Settings.bindings.grenade, [])
	assert_false(_has_key("grenade", KEY_G), "plus de G sur la grenade")
	assert_true(_has_key("reload", KEY_G))
	# Tir sur une touche : le clic gauche reste libre de toute action.
	assert_eq(Settings.bind("aim", 1, "mouse:%d" % MOUSE_BUTTON_LEFT), "fire")
	assert_false(_has_mouse("fire", MOUSE_BUTTON_LEFT))


func test_same_action_swaps_slots() -> void:
	# Ctrl, C : C mis en première case -> C, Ctrl.
	Settings.bind("crouch", 0, "key:%d" % KEY_C)
	assert_eq(Settings.bindings.crouch, ["key:%d" % KEY_C, "key:%d" % KEY_CTRL])
	Settings.clear_binding("crouch", 0)
	assert_eq(Settings.bindings.crouch, ["key:%d" % KEY_CTRL], "case vidée, la suivante remonte")
	assert_false(_has_key("crouch", KEY_C))


func test_reset_bindings() -> void:
	Settings.bind("jump", 0, "key:%d" % KEY_W)
	assert_false(_has_key("move_forward", KEY_W))
	Settings.reset_bindings()
	assert_eq(Settings.bindings, Settings.default_bindings())
	assert_true(_has_key("move_forward", KEY_W) and _has_key("jump", KEY_SPACE))


func test_save_and_reload() -> void:
	Settings.bind("reload", 0, "key:%d" % KEY_T)
	Settings.bind("melee", 1, "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	Settings.render_scale = 0.7
	Settings.max_fps = 144
	Settings.brightness = 1.25
	Settings.ads_sensitivity = 0.6
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_eq(Array(cfg.get_value("bindings", "reload")), ["key:%d" % KEY_T], "touches dans settings.cfg")
	# Retour aux valeurs d'origine, puis rechargement du fichier.
	Settings.reset_bindings()
	Settings.render_scale = 1.0
	Settings.max_fps = 0
	Settings.brightness = 1.0
	Settings.ads_sensitivity = 1.0
	assert_true(Settings.load_from(TMP), "fichier relu")
	Settings.apply_bindings()
	assert_eq(Settings.bindings.reload, ["key:%d" % KEY_T])
	assert_eq(Settings.bindings.melee, ["key:%d" % KEY_V, "mouse:%d" % MOUSE_BUTTON_MIDDLE])
	assert_true(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "InputMap rechargée")
	assert_near(Settings.render_scale, 0.7)
	assert_eq(Settings.max_fps, 144)
	assert_near(Settings.brightness, 1.25)
	assert_near(Settings.ads_sensitivity, 0.6)


func test_invalid_file_values_are_sanitized() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "render_scale", 3.0)
	cfg.set_value("video", "max_fps", 77)
	cfg.set_value("video", "brightness", -1.0)
	# Touche en double, code invalide, trois touches ; « tactical » absent du
	# fichier : sa touche d'origine Q, déjà prise par « jump », n'est pas remise.
	cfg.set_value("bindings", "jump", PackedStringArray(["key:%d" % KEY_Q, "bogus", "key:%d" % KEY_Q]))
	cfg.set_value("bindings", "reload", PackedStringArray(["key:%d" % KEY_R, "key:%d" % KEY_T, "key:%d" % KEY_Y]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	assert_near(Settings.render_scale, Settings.RENDER_SCALE_RANGE.y)
	assert_eq(Settings.max_fps, 0, "limite inconnue -> illimitée")
	assert_near(Settings.brightness, Settings.BRIGHTNESS_RANGE.x)
	assert_eq(Settings.bindings.jump, ["key:%d" % KEY_Q])
	assert_eq(Settings.bindings.reload, ["key:%d" % KEY_R, "key:%d" % KEY_T])
	assert_eq(Settings.bindings.tactical, [], "Q déjà pris")
	assert_eq(Settings.bindings.grenade, ["key:%d" % KEY_G], "action absente : touche d'origine")


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
	assert_near(Settings.clamp_editor_ui_scale(NAN), 0.8, 0.001, "valeur non finie -> défaut")
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
	assert_eq(Settings.code_label("mouse:%d" % MOUSE_BUTTON_LEFT), "CLIC GAUCHE")
	assert_eq(Settings.code_label("key:%d" % KEY_SPACE), "ESPACE")
	Settings.language = "en"
	assert_eq(Lang.t("REPRENDRE", "RESUME"), "RESUME")
	assert_eq(Settings.code_label("mouse:%d" % MOUSE_BUTTON_LEFT), "LEFT CLICK")
	assert_eq(Settings.code_label("key:%d" % KEY_SPACE), "SPACE")
	assert_eq(Settings.code_label("key:%d" % KEY_R), "R")
	assert_eq(Settings.action_label("interact"), "F")


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
