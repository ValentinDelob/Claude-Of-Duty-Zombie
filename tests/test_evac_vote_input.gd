extends TestCase
## Vote d'évacuation de n'importe où (GAME_CONCEPT §4.5, maquette
## docs/hub_v2/Evacuation.dc.html) : actions « vote_continue » (F1 / croix
## gauche) et « vote_evacuate » (F2 / croix droite), réaffectables ; conflit
## avec une autre action sur la même commande (croix gauche / droite et armes
## 1 / 3 d'origine, ou touche réaffectée) : pendant la fenêtre l'appui ne sert
## qu'au vote, hors de la fenêtre l'autre action marche ; anciens fichiers de
## réglages ; lecture réelle des périphériques (PlayerInput.read_devices).
## Réglages du test seulement (fichier temporaire, état restauré).

const TMP := "user://settings_evac_vote_unittest.cfg"
const READY := EvacRules.Vote.READY
const LEAVE := EvacRules.Vote.LEAVE

var _saved := {}


func before_each() -> void:
	Input.flush_buffered_events()
	for k in ["bindings", "pad_bindings", "using_pad"]:
		var v = Settings.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary else v
	Settings.reset_bindings()


func after_each() -> void:
	for k in _saved:
		Settings.set(k, _saved[k])
	Settings.apply_bindings()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func _k(key: Key) -> String:
	return "key:%d" % key


func _j(b: JoyButton) -> String:
	return "joy:%d" % b


func test_defaults() -> void:
	@warning_ignore("static_called_on_instance")
	var d := Settings.default_bindings()
	@warning_ignore("static_called_on_instance")
	var p := Settings.default_pad_bindings()
	assert_eq(d.vote_continue, [_k(KEY_F1)], "CONTINUER : F1")
	assert_eq(d.vote_evacuate, [_k(KEY_F2)], "ÉVACUER : F2")
	assert_eq(p.vote_continue, [_j(JOY_BUTTON_DPAD_LEFT)], "CONTINUER : croix gauche")
	assert_eq(p.vote_evacuate, [_j(JOY_BUTTON_DPAD_RIGHT)], "ÉVACUER : croix droite")
	assert_true("vote_continue" in Settings.REBINDABLE and "vote_evacuate" in Settings.REBINDABLE, "réaffectables")
	var opts: GDScript = load("res://scripts/ui/screens/options_screen.gd")
	var names: Dictionary = opts.get_script_constant_map().ACTION_NAMES
	for a in Settings.VOTE_ACTIONS:
		assert_true(names.has(a), "nom dans OPTIONS > COMMANDES : %s" % a)
	assert_eq(names.vote_continue, ["ÉVACUATION : CONTINUER", "EVACUATION: CONTINUE"])
	assert_eq(names.vote_evacuate, ["ÉVACUATION : ÉVACUER", "EVACUATION: EVACUATE"])
	assert_eq(Settings.action_label("vote_continue"), "F1")
	assert_eq(Settings.action_label("vote_evacuate"), "F2")


func test_conflicts() -> void:
	@warning_ignore("static_called_on_instance")
	var c := Settings.vote_conflicts(Settings.default_bindings(), Settings.default_pad_bindings())
	assert_eq(c, {"weapon_1": ["vote_continue"], "weapon_3": ["vote_evacuate"]}, "d'origine : croix gauche / droite")
	assert_eq(Settings.vote_shared, c, "gardé par apply_bindings")
	# Touche réaffectée sur une commande déjà prise : F1 pour INTERAGIR aussi,
	# ÉVACUER sur R (RECHARGER).
	Settings.bind("interact", _k(KEY_F1), 1)
	Settings.bind("vote_evacuate", _k(KEY_R), 1)
	assert_eq(Settings.vote_shared.interact, ["vote_continue"])
	assert_eq(Settings.vote_shared.reload, ["vote_evacuate"])
	# Croix gauche retirée de l'ARME 1 : plus de conflit.
	Settings.clear_binding("weapon_1", true)
	assert_false(Settings.vote_shared.has("weapon_1"))
	# Une action sur les deux votes.
	assert_eq(Settings.vote_conflicts({"jump": ["a"], "vote_continue": ["a"], "vote_evacuate": ["a"]}, {}),
			{"jump": ["vote_continue", "vote_evacuate"]})


func test_masked_by_vote() -> void:
	var conf := {"weapon_1": ["vote_continue"], "weapon_3": ["vote_evacuate"]}
	assert_true(PlayerInput.masked_by_vote("weapon_1", conf, true, {"vote_continue": true}), "fenêtre : croix gauche = vote")
	assert_false(PlayerInput.masked_by_vote("weapon_1", conf, false, {"vote_continue": true}), "hors fenêtre : arme 1")
	assert_false(PlayerInput.masked_by_vote("weapon_1", conf, true, {"vote_continue": false}), "1 au clavier pendant la fenêtre : arme 1")
	assert_false(PlayerInput.masked_by_vote("weapon_1", conf, true, {"vote_evacuate": true}), "l'autre vote ne masque pas l'arme 1")
	assert_false(PlayerInput.masked_by_vote("weapon_2", conf, true, {"vote_continue": true, "vote_evacuate": true}), "sans conflit")


