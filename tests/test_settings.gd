extends TestCase
## Réglages : touches et boutons de manette réaffectables (deux commandes par
## action et par colonne, molette, commande partagée entre actions, InputMap, anciens fichiers), noms des
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
	# Événements injectés par un test précédent (Input.parse_input_event) et
	# pas encore lus : appliqués maintenant, avant la sauvegarde, et non au
	# milieu de ce test (indépendance de l'ordre des tests).
	Input.flush_buffered_events()
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


func _w(button: MouseButton) -> String:
	return "mouse:%d" % button


## Cran de molette injecté (appui puis relâche dans la même image, comme le
## pilote de la souris), hors image physique comme les événements du
## système (lus au début de l'image suivante).
func _wheel_notch(button: MouseButton) -> void:
	await host.get_tree().process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.factor = 1.0
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)


## Appui ou relâche injecté hors image physique, puis attente de sa lecture.
## Input met les événements en mémoire tampon et ne les lit qu'au début de
## l'itération suivante du moteur ; or, après une image lente (machine
## chargée, série complète), le moteur rattrape plusieurs images physiques
## dans la MÊME itération : compter des images physiques juste après
## parse_input_event peut alors se faire sans que l'événement soit lu (appui
## et relâche lus ensemble ensuite : action « maintenue » une seule image).
## Après process_frame, toute image physique suivante appartient à une
## itération qui a déjà lu l'événement.
func _inject(ev: InputEvent) -> void:
	await host.get_tree().process_frame
	Input.parse_input_event(ev)
	await host.get_tree().process_frame


func test_one_key_per_action_by_default() -> void:
	@warning_ignore("static_called_on_instance")
	var d := Settings.default_bindings()
	assert_eq(d.size(), Settings.REBINDABLE.size())
	assert_eq(Settings.SLOTS_PER_COLUMN, 2, "deux cases par colonne")
	assert_eq(d.crouch, [_k(KEY_C)], "S'ACCROUPIR : C seulement, deuxième case vide")
	assert_eq(d.interact, [_k(KEY_F)], "INTERAGIR : F seulement (l'invite dit F)")
	assert_eq(d.switch_weapon, [_k(KEY_1)], "CHANGER D'ARME : 1 (+ molette)")
	assert_eq(d.fire, ["mouse:%d" % MOUSE_BUTTON_LEFT])
	assert_eq(d.aim, ["mouse:%d" % MOUSE_BUTTON_RIGHT])
	assert_eq(Settings.binding("melee", false, 1), "", "deuxième case vide")
	assert_eq(Settings.binding("melee", true, 1), "", "deuxième case manette vide")
	assert_true(_has_key("move_forward", KEY_W), "Z/W avance")
	assert_true(_has_key("interact", KEY_F) and not _has_key("interact", KEY_E), "F interagit, E ne fait plus rien")
	assert_false(_has_key("crouch", KEY_CTRL), "Ctrl libre")
	assert_false(_has_key("switch_weapon", KEY_2), "2 libre")
	assert_true(_has_mouse("fire", MOUSE_BUTTON_LEFT), "clic gauche tire")
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_UP), "molette : changement d'arme")
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN))
	assert_true(_has_key("pause", KEY_ESCAPE), "Échap : pause (fixe)")
	# Une seule commande d'origine par action : jamais deux actions sur la même.
	var seen := {}
	for a in Settings.REBINDABLE:
		assert_true(d[a] is Array and d[a].size() == 1, "%s : une touche" % a)
		assert_false(seen.has(d[a][0]), "%s : touche unique" % a)
		seen[d[a][0]] = true


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
	for a in expect:
		assert_eq(p[a], [expect[a]], "%s : un bouton, deuxième case vide" % a)
	var seen := {}
	for a in Settings.REBINDABLE:
		assert_eq(p[a].size(), 1)
		assert_false(seen.has(p[a][0]), "%s : bouton unique" % a)
		seen[p[a][0]] = true
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
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_from_event(mb), "mouse:%d" % MOUSE_BUTTON_XBUTTON1)
	@warning_ignore("static_called_on_instance")
	assert_true(Settings.event_from_code(_k(KEY_T)) is InputEventKey)
	@warning_ignore("static_called_on_instance")
	assert_true(Settings.event_from_code("mouse:%d" % MOUSE_BUTTON_MIDDLE) is InputEventMouseButton)
	for bad in ["", "key:", "key:abc", "mouse:0", "mouse:10", "mouse:-4", "pad:1", _k(KEY_ESCAPE)]:
		@warning_ignore("static_called_on_instance")
		assert_true(Settings.event_from_code(bad) == null, "code invalide « %s »" % bad)


