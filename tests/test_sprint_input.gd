extends TestCase
## Demande de course lue par PlayerInput (BO1) : au clavier, la touche
## ENFONCÉE fait courir ; à la manette, un clic sur L3 verrouille le sprint
## tant qu'on avance, et le verrou tombe dès qu'on s'arrête, recule ou va de
## côté. Une touche du clavier ne pose jamais ce verrou, même quand le
## drapeau « manette » (Settings.using_pad) est resté levé (manette branchée
## qui dérive, clavier et manette mélangés) : sinon, Maj relâchée, la course
## continuait seule.
## Le reste de la règle (visée, accroupi, à terre, souffle, pause, menu,
## focus) : scénario tests/autotest/sprint_restart.gd.

const SAVED_KEYS := ["bindings", "pad_bindings", "using_pad", "pad_device"]

var _saved := {}


func before_each() -> void:
	# Événements injectés par un test précédent : lus maintenant.
	Input.flush_buffered_events()
	for k in SAVED_KEYS:
		var v = Settings.get(k)
		_saved[k] = v.duplicate(true) if v is Dictionary else v
	Settings.reset_bindings()


func after_each() -> void:
	for k in SAVED_KEYS:
		Settings.set(k, _saved[k])
	Settings.apply_bindings()


## Appui ou relâche injecté hors image physique, puis attente de sa lecture
## (voir test_settings._inject).
func _inject(ev: InputEvent) -> void:
	await host.get_tree().process_frame
	Input.parse_input_event(ev)
	await host.get_tree().process_frame


## Événement de la première commande clavier de `action`, appuyée ou relâchée.
func _key(action: String, pressed: bool) -> InputEvent:
	var ev := Settings.event_from_code(Settings.bindings[action][0])
	ev.set("pressed", pressed)
	return ev


func _l3(pressed: bool) -> InputEvent:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_LEFT_STICK
	ev.pressed = pressed
	return ev


func _physics(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


func test_latch_holds_only_while_advancing() -> void:
	var inp := PlayerInput.new()
	inp.move = Vector2(0, 1)
	inp.update_sprint(false, true)
	assert_true(inp.sprint, "clic de L3 en avançant : sprint")
	inp.update_sprint(false, false)
	assert_true(inp.sprint, "verrou : le sprint tient sans garder L3 enfoncé")
	for move in [Vector2.ZERO, Vector2(0, -1), Vector2(1, 0), Vector2(0.95, 0.25)]:
		inp.move = Vector2(0, 1)
		inp.update_sprint(false, true)
		inp.move = move
		inp.update_sprint(false, false)
		assert_false(inp.sprint, "verrou tombé (déplacement %s)" % move)
		inp.move = Vector2(0, 1)
		inp.update_sprint(false, false)
		assert_false(inp.sprint, "de nouveau en avant (après %s) : pas de reprise sans clic" % move)
	# Clic à l'arrêt : rien à verrouiller.
	inp.move = Vector2.ZERO
	inp.update_sprint(false, true)
	inp.move = Vector2(0, 1)
	inp.update_sprint(false, false)
	assert_false(inp.sprint, "clic à l'arrêt : pas de sprint en repartant")
	# Relâché par le joueur (épuisement, visée...) : plus de verrou.
	inp.update_sprint(false, true)
	inp.release_sprint()
	inp.update_sprint(false, false)
	assert_false(inp.sprint, "verrou relâché")
	# Clavier : seulement tant que la touche est enfoncée.
	inp.update_sprint(true, false)
	assert_true(inp.sprint)
	inp.update_sprint(false, false)
	assert_false(inp.sprint, "touche relâchée : plus de demande")


func test_keyboard_press_never_latches() -> void:
	var tree := host.get_tree()
	var inp := PlayerInput.new()
	var frames := {"sprint": 0}
	var read := func():
		# Drapeau « manette » resté levé (manette qui dérive) à chaque image.
		Settings.using_pad = true
		inp.read_devices(1.0 / 60.0)
		frames.sprint += int(inp.sprint)
		inp.clear_edges()
	tree.physics_frame.connect(read)
	await _inject(_key("move_forward", true))
	await _physics(2)
	await _inject(_key("sprint", true))
	await _physics(3)
	assert_true(inp.sprint, "Maj enfoncée en avançant : sprint")
	await _inject(_key("sprint", false))
	await _physics(3)
	assert_false(inp.sprint, "Maj relâchée : plus de sprint (jamais de verrou au clavier)")
	# Appui très bref (appui et relâche lus dans la même image).
	await host.get_tree().process_frame
	Input.parse_input_event(_key("sprint", true))
	Input.parse_input_event(_key("sprint", false))
	await host.get_tree().process_frame
	await _physics(3)
	assert_false(inp.sprint, "appui très bref : pas de sprint verrouillé")
	await _inject(_key("move_forward", false))
	await _physics(2)
	tree.physics_frame.disconnect(read)


func test_pad_click_latches_until_stop() -> void:
	var tree := host.get_tree()
	var inp := PlayerInput.new()
	var read := func():
		inp.read_devices(1.0 / 60.0)
		inp.clear_edges()
	tree.physics_frame.connect(read)
	await _inject(_key("move_forward", true))
	await _physics(2)
	await _inject(_l3(true))
	await _physics(2)
	await _inject(_l3(false))
	await _physics(3)
	assert_true(Settings.using_pad, "clic de manette : périphérique manette")
	assert_true(inp.sprint, "L3 relâché : sprint verrouillé tant qu'on avance")
	await _inject(_key("move_forward", false))
	await _physics(3)
	assert_false(inp.sprint, "arrêt : verrou tombé")
	await _inject(_key("move_forward", true))
	await _physics(3)
	assert_false(inp.sprint, "reprise de la marche : pas de sprint sans nouveau clic")
	await _inject(_key("move_forward", false))
	await _physics(2)
	tree.physics_frame.disconnect(read)
