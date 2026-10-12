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
## Marche avant minimale (move.y) pour courir et garder le verrou de L3.
const SPRINT_FORWARD := 0.3

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
## Emplacement en main choisi directement (touches 1 à 3 : 0 à 2), -1 sinon.
var select_slot := -1
var grenade := false             # maintenu : dégoupiller / cuire, relâcher = lancer
## Vote d'évacuation de cette image (front) : EvacRules.Vote.READY
## (CONTINUER), LEAVE (ÉVACUER), NONE sinon. Envoyé au serveur par
## InteractionSystem.local_tick ; lu seulement pendant la fenêtre.
var vote := 0
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
	select_slot = -1
	jump = false
	vote = 0


## Course arrêtée (épuisement, visée, accroupi, à terre, pause...) : le
## sprint verrouillé au clic de L3 se relâche (BO1 : il faut recliquer pour
## repartir).
func release_sprint() -> void:
	_sprint_latch = false


## Demande de course de l'image : commande maintenue (`held_now`) ou sprint
## verrouillé par un clic de manette (`pad_click`). Le verrou tombe dès qu'on
## n'avance plus franchement (arrêt, stick relâché, recul, pas de côté) ;
## Player le relâche aussi dès que la course ne tient pas (visée, accroupi,
## à terre, souffle, pause...). Appelée par read_devices ; les tests
## l'appellent à chaque image pour simuler la manette.
func update_sprint(held_now: bool, pad_click: bool) -> void:
	if pad_click:
		_sprint_latch = true
	if move.y <= SPRINT_FORWARD:
		_sprint_latch = false
	sprint = held_now or _sprint_latch


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


## Action maintenue, ou appuyée depuis l'image physique précédente : un cran
## de molette (appui et relâche dans la même image, Settings.WHEEL_BUTTONS)
## compte ainsi comme un appui d'une image (grenade lancée, visée d'un
## instant). Les fronts (saut, couteau, recharge...) passent par
## Input.is_action_just_pressed, vrai à une seule image physique par cran.
static func held(action: StringName) -> bool:
	return Input.is_action_pressed(action) or Input.is_action_just_pressed(action)


## Une touche du clavier (ou un bouton de souris) de `action` est-elle
## enfoncée ? Les commandes de la manette ne comptent pas.
static func keys_down(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if (k.physical_keycode != KEY_NONE and Input.is_physical_key_pressed(k.physical_keycode)) \
					or (k.keycode != KEY_NONE and Input.is_key_pressed(k.keycode)):
				return true
		elif ev is InputEventMouseButton and Input.is_mouse_button_pressed((ev as InputEventMouseButton).button_index):
			return true
	return false


## Vote choisi par les appuis de l'image : ÉVACUER seul -> LEAVE, CONTINUER
## seul -> READY ; aucun, ou les deux à la fois (ambigu) -> NONE. Pure (tests).
static func pick_vote(continue_pressed: bool, evacuate_pressed: bool) -> int:
	if evacuate_pressed == continue_pressed:
		return EvacRules.Vote.NONE
	return EvacRules.Vote.LEAVE if evacuate_pressed else EvacRules.Vote.READY


## Pendant la fenêtre d'évacuation (`vote_open`), `action` est-elle masquée par
## un vote ? Oui si elle partage une commande (`conflicts` : action -> votes,
## Settings.vote_shared) avec un vote `active` (vote -> bool : appuyé à cette
## image pour un front, enfoncé pour une action maintenue) : cette commande ne
## sert alors qu'au vote (croix gauche : vote CONTINUER, pas l'arme 1). Hors
## de la fenêtre, jamais. Pure (tests).
static func masked_by_vote(action: String, conflicts: Dictionary, vote_open: bool, active: Dictionary) -> bool:
	if not vote_open:
		return false
	for v in conflicts.get(action, []):
		if active.get(v, false):
			return true
	return false


# Masques de l'image en cours (read_devices) : votes en conflit, appuyés,
# enfoncés.
const _NO_CONFLICT := {}
var _conf: Dictionary = _NO_CONFLICT
var _vote_jp: Dictionary = {}
var _vote_down: Dictionary = {}


## Front montant de `action`, sauf masqué par un vote appuyé à cette image.
func _edge(action: String) -> bool:
	return Input.is_action_just_pressed(action) and not masked_by_vote(action, _conf, true, _vote_jp)


## `action` maintenue (held), sauf masquée par un vote enfoncé.
func _hold(action: String) -> bool:
	return held(action) and not masked_by_vote(action, _conf, true, _vote_down)


func _strength(action: String) -> float:
	return 0.0 if masked_by_vote(action, _conf, true, _vote_down) else Input.get_action_raw_strength(action)


## Lecture des périphériques (joueur humain local), `delta` : durée de l'image.
## `vote_open` : fenêtre d'évacuation ouverte et joueur votant
## (EvacDoor.local_can_vote) : les votes (F1 / F2, croix gauche / droite) sont
## lus, et une commande qu'ils partagent avec une autre action ne sert qu'au
## vote (masked_by_vote).
func read_devices(delta := 0.0, vote_open := false) -> void:
	_conf = Settings.vote_shared if vote_open else _NO_CONFLICT
	_vote_jp.clear()
	_vote_down.clear()
	if vote_open:
		for v in Settings.VOTE_ACTIONS:
			_vote_jp[v] = Input.is_action_just_pressed(v)
			_vote_down[v] = _vote_jp[v] or Input.is_action_pressed(v)
		vote = pick_vote(_vote_jp.vote_continue, _vote_jp.vote_evacuate)
	# Analogique au stick gauche (les touches donnent 0 ou 1).
	move = stick_deadzone(Vector2(
		_strength("move_right") - _strength("move_left"),
		_strength("move_forward") - _strength("move_back")), MOVE_DEADZONE)
	look_pad += pad_look_step(right_stick(), Settings.pad_look_sensitivity, delta)
	# Verrou seulement pour un appui venu de la manette (Settings.sprint_press_pad) :
	# une touche du clavier (encore enfoncée ou appui très bref) ne verrouille
	# jamais, même si le drapeau « manette » est resté levé (manette branchée
	# qui dérive, clavier et manette mélangés) ; sinon, Maj relâchée, la
	# course continuait toute seule.
	var pad_click := _edge("sprint") and Settings.sprint_press_pad \
			and not keys_down("sprint")
	update_sprint(_hold("sprint"), pad_click)
	crouch = _hold("crouch")
	fire = _hold("fire")
	aim = _hold("aim")
	interact = _hold("interact")
	grenade = _hold("grenade")
	if _edge("jump"):
		jump = true
	if _edge("fire"):
		fire_pressed = true
	if _edge("interact"):
		interact_pressed = true
	if _edge("reload"):
		reload = true
	if _edge("melee"):
		melee = true
	if _edge("switch_weapon"):
		switch_weapon = true
	for i in Settings.WEAPON_SLOT_ACTIONS.size():
		if _edge(Settings.WEAPON_SLOT_ACTIONS[i]):
			select_slot = i
