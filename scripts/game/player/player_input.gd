class_name PlayerInput
extends RefCounted
## Intentions du joueur pour une image. Remplies par le clavier/souris ou la
## manette pour un humain, ou par un script (bot d'autotest). Le contrôleur
## ne lit que ceci.

## Stick droit (vue) : zone morte radiale, vitesse de rotation à fond
## (radians par seconde, lacet puis tangage, multipliée par
## Settings.pad_look_sensitivity) et courbe de réponse (exposant : précision
## près du centre, demi-tour rapide à fond, comme sur console).
const LOOK_DEADZONE := 0.15
const PAD_LOOK_SPEED := Vector2(3.2, 2.2)
const PAD_LOOK_CURVE := 2.0
## Stick gauche (déplacement) : zone morte radiale.
const MOVE_DEADZONE := 0.2

var move := Vector2.ZERO        # x = droite, y = avant
var look := Vector2.ZERO        # delta souris (pixels) accumulé depuis la dernière image
var look_pad := Vector2.ZERO    # rotation au stick droit de cette image (radians, x = lacet, y = tangage vers le bas)
var jump := false
var sprint := false
var crouch := false
var fire := false               # maintenu
var fire_pressed := false       # front montant
var aim := false
var reload := false
var interact := false           # maintenu
var interact_pressed := false
var melee := false
var switch_weapon := false
var grenade := false             # maintenu : dégoupiller / cuire, relâcher = lancer
var tactical := false            # maintenu : SINGE-TAMBOUR
## Sprint à la manette (BO1 : un clic sur L3 / LS lance le sprint, qui dure
## tant qu'on avance) ; au clavier, la touche reste maintenue.
var _sprint_latch := false


func clear_edges() -> void:
	look = Vector2.ZERO
	look_pad = Vector2.ZERO
	fire_pressed = false
	interact_pressed = false
	reload = false
	melee = false
	switch_weapon = false
	jump = false


## Zone morte radiale d'un stick, puis remise à l'échelle (juste après la
## zone morte : 0 ; à fond : 1, jamais plus). Pure (tests).
static func stick_deadzone(v: Vector2, deadzone: float) -> Vector2:
	var l := v.length()
	if l <= deadzone or l < 0.0001:
		return Vector2.ZERO
	var out := minf((l - deadzone) / (1.0 - deadzone), 1.0)
	return v / l * out


## Rotation de la vue au stick droit pendant `delta` secondes (radians),
## proportionnelle au temps : la même à 30 ou à 240 images par seconde.
## Pure (tests) ; l'inversion de l'axe vertical et la sensibilité en visée
## sont appliquées ensuite par Player._apply_look, comme pour la souris.
static func pad_look_step(stick: Vector2, sensitivity: float, delta: float) -> Vector2:
	var s := stick_deadzone(stick, LOOK_DEADZONE)
	var l := s.length()
	if l == 0.0:
		return Vector2.ZERO
	var curved := s / l * pow(l, PAD_LOOK_CURVE)
	return curved * PAD_LOOK_SPEED * sensitivity * delta


## Stick droit le plus incliné parmi les manettes branchées (aucune : zéro).
static func right_stick() -> Vector2:
	var best := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if v.length_squared() > best.length_squared():
			best = v
	return best


## Lecture des périphériques (joueur humain local), `delta` : durée de l'image.
func read_devices(delta := 0.0) -> void:
	# Analogique au stick gauche (les touches donnent 0 ou 1).
	move = stick_deadzone(Vector2(
		Input.get_action_raw_strength("move_right") - Input.get_action_raw_strength("move_left"),
		Input.get_action_raw_strength("move_forward") - Input.get_action_raw_strength("move_back")), MOVE_DEADZONE)
	look_pad += pad_look_step(right_stick(), Settings.pad_look_sensitivity, delta)
	if Input.is_action_just_pressed("sprint") and Settings.using_pad:
		_sprint_latch = true
	if move.y < 0.3:
		_sprint_latch = false
	sprint = Input.is_action_pressed("sprint") or _sprint_latch
	crouch = Input.is_action_pressed("crouch")
	fire = Input.is_action_pressed("fire")
	aim = Input.is_action_pressed("aim")
	interact = Input.is_action_pressed("interact")
	grenade = Input.is_action_pressed("grenade")
	tactical = Input.is_action_pressed("tactical")
	if Input.is_action_just_pressed("jump"):
		jump = true
	if Input.is_action_just_pressed("fire"):
		fire_pressed = true
	if Input.is_action_just_pressed("interact"):
		interact_pressed = true
	if Input.is_action_just_pressed("reload"):
		reload = true
	if Input.is_action_just_pressed("melee"):
		melee = true
	if Input.is_action_just_pressed("switch_weapon"):
		switch_weapon = true