func test_wheel_codes_roundtrip_and_names() -> void:
	# Chaque cran de molette s'affecte comme un bouton, aller-retour exact.
	for b in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var ev := InputEventMouseButton.new()
		ev.button_index = b
		ev.pressed = true
		@warning_ignore("static_called_on_instance")
		var code := Settings.code_from_event(ev)
		assert_eq(code, _w(b), "cran %d affectable" % b)
		@warning_ignore("static_called_on_instance")
		var back := Settings.event_from_code(code) as InputEventMouseButton
		assert_true(back != null and back.button_index == b, "cran %d relu" % b)
		@warning_ignore("static_called_on_instance")
		assert_true(Settings.is_wheel_code(code))
	@warning_ignore("static_called_on_instance")
	assert_false(Settings.is_wheel_code(_w(MOUSE_BUTTON_MIDDLE)), "clic molette : un bouton, pas un cran")
	Settings.language = "fr"
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_w(MOUSE_BUTTON_WHEEL_DOWN)), "MOLETTE BAS")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_w(MOUSE_BUTTON_WHEEL_UP)), "MOLETTE HAUT")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_w(MOUSE_BUTTON_WHEEL_LEFT)), "MOLETTE GAUCHE")
	Settings.language = "en"
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_w(MOUSE_BUTTON_WHEEL_DOWN)), "WHEEL DOWN")
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.code_label(_w(MOUSE_BUTTON_WHEEL_RIGHT)), "WHEEL RIGHT")
	# Un cran est une touche : jamais dans la colonne manette.
	@warning_ignore("static_called_on_instance")
	assert_false(Settings.is_pad_code(_w(MOUSE_BUTTON_WHEEL_DOWN)))


func test_two_keys_per_action() -> void:
	# L'exemple du joueur : couteau sur V ET sur molette bas.
	assert_eq(Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1), [], "molette bas : aucune autre action ne l'a")
	assert_eq(Settings.bindings.melee, [_k(KEY_V), _w(MOUSE_BUTTON_WHEEL_DOWN)])
	assert_true(_has_key("melee", KEY_V) and _has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN), "V et molette bas dans l'InputMap")
	assert_eq(Settings.action_label("melee"), "V", "invite : la première")
	assert_eq(Settings.binding("melee", false, 1), _w(MOUSE_BUTTON_WHEEL_DOWN))
	# Deuxième bouton de manette, sans toucher au premier.
	Settings.bind("melee", "joy:%d" % JOY_BUTTON_DPAD_DOWN, 1)
	assert_eq(Settings.pad_bindings.melee, ["joy:%d" % JOY_BUTTON_RIGHT_STICK, "joy:%d" % JOY_BUTTON_DPAD_DOWN])
	assert_true(_has_pad_button("melee", JOY_BUTTON_RIGHT_STICK) and _has_pad_button("melee", JOY_BUTTON_DPAD_DOWN))
	# Remplacer une case : seule celle-là change.
	Settings.bind("melee", _k(KEY_B), 1)
	assert_eq(Settings.bindings.melee, [_k(KEY_V), _k(KEY_B)])
	assert_false(_has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN), "molette bas libérée")
	Settings.bind("melee", _k(KEY_N), 0)
	assert_eq(Settings.bindings.melee, [_k(KEY_N), _k(KEY_B)])
	assert_false(_has_key("melee", KEY_V))
	# Case 2 alors que la première est vide : en première case.
	Settings.clear_binding("reload")
	Settings.bind("reload", _k(KEY_T), 1)
	assert_eq(Settings.bindings.reload, [_k(KEY_T)])
	# Case hors limites : ramenée à la dernière.
	Settings.bind("reload", _k(KEY_Y), 7)
	assert_eq(Settings.bindings.reload, [_k(KEY_T), _k(KEY_Y)])


func test_bind_to_other_slot_of_same_action_moves_it() -> void:
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	# V dans la deuxième case : les deux commandes échangent leur place.
	assert_eq(Settings.bind("melee", _k(KEY_V), 1), [], "pas de partage avec soi-même")
	assert_eq(Settings.bindings.melee, [_w(MOUSE_BUTTON_WHEEL_DOWN), _k(KEY_V)])
	assert_eq(Settings.action_label("melee"), "MOLETTE BAS" if Settings.language == "fr" else "WHEEL DOWN")
	# Même case : rien ne change.
	Settings.bind("melee", _k(KEY_V), 1)
	assert_eq(Settings.bindings.melee, [_w(MOUSE_BUTTON_WHEEL_DOWN), _k(KEY_V)])
	# Seule commande, mise en case 2 : reste unique, en première case.
	Settings.bind("jump", _k(KEY_SPACE), 1)
	assert_eq(Settings.bindings.jump, [_k(KEY_SPACE)])


