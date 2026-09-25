class_name PlayerInput
extends RefCounted
## Intentions du joueur pour une image. Remplies par le clavier/souris pour un
## humain, ou par un script (bot d'autotest). Le contrôleur ne lit que ceci.

var move := Vector2.ZERO        # x = droite, y = avant
var look := Vector2.ZERO        # delta souris (pixels) accumulé depuis la dernière image
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


func clear_edges() -> void:
	look = Vector2.ZERO
	fire_pressed = false
	interact_pressed = false
	reload = false
	melee = false
	switch_weapon = false
	jump = false


## Lecture des périphériques (joueur humain local).
func read_devices() -> void:
	move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	if move.length_squared() > 1.0:
		move = move.normalized()
	sprint = Input.is_action_pressed("sprint")
	crouch = Input.is_action_pressed("crouch")
	fire = Input.is_action_pressed("fire")
	aim = Input.is_action_pressed("aim")
	interact = Input.is_action_pressed("interact")
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