func test_old_settings_file_gets_vote_defaults() -> void:
	# Fichier d'avant les votes : armes 1 / 3 sur la croix -> les votes ont
	# leur commande d'origine, croix comprise (partage d'origine).
	var cfg := ConfigFile.new()
	@warning_ignore("static_called_on_instance")
	var dk := Settings.default_bindings()
	@warning_ignore("static_called_on_instance")
	var dp := Settings.default_pad_bindings()
	for a in Settings.REBINDABLE:
		if a in Settings.VOTE_ACTIONS:
			continue
		cfg.set_value("bindings", a, PackedStringArray(dk[a]))
		cfg.set_value("pad_bindings", a, PackedStringArray(dp[a]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	assert_eq(Settings.bindings.vote_continue, [_k(KEY_F1)])
	assert_eq(Settings.pad_bindings.vote_continue, [_j(JOY_BUTTON_DPAD_LEFT)], "croix gauche gardée (partage d'origine)")
	assert_eq(Settings.pad_bindings.vote_evacuate, [_j(JOY_BUTTON_DPAD_RIGHT)])
	# Le joueur avait mis F1 sur SAUTER et la croix gauche sur RECHARGER (pas
	# leurs commandes d'origine) : pas de partage qu'il n'a pas choisi.
	cfg.set_value("bindings", "jump", PackedStringArray([_k(KEY_F1)]))
	cfg.set_value("pad_bindings", "reload", PackedStringArray([_j(JOY_BUTTON_DPAD_LEFT)]))
	cfg.save(TMP)
	assert_true(Settings.load_from(TMP))
	assert_eq(Settings.bindings.vote_continue, [], "F1 déjà sur SAUTER")
	assert_eq(Settings.pad_bindings.vote_continue, [], "croix gauche déjà sur RECHARGER")
	assert_eq(Settings.bindings.vote_evacuate, [_k(KEY_F2)])
	assert_eq(Settings.pad_bindings.vote_evacuate, [_j(JOY_BUTTON_DPAD_RIGHT)])


## Appui injecté hors image physique, puis attente de sa lecture (voir
## test_settings._inject).
func _inject(ev: InputEvent) -> void:
	await host.get_tree().process_frame
	Input.parse_input_event(ev)
	await host.get_tree().process_frame


func _pad(b: JoyButton, down: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = b
	ev.pressed = down
	return ev


func _key(k: Key, down: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = down
	return ev


## Appuis lus comme Player (image physique) : votes et choix d'arme, fenêtre
## ouverte ou non.
func _press_and_read(ev_down: InputEvent, ev_up: InputEvent, vote_open: bool) -> Dictionary:
	var tree := host.get_tree()
	var got := {"votes": [], "slots": [], "interact": 0}
	var inp := PlayerInput.new()
	var read := func():
		inp.read_devices(1.0 / 60.0, vote_open)
		if inp.vote != EvacRules.Vote.NONE:
			got.votes.append(inp.vote)
		if inp.select_slot >= 0:
			got.slots.append(inp.select_slot)
		got.interact += int(inp.interact_pressed)
		inp.clear_edges()
	tree.physics_frame.connect(read)
	await _inject(ev_down)
	for i in 3:
		await tree.physics_frame
	await _inject(ev_up)
	await tree.physics_frame
	tree.physics_frame.disconnect(read)
	return got


func test_dpad_votes_only_during_window() -> void:
	var g: Dictionary = await _press_and_read(_pad(JOY_BUTTON_DPAD_LEFT, true), _pad(JOY_BUTTON_DPAD_LEFT, false), true)
	assert_eq(g.votes, [READY], "fenêtre : croix gauche = CONTINUER")
	assert_eq(g.slots, [], "fenêtre : pas d'arme 1")
	g = await _press_and_read(_pad(JOY_BUTTON_DPAD_RIGHT, true), _pad(JOY_BUTTON_DPAD_RIGHT, false), true)
	assert_eq(g.votes, [LEAVE], "fenêtre : croix droite = ÉVACUER")
	assert_eq(g.slots, [], "fenêtre : pas d'arme 3")
	g = await _press_and_read(_pad(JOY_BUTTON_DPAD_LEFT, true), _pad(JOY_BUTTON_DPAD_LEFT, false), false)
	assert_eq(g.votes, [], "hors fenêtre : aucun vote")
	assert_eq(g.slots, [0], "hors fenêtre : arme 1")
	g = await _press_and_read(_key(KEY_1, true), _key(KEY_1, false), true)
	assert_eq(g.slots, [0], "touche 1 pendant la fenêtre : arme 1 (pas de conflit)")
	g = await _press_and_read(_key(KEY_F2, true), _key(KEY_F2, false), true)
	assert_eq(g.votes, [LEAVE], "F2 : ÉVACUER")
	g = await _press_and_read(_key(KEY_F1, true), _key(KEY_F1, false), true)
	assert_eq(g.votes, [READY], "F1 : CONTINUER (l'autre touche change le vote)")


func test_rebound_onto_used_key() -> void:
	# CONTINUER réaffecté sur F (INTERAGIR) : pendant la fenêtre, F vote
	# seulement ; hors de la fenêtre, F interagit.
	Settings.bind("vote_continue", _k(KEY_F))
	var g: Dictionary = await _press_and_read(_key(KEY_F, true), _key(KEY_F, false), true)
	assert_eq(g.votes, [READY], "F vote CONTINUER")
	assert_eq(g.interact, 0, "F n'interagit pas pendant la fenêtre")
	g = await _press_and_read(_key(KEY_F, true), _key(KEY_F, false), false)
	assert_eq(g.votes, [], "hors fenêtre : pas de vote")
	assert_eq(g.interact, 1, "hors fenêtre : F interagit")
	assert_eq(Settings.action_label("vote_continue"), "F", "touche affichée dans le cadre de vote")