func test_shared_with_second_slot() -> void:
	Settings.bind("melee", _k(KEY_B), 1)
	# B aussi sur RECHARGER : gardée dans la deuxième case du couteau.
	assert_eq(Settings.bind("reload", _k(KEY_B), 1), ["melee"])
	assert_eq(Settings.bindings.melee, [_k(KEY_V), _k(KEY_B)])
	assert_eq(Settings.bindings.reload, [_k(KEY_R), _k(KEY_B)])
	assert_true(_has_key("melee", KEY_B) and _has_key("reload", KEY_B), "B dans l'InputMap des deux actions")
	# V (première case du couteau) aussi sur RECHARGER : le couteau la garde.
	assert_eq(Settings.bind("reload", _k(KEY_V), 0), ["melee"])
	assert_eq(Settings.bindings.melee, [_k(KEY_V), _k(KEY_B)], "le couteau garde V et B")
	assert_eq(Settings.bindings.reload, [_k(KEY_V), _k(KEY_B)], "R remplacé par V")
	assert_false(_has_key("reload", KEY_R))
	assert_eq(Settings.action_label("melee"), "V", "invite du couteau : toujours V")
	assert_eq(Settings.action_label("reload"), "V", "invite de RECHARGER : V")
	# Colonne manette : même règle, case par case.
	assert_eq(Settings.bind("jump", "joy:%d" % JOY_BUTTON_Y, 1), ["switch_weapon"])
	assert_eq(Settings.pad_bindings.switch_weapon, ["joy:%d" % JOY_BUTTON_Y], "Y reste sur CHANGER D'ARME")
	assert_eq(Settings.pad_bindings.jump, ["joy:%d" % JOY_BUTTON_A, "joy:%d" % JOY_BUTTON_Y])
	# Effacer sur une ligne ne touche pas l'autre.
	Settings.clear_binding("reload", false, 1)
	assert_eq(Settings.bindings.melee, [_k(KEY_V), _k(KEY_B)])
	assert_eq(Settings.shared_with("melee", _k(KEY_B)), [], "B n'est plus partagée")
	assert_eq(Settings.shared_with("melee", _k(KEY_V)), ["reload"])


func test_shared_with_lists_other_actions_in_screen_order() -> void:
	Settings.bind("reload", _k(KEY_F), 1)
	Settings.bind("melee", _k(KEY_F), 1)
	assert_eq(Settings.shared_with("interact", _k(KEY_F)), ["reload", "melee"], "ordre de l'écran")
	assert_eq(Settings.shared_with("reload", _k(KEY_F)), ["interact", "melee"])
	assert_eq(Settings.shared_with("reload", ""), [], "case vide")
	assert_eq(Settings.shared_with("reload", _k(KEY_R)), [], "R : seulement RECHARGER")
	# Même code dans l'autre colonne : jamais confondu.
	@warning_ignore("static_called_on_instance")
	var shared := Settings.codes_shared({"jump": [_k(KEY_SPACE)]}, {"crouch": ["joy:0"], "jump": ["joy:0"]}, "jump", "joy:0")
	assert_eq(shared, ["crouch"])
	# Mention de la case (écran COMMANDES).
	var lang: String = Settings.language
	Settings.language = "fr"
	assert_eq(MenuBindRow.shared_label([]), "")
	assert_eq(MenuBindRow.shared_label(["COUTEAU"]), "AUSSI : COUTEAU")
	assert_eq(MenuBindRow.shared_label(["COUTEAU", "RECHARGER"]), "AUSSI : COUTEAU +1")
	Settings.language = "en"
	assert_eq(MenuBindRow.shared_label(["KNIFE"]), "ALSO: KNIFE")
	Settings.language = lang


## Le même évènement (une touche, un bouton de manette) déclenche chaque
## action qui l'a, lu par PlayerInput à l'image physique comme Player.
func test_shared_key_triggers_every_action() -> void:
	Settings.bind("reload", _k(KEY_F), 1)
	Settings.bind("melee", _k(KEY_F), 1)
	Settings.bind("sprint", "joy:%d" % JOY_BUTTON_A, 1)
	var tree := host.get_tree()
	var counts := {"interact": 0, "reload": 0, "melee": 0, "jump": 0, "sprint_frames": 0}
	var inp := PlayerInput.new()
	var read := func():
		inp.read_devices(1.0 / 60.0)
		counts.interact += int(inp.interact_pressed)
		counts.reload += int(inp.reload)
		counts.melee += int(inp.melee)
		counts.jump += int(inp.jump)
		counts.sprint_frames += int(inp.sprint)
		inp.clear_edges()
	tree.physics_frame.connect(read)
	# Chaque événement passe par _inject : lu par Input AVANT les images
	# physiques comptées (sinon, machine chargée, appui et relâche peuvent
	# être lus ensemble après coup : sprint « maintenu » une seule image).
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	await _inject(key)
	for i in 3:
		await tree.physics_frame
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	await _inject(up)
	for i in 3:
		await tree.physics_frame
	assert_eq(counts.interact, 1, "F : INTERAGIR une fois")
	assert_eq(counts.reload, 1, "F : RECHARGER une fois")
	assert_eq(counts.melee, 1, "F : COUTEAU une fois")
	# Manette : A saute ET sprinte (maintenu tant que A est enfoncé).
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	await _inject(a)
	for i in 3:
		await tree.physics_frame
	var held_frames: int = counts.sprint_frames
	var a_up := a.duplicate() as InputEventJoypadButton
	a_up.pressed = false
	await _inject(a_up)
	for i in 3:
		await tree.physics_frame
	tree.physics_frame.disconnect(read)
	assert_eq(counts.jump, 1, "A : un saut")
	assert_true(held_frames >= 3, "A : sprint maintenu (%d images)" % held_frames)
	assert_false(inp.sprint, "A relâché : plus de sprint")
	Settings.using_pad = false


func test_shared_reload_and_use_prefers_use_near_an_object() -> void:
	# Même appui pour RECHARGER et INTERAGIR : devant un objet, l'achat
	# l'emporte (BO1 console) ; ailleurs, l'arme est rechargée.
	assert_true(WeaponController.use_takes_press(true, true), "objet visé : pas de rechargement")
	assert_false(WeaponController.use_takes_press(true, false), "rien à utiliser : rechargement")
	assert_false(WeaponController.use_takes_press(false, true), "touche de rechargement seule : rechargement")


func test_clear_each_slot() -> void:
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	Settings.clear_binding("melee", false, 1)
	assert_eq(Settings.bindings.melee, [_k(KEY_V)], "deuxième case effacée")
	assert_false(_has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN))
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN), "la molette bas change de nouveau d'arme")
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	Settings.clear_binding("melee", false, 0)
	assert_eq(Settings.bindings.melee, [_w(MOUSE_BUTTON_WHEEL_DOWN)], "première effacée : la deuxième remonte")
	Settings.clear_binding("melee", false, 1)
	assert_eq(Settings.bindings.melee, [_w(MOUSE_BUTTON_WHEEL_DOWN)], "case déjà vide : rien")
	Settings.bind("melee", "joy:%d" % JOY_BUTTON_DPAD_UP, 1)
	Settings.clear_binding("melee", true, 0)
	assert_eq(Settings.pad_bindings.melee, ["joy:%d" % JOY_BUTTON_DPAD_UP])
	assert_false(_has_pad_button("melee", JOY_BUTTON_RIGHT_STICK))
	# Reset : une seule commande d'origine, deuxièmes cases vides.
	Settings.reset_bindings()
	assert_eq(Settings.bindings.melee, [_k(KEY_V)])
	assert_eq(Settings.pad_bindings.melee, ["joy:%d" % JOY_BUTTON_RIGHT_STICK])
	assert_false(_has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN))


func test_wheel_notch_bound_no_longer_switches_weapon() -> void:
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.wheel_switch_events(Settings.default_bindings()).size(), 2, "par défaut : haut et bas")
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	assert_false(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN), "molette bas : couteau, plus changement d'arme")
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_UP), "molette haut : change toujours d'arme")
	assert_true(_has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN))
	# Molette haut sur CHANGER D'ARME : affectée, une seule fois dans l'InputMap.
	Settings.bind("switch_weapon", _w(MOUSE_BUTTON_WHEEL_UP), 1)
	var n := 0
	for ev in InputMap.action_get_events("switch_weapon"):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			n += 1
	assert_eq(n, 1, "molette haut une seule fois")
	# Molette gauche / droite : jamais de changement d'arme d'origine.
	assert_false(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_LEFT))
	# Colonne manette : n'y change rien.
	Settings.reset_bindings()
	assert_true(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN), "reset : la molette change d'arme")


func test_wheel_bound_actions_fire_once_per_notch() -> void:
	# Couteau sur molette bas : un cran = un coup, lu par PlayerInput à
	# l'image physique (comme Player), et plus de changement d'arme.
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	Settings.bind("grenade", _w(MOUSE_BUTTON_WHEEL_LEFT))
	var tree := host.get_tree()
	var counts := {"melee": 0, "switch": 0, "grenade": 0, "grenade_frames": 0}
	var inp := PlayerInput.new()
	var read := func():
		inp.read_devices(1.0 / 60.0)
		counts.melee += int(inp.melee)
		counts.switch += int(inp.switch_weapon)
		counts.grenade_frames += int(inp.grenade)
		inp.clear_edges()
	tree.physics_frame.connect(read)
	for notch in 3:
		await tree.physics_frame
		await _wheel_notch(MOUSE_BUTTON_WHEEL_DOWN)
		for i in 4:
			await tree.physics_frame
	assert_eq(counts.melee, 3, "un coup de couteau par cran (%d)" % counts.melee)
	assert_eq(counts.switch, 0, "molette bas : plus de changement d'arme")
	# Molette haut : change toujours d'arme, une fois par cran.
	await _wheel_notch(MOUSE_BUTTON_WHEEL_UP)
	for i in 4:
		await tree.physics_frame
	assert_eq(counts.switch, 1, "molette haut : un changement d'arme")
	assert_eq(counts.melee, 3)
	# Action maintenue (grenade) sur un cran : un appui d'une seule image
	# (dégoupillée puis lancée par ThrowController).
	await _wheel_notch(MOUSE_BUTTON_WHEEL_LEFT)
	for i in 4:
		await tree.physics_frame
	assert_eq(counts.grenade_frames, 1, "grenade : appui d'une image (%d)" % counts.grenade_frames)
	tree.physics_frame.disconnect(read)


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
	assert_eq(taken, [])
	assert_eq(Settings.bindings.reload, [_k(KEY_T)], "première case : T remplace R")
	assert_true(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "R -> T dans l'InputMap")
	assert_eq(Settings.pad_bindings.reload, ["joy:%d" % JOY_BUTTON_RIGHT_SHOULDER], "le bouton de manette reste")
	Settings.bind("reload", "mouse:%d" % MOUSE_BUTTON_XBUTTON2)
	assert_eq(Settings.bindings.reload, ["mouse:%d" % MOUSE_BUTTON_XBUTTON2])
	assert_true(_has_mouse("reload", MOUSE_BUTTON_XBUTTON2) and not _has_key("reload", KEY_T), "bouton 5 de la souris")
	# Colonne manette : ne touche pas à la touche.
	Settings.bind("reload", "joy:%d" % JOY_BUTTON_DPAD_UP)
	assert_eq(Settings.pad_bindings.reload, ["joy:%d" % JOY_BUTTON_DPAD_UP])
	assert_eq(Settings.bindings.reload, ["mouse:%d" % MOUSE_BUTTON_XBUTTON2])
	assert_true(_has_pad_button("reload", JOY_BUTTON_DPAD_UP) and not _has_pad_button("reload", JOY_BUTTON_RIGHT_SHOULDER))
	assert_eq(Settings.bind("reload", "joy:bogus"), [], "code invalide refusé")
	assert_eq(Settings.pad_bindings.reload, ["joy:%d" % JOY_BUTTON_DPAD_UP])


func test_used_key_is_kept_on_both_actions() -> void:
	var others := Settings.bind("reload", _k(KEY_G))
	assert_eq(others, ["grenade"], "G partagée avec GRENADE")
	assert_eq(Settings.bindings.grenade, [_k(KEY_G)], "la grenade garde G")
	assert_eq(Settings.bindings.reload, [_k(KEY_G)])
	assert_true(_has_key("grenade", KEY_G) and _has_key("reload", KEY_G), "G dans l'InputMap des deux actions")
	assert_eq(Settings.pad_bindings.grenade, ["joy:%d" % JOY_BUTTON_LEFT_SHOULDER], "la manette n'est pas touchée")
	assert_eq(Settings.action_label("grenade"), "G", "invite de la grenade : G")
	assert_eq(Settings.action_label("reload"), "G", "invite de RECHARGER : G")
	# Clic gauche aussi sur VISER : TIRER le garde.
	assert_eq(Settings.bind("aim", "mouse:%d" % MOUSE_BUTTON_LEFT), ["fire"])
	assert_true(_has_mouse("fire", MOUSE_BUTTON_LEFT) and _has_mouse("aim", MOUSE_BUTTON_LEFT))
	# Une troisième action sur G : les deux premières la gardent.
	assert_eq(Settings.bind("melee", _k(KEY_G), 1), ["reload", "grenade"])
	assert_true(_has_key("grenade", KEY_G) and _has_key("reload", KEY_G) and _has_key("melee", KEY_G))


func test_pad_shared_stays_in_pad_column() -> void:
	# Y (changer d'arme) aussi sur RECHARGER, côté manette seulement.
	var others := Settings.bind("reload", "joy:%d" % JOY_BUTTON_Y)
	assert_eq(others, ["switch_weapon"])
	assert_eq(Settings.pad_bindings.switch_weapon, ["joy:%d" % JOY_BUTTON_Y], "CHANGER D'ARME garde Y")
	assert_eq(Settings.bindings.switch_weapon, [_k(KEY_1)], "la touche 1 reste")
	assert_true(_has_pad_button("switch_weapon", JOY_BUTTON_Y) and _has_pad_button("reload", JOY_BUTTON_Y))
	assert_eq(Settings.shared_with("reload", _k(KEY_R)), [], "colonne des touches : rien de partagé")
	# Gâchette : même règle.
	assert_eq(Settings.bind("melee", "joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT), ["fire"])
	assert_eq(Settings.pad_bindings.fire, ["joyaxis:%d:1" % JOY_AXIS_TRIGGER_RIGHT])
	assert_true(_has_pad_axis("melee", JOY_AXIS_TRIGGER_RIGHT, 1.0) and _has_pad_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0))
	assert_true(_has_mouse("fire", MOUSE_BUTTON_LEFT), "le clic gauche tire toujours")


func test_shared_wheel_notch() -> void:
	# Molette bas sur COUTEAU et GRENADE : les deux l'ont, plus de changement
	# d'arme dans ce sens ; un cran déclenche les deux.
	assert_eq(Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1), [])
	assert_eq(Settings.bind("grenade", _w(MOUSE_BUTTON_WHEEL_DOWN), 1), ["melee"])
	assert_true(_has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN) and _has_mouse("grenade", MOUSE_BUTTON_WHEEL_DOWN))
	assert_false(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN), "molette bas : plus de changement d'arme")
	# Aussi sur CHANGER D'ARME : une seule fois dans son InputMap.
	assert_eq(Settings.bind("switch_weapon", _w(MOUSE_BUTTON_WHEEL_DOWN), 1), ["melee", "grenade"])
	var n := 0
	for ev in InputMap.action_get_events("switch_weapon"):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			n += 1
	assert_eq(n, 1, "molette bas une seule fois sur CHANGER D'ARME")
	var tree := host.get_tree()
	var counts := {"melee": 0, "switch": 0, "grenade_frames": 0}
	var inp := PlayerInput.new()
	var read := func():
		inp.read_devices(1.0 / 60.0)
		counts.melee += int(inp.melee)
		counts.switch += int(inp.switch_weapon)
		counts.grenade_frames += int(inp.grenade)
		inp.clear_edges()
	tree.physics_frame.connect(read)
	await tree.physics_frame
	await _wheel_notch(MOUSE_BUTTON_WHEEL_DOWN)
	for i in 4:
		await tree.physics_frame
	tree.physics_frame.disconnect(read)
	assert_eq(counts.melee, 1, "un cran : un coup de couteau")
	assert_eq(counts.switch, 1, "un cran : un changement d'arme")
	assert_eq(counts.grenade_frames, 1, "un cran : grenade une image")


func test_clear_binding_per_column() -> void:
	Settings.clear_binding("crouch")
	assert_eq(Settings.bindings.crouch, [])
	assert_false(_has_key("crouch", KEY_C))
	assert_true(_has_pad_button("crouch", JOY_BUTTON_B), "B accroupit toujours")
	Settings.clear_binding("crouch", true)
	assert_eq(Settings.pad_bindings.crouch, [])
	assert_true(InputMap.action_get_events("crouch").is_empty())
	assert_eq(Settings.action_label("crouch"), "?", "aucune commande : « ? »")


func test_reset_bindings() -> void:
	Settings.bind("jump", _k(KEY_W))
	Settings.bind("jump", "joy:%d" % JOY_BUTTON_X)
	Settings.bind("jump", _k(KEY_J), 1)
	Settings.bind("jump", "joy:%d" % JOY_BUTTON_DPAD_LEFT, 1)
	assert_true(_has_key("move_forward", KEY_W) and _has_key("jump", KEY_W), "W partagée")
	assert_eq(Settings.shared_with("jump", "joy:%d" % JOY_BUTTON_X), ["interact"])
	Settings.reset_bindings()
	assert_eq(Settings.shared_with("jump", _k(KEY_SPACE)), [], "par défaut : aucun partage")
	for a in Settings.REBINDABLE:
		for pad in [false, true]:
			for c in Settings.bindings_of(a, pad):
				assert_eq(Settings.shared_with(a, c), [], "par défaut : %s seule sur %s" % [c, a])
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.bindings, Settings.default_bindings())
	@warning_ignore("static_called_on_instance")
	assert_eq(Settings.pad_bindings, Settings.default_pad_bindings(), "colonne manette rétablie aussi")
	assert_eq(Settings.binding("jump", false, 1), "", "deuxième case vide")
	assert_eq(Settings.binding("jump", true, 1), "")
	assert_true(_has_key("move_forward", KEY_W) and _has_key("jump", KEY_SPACE) and not _has_key("jump", KEY_J))
	assert_true(_has_pad_button("interact", JOY_BUTTON_X) and _has_pad_button("jump", JOY_BUTTON_A))
	assert_false(_has_pad_button("jump", JOY_BUTTON_DPAD_LEFT))


func test_save_and_reload() -> void:
	Settings.bind("reload", _k(KEY_T))
	Settings.bind("melee", "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	Settings.bind("reload", "joy:%d" % JOY_BUTTON_DPAD_DOWN)
	Settings.bind("reload", "joy:%d" % JOY_BUTTON_DPAD_LEFT, 1)
	Settings.bind("grenade", "joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT)
	Settings.render_scale = 0.7
	Settings.max_fps = 144
	Settings.brightness = 1.25
	Settings.ads_sensitivity = 0.6
	Settings.pad_look_sensitivity = 1.7
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_eq(Array(cfg.get_value("bindings", "reload")), [_k(KEY_T)], "une touche : liste d'une valeur")
	assert_eq(Array(cfg.get_value("bindings", "melee")), ["mouse:%d" % MOUSE_BUTTON_MIDDLE, _w(MOUSE_BUTTON_WHEEL_DOWN)],
			"deux touches : liste de deux valeurs")
	assert_eq(Array(cfg.get_value("pad_bindings", "reload")), ["joy:%d" % JOY_BUTTON_DPAD_DOWN, "joy:%d" % JOY_BUTTON_DPAD_LEFT],
			"boutons de manette dans settings.cfg")
	assert_eq(Array(cfg.get_value("bindings", "grenade")), [_k(KEY_G)])
	# Retour aux valeurs d'origine, puis rechargement du fichier.
	Settings.reset_bindings()
	Settings.render_scale = 1.0
	Settings.max_fps = 0
	Settings.brightness = 1.0
	Settings.ads_sensitivity = 1.0
	Settings.pad_look_sensitivity = 1.0
	assert_true(Settings.load_from(TMP), "fichier relu")
	Settings.apply_bindings()
	assert_eq(Settings.bindings.reload, [_k(KEY_T)])
	assert_eq(Settings.bindings.melee, ["mouse:%d" % MOUSE_BUTTON_MIDDLE, _w(MOUSE_BUTTON_WHEEL_DOWN)])
	assert_eq(Settings.pad_bindings.reload, ["joy:%d" % JOY_BUTTON_DPAD_DOWN, "joy:%d" % JOY_BUTTON_DPAD_LEFT])
	assert_eq(Settings.pad_bindings.grenade, ["joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT])
	assert_eq(Settings.pad_bindings.aim, ["joyaxis:%d:1" % JOY_AXIS_TRIGGER_LEFT], "LT partagé : VISER le garde")
	assert_true(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "InputMap rechargée")
	assert_true(_has_pad_axis("grenade", JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_true(_has_mouse("melee", MOUSE_BUTTON_WHEEL_DOWN) and not _has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN),
			"molette bas : couteau après rechargement")
	assert_near(Settings.render_scale, 0.7)
	assert_eq(Settings.max_fps, 144)
	assert_near(Settings.brightness, 1.25)
	assert_near(Settings.ads_sensitivity, 0.6)
	assert_near(Settings.pad_look_sensitivity, 1.7)


func test_shared_keys_saved_and_reloaded() -> void:
	# F sur INTERAGIR et RECHARGER (case 2), molette bas sur COUTEAU et
	# GRENADE, X sur INTERAGIR et SAUTER : même format de fichier (listes de
	# codes par action), relu tel quel.
	Settings.bind("reload", _k(KEY_F), 1)
	Settings.bind("melee", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	Settings.bind("grenade", _w(MOUSE_BUTTON_WHEEL_DOWN), 1)
	Settings.bind("jump", "joy:%d" % JOY_BUTTON_X, 1)
	Settings.save_to(TMP)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP), OK)
	assert_eq(Array(cfg.get_value("bindings", "interact")), [_k(KEY_F)])
	assert_eq(Array(cfg.get_value("bindings", "reload")), [_k(KEY_R), _k(KEY_F)])
	Settings.reset_bindings()
	assert_true(Settings.load_from(TMP), "fichier relu")
	Settings.apply_bindings()
	assert_eq(Settings.bindings.interact, [_k(KEY_F)], "INTERAGIR garde F")
	assert_eq(Settings.bindings.reload, [_k(KEY_R), _k(KEY_F)], "RECHARGER garde F en case 2")
	assert_eq(Settings.bindings.melee, [_k(KEY_V), _w(MOUSE_BUTTON_WHEEL_DOWN)])
	assert_eq(Settings.bindings.grenade, [_k(KEY_G), _w(MOUSE_BUTTON_WHEEL_DOWN)])
	assert_eq(Settings.pad_bindings.interact, ["joy:%d" % JOY_BUTTON_X])
	assert_eq(Settings.pad_bindings.jump, ["joy:%d" % JOY_BUTTON_A, "joy:%d" % JOY_BUTTON_X])
	assert_true(_has_key("interact", KEY_F) and _has_key("reload", KEY_F), "F dans l'InputMap des deux actions")
	assert_false(_has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN), "molette bas : toujours sans changement d'arme")
	assert_eq(Settings.action_label("interact"), "F", "invite « Appuyez sur F » d'INTERAGIR")
	assert_eq(Settings.action_label("reload"), "R", "invite de RECHARGER : sa première case")
	# Action absente du fichier (nouvelle version) : sa touche d'origine
	# n'est pas remise si une action du fichier l'a déjà (partage non choisi).
	cfg.set_value("bindings", "jump", PackedStringArray([_k(KEY_Q)]))
	cfg.erase_section_key("bindings", "tactical")
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	assert_eq(Settings.bindings.tactical, [], "Q déjà sur SAUTER : pas remise sur GRENADE SPÉCIALE")
	assert_eq(Settings.bindings.jump, [_k(KEY_Q)])


func test_one_slot_file_loads_unchanged() -> void:
	# Fichier de la version précédente (une commande par colonne : touche en
	# liste d'une valeur, bouton de manette en texte) : relu tel quel.
	var cfg := ConfigFile.new()
	@warning_ignore("static_called_on_instance")
	var dk := Settings.default_bindings()
	@warning_ignore("static_called_on_instance")
	var dp := Settings.default_pad_bindings()
	for a in Settings.REBINDABLE:
		cfg.set_value("bindings", a, PackedStringArray(dk[a]))
		cfg.set_value("pad_bindings", a, dp[a][0] if not dp[a].is_empty() else "")
	cfg.set_value("bindings", "reload", PackedStringArray([_k(KEY_T)]))
	cfg.set_value("bindings", "melee", PackedStringArray([]))
	cfg.set_value("pad_bindings", "reload", "joy:%d" % JOY_BUTTON_DPAD_UP)
	cfg.set_value("pad_bindings", "crouch", "")
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	Settings.apply_bindings()
	assert_eq(Settings.bindings.reload, [_k(KEY_T)], "une touche, deuxième case vide")
	assert_eq(Settings.bindings.melee, [], "touche effacée : reste vide")
	assert_eq(Settings.pad_bindings.reload, ["joy:%d" % JOY_BUTTON_DPAD_UP], "bouton en texte relu")
	assert_eq(Settings.pad_bindings.crouch, [], "bouton effacé : reste vide")
	assert_eq(Settings.pad_bindings.jump, ["joy:%d" % JOY_BUTTON_A])
	assert_eq(Settings.bindings.interact, [_k(KEY_F)])
	for a in Settings.REBINDABLE:
		assert_true(Settings.bindings[a].size() <= 1 and Settings.pad_bindings[a].size() <= 1, "%s : une seule commande" % a)


func test_old_two_key_file_migrates() -> void:
	# Fichier d'avant la manette : deux touches par action, pas de colonne
	# manette. La première touche valide est gardée (E n'interagit plus), la
	# manette a sa disposition d'origine.
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "crouch", PackedStringArray([_k(KEY_CTRL), _k(KEY_C)]))
	cfg.set_value("bindings", "interact", PackedStringArray([_k(KEY_F), _k(KEY_E)]))
	cfg.set_value("bindings", "switch_weapon", PackedStringArray([_k(KEY_1), _k(KEY_2)]))
	cfg.set_value("bindings", "reload", PackedStringArray(["bogus", _k(KEY_T), _k(KEY_Y)]))
	cfg.set_value("bindings", "melee", PackedStringArray([]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	Settings.apply_bindings()
	assert_eq(Settings.bindings.crouch, [_k(KEY_CTRL)], "première touche gardée")
	assert_eq(Settings.bindings.interact, [_k(KEY_F)])
	assert_eq(Settings.bindings.switch_weapon, [_k(KEY_1)])
	assert_eq(Settings.bindings.reload, [_k(KEY_T)], "première touche VALIDE")
	assert_eq(Settings.bindings.melee, [], "touche effacée par le joueur : reste vide")
	assert_eq(Settings.bindings.grenade, [_k(KEY_G)], "action absente : touche d'origine")
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
	# Molette : comme une touche ; deux fois la même : une seule ; déjà
	# sur une action précédente (VISER) : gardée sur les deux (partage).
	cfg.set_value("bindings", "aim", PackedStringArray(["mouse:99", _w(MOUSE_BUTTON_WHEEL_DOWN)]))
	cfg.set_value("bindings", "melee", PackedStringArray(["joy:%d" % JOY_BUTTON_A, _w(MOUSE_BUTTON_WHEEL_DOWN),
		_w(MOUSE_BUTTON_WHEEL_LEFT), _w(MOUSE_BUTTON_WHEEL_LEFT), _k(KEY_V)]))
	# Code de manette dans la colonne des touches (et l'inverse) : refusé.
	cfg.set_value("pad_bindings", "melee", _k(KEY_V))
	# Manette : A aussi sur « jump » (partage gardé), codes piégés, mauvais type.
	cfg.set_value("pad_bindings", "jump", "joy:%d" % JOY_BUTTON_A)
	cfg.set_value("pad_bindings", "interact", PackedStringArray(["joy:%d" % JOY_BUTTON_A, _w(MOUSE_BUTTON_WHEEL_UP)]))
	cfg.set_value("pad_bindings", "fire", "joyaxis:%d:1" % JOY_AXIS_RIGHT_X)
	cfg.set_value("pad_bindings", "aim", 42)
	cfg.set_value("pad_bindings", "reload", PackedStringArray(["joy:%d" % JOY_BUTTON_START, "joy:%d" % JOY_BUTTON_DPAD_UP,
		"joy:%d" % JOY_BUTTON_DPAD_DOWN, "joy:%d" % JOY_BUTTON_DPAD_LEFT]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	assert_near(Settings.render_scale, Settings.RENDER_SCALE_RANGE.y)
	assert_eq(Settings.max_fps, 0, "limite inconnue -> illimitée")
	assert_near(Settings.brightness, Settings.BRIGHTNESS_RANGE.x)
	assert_near(Settings.pad_look_sensitivity, Settings.PAD_SENSITIVITY_RANGE.y)
	assert_eq(Settings.bindings.jump, [_k(KEY_Q)], "doublon retiré")
	assert_eq(Settings.bindings.reload, [_k(KEY_R), _k(KEY_T)], "deux touches au plus : les deux premières")
	assert_eq(Settings.bindings.tactical, [], "Q déjà pris")
	assert_eq(Settings.bindings.grenade, [_k(KEY_G)], "action absente : touche d'origine")
	assert_eq(Settings.bindings.aim, [_w(MOUSE_BUTTON_WHEEL_DOWN)], "bouton inconnu refusé, molette bas gardée")
	assert_eq(Settings.bindings.melee, [_w(MOUSE_BUTTON_WHEEL_DOWN), _w(MOUSE_BUTTON_WHEEL_LEFT)],
			"bouton de manette refusé dans la colonne des touches, molette bas partagée avec VISER, molette gauche une fois")
	assert_eq(Settings.pad_bindings.melee, [], "touche refusée dans la colonne manette")
	assert_eq(Settings.pad_bindings.jump, ["joy:%d" % JOY_BUTTON_A])
	assert_eq(Settings.pad_bindings.interact, ["joy:%d" % JOY_BUTTON_A], "A partagé avec SAUTER, molette refusée côté manette")
	assert_eq(Settings.pad_bindings.fire, [], "stick droit refusé")
	assert_eq(Settings.pad_bindings.aim, [], "mauvais type")
	assert_eq(Settings.pad_bindings.reload, ["joy:%d" % JOY_BUTTON_DPAD_UP, "joy:%d" % JOY_BUTTON_DPAD_DOWN],
			"Start refusé, deux valeurs suivantes")
	assert_eq(Settings.pad_bindings.switch_weapon, ["joy:%d" % JOY_BUTTON_Y], "action absente : bouton d'origine")


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
