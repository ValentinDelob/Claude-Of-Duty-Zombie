class_name LootDrop
extends Interactable
## Arme de butin au sol (GAME_CONCEPT §4.7) : BUTIN PERSONNEL, visible de
## tous, seul le propriétaire a l'invite [F] ; le serveur refuse tout autre
## joueur (LootSystem.srv_pick).
##
## Elle JAILLIT du dernier zombie tué de la vague (LootArc : saut, chute,
## rebonds, puis flottement et rotation lente), le serveur ayant choisi le
## point d'arrivée (position du nœud) ; chaque machine rejoue le même arc
## (départ, arrivée, graine = identifiant). Modèle : la vraie arme
## (WeaponModels, cubes de l'arme), habillée selon sa rareté (LootFx :
## contour lumineux, étoiles, faisceaux, lumière). La fiche de l'arme
## s'affiche quand on la regarde (LootCard).

## Préfixe des identifiants d'interaction.
const ID_PREFIX := "loot_"

var drop_id := 0
var owner_pid := 0
## Arme de partie (GameWeapon).
var weapon: Dictionary = {}
var loot: LootSystem
## Point d'où l'arme jaillit (corps du zombie ; = position : posée sur place).
var from := Vector3.ZERO
## Temps depuis l'apparition (s) ; arc rejoué (LootArc.plan).
var age := 0.0
var arc: Dictionary = {}
## Corps (suit l'arc et le flottement) et pivot de rotation du modèle.
var body: Node3D
var spin_node: Node3D
var fx: Dictionary = {}
var rarity := 0
var _landed := 0
var _light := 0.0
## Demi-taille du modèle (m) : rayon des étoiles, fiche.
var half_size := 0.25


func setup(id: int, owner: int, w: Dictionary, pos: Vector3, sys: LootSystem, start := Vector3.INF) -> void:
	drop_id = id
	owner_pid = owner
	weapon = w
	loot = sys
	interact_id = ID_PREFIX + str(id)
	name = "Loot%d" % id
	position = pos
	from = pos if start == Vector3.INF else start
	interact_range = 2.0
	rarity = GameWeapon.rarity_of(w)


func _ready() -> void:
	arc = LootArc.plan(from, global_position, drop_id)
	var parts := build_model(self, String(weapon.get("id", "")), rarity)
	body = parts.body
	spin_node = parts.spin
	half_size = parts.half
	fx = LootFx.build(self, body, rarity, half_size)
	_light = float(LootFx.tier(rarity).light)
	_place(0.0)
	if rarity >= LootFx.LEGENDARY:
		Audio.play_3d(LootFx.DROP_LEGENDARY_SOUND, from, 0.0, 0.0)


func _process(delta: float) -> void:
	age += delta
	_place(age)


## Corps, rotation, lueurs et sons au temps `t` (s).
func _place(t: float) -> void:
	if body == null:
		return
	var p := LootArc.position(arc, t) - global_position
	var since := t - float(arc.settle)
	p.y += LootArc.hover(arc, since)
	body.position = p
	spin_node.rotation = Vector3(LootArc.tumble(arc, t), LootArc.spin(arc, t), 0.0)
	var lands := LootArc.landings(arc)
	if _landed < lands.size() and t >= lands[_landed]:
		# Premier contact : son et petite gerbe ; rebonds : son plus faible.
		if is_inside_tree() and t - lands[_landed] < 0.25:
			Audio.play_3d(LootFx.LAND_SOUND, global_position, -3.0 * _landed, 0.08)
			if _landed == 0 and Game.instance and Game.instance.fx_root:
				Game.instance.fx_root.dust.burst(global_position + Vector3.UP * 0.05, Vector3.UP, 3, 0.6, 0.8, 0.5, Color(0.6, 0.58, 0.55, 0.6))
		_landed += 1
	# Lueurs : apparaissent au premier contact (faisceaux qui montent du sol).
	var k := clampf((t - float(lands[0])) / 0.45, 0.0, 1.0)
	var light := _light * (0.9 + 0.1 * sin(t * 2.4))
	LootFx.set_fade(fx, k, light)


func interact_point() -> Vector3:
	return global_position + Vector3.UP * LootArc.HOVER_H


## Point d'ancrage de la fiche (au-dessus de l'arme, là où elle est).
func card_point() -> Vector3:
	return (body.global_position if body else interact_point()) + Vector3.UP * 0.1


## Texte d'étiquette : nom, niveau, rareté, joueur (pure, tests ; sert
## aussi à la planche des étiquettes 3D, ui_look).
static func label_text(w: Dictionary, player_name: String) -> String:
	return "%s\n%s\n%s" % [WeaponDB.display_name(String(w.get("id", ""))),
		Lang.t("NIV. %d · %s", "LVL %d · %s") % [GameWeapon.level_of(w), GameWeapon.rarity_name(GameWeapon.rarity_of(w))],
		player_name]


func prompt(pid: int) -> String:
	if pid != owner_pid or weapon.is_empty():
		return ""
	return Lang.t("[F] Ramasser %s (niv. %d)", "[F] Pick up %s (lvl %d)") % [
		WeaponDB.display_name(String(weapon.get("id", ""))), GameWeapon.level_of(weapon)]


func srv_use(pid: int) -> void:
	if loot:
		loot.srv_pick(self, pid)


## Modèle (pur : ajoute les nœuds sous `root`) : corps « Body » (arc,
## flottement), pivot « Spin » (rotation), vraie arme `weapon_id` centrée
## sur le pivot, habillée de la rareté `r` (LootFx.dress). Rend {body,
## spin, model, half (demi-taille, m)}.
static func build_model(root: Node3D, weapon_id: String, r: int) -> Dictionary:
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var spin := Node3D.new()
	spin.name = "Spin"
	body.add_child(spin)
	var model := WeaponModels.build(weapon_id, false)
	var b := model_bounds(weapon_id)
	model.position = -b.get_center()
	spin.add_child(model)
	LootFx.dress(model, r)
	return {"body": body, "spin": spin, "model": model, "half": clampf(b.size.length() * 0.5, 0.12, 0.6)}


## Boîte du modèle de l'arme (repère du modèle), d'après ses pavés.
static func model_bounds(weapon_id: String) -> AABB:
	var parts: Array = WeaponModels.spec(weapon_id).get("parts", [])
	if parts.is_empty():
		return AABB(Vector3(-0.05, -0.05, -0.15), Vector3(0.1, 0.1, 0.3))
	var box := AABB()
	var first := true
	for part in parts:
		var a := AABB(part[2] - part[1] * 0.5, part[1])
		box = a if first else box.merge(a)
		first = false
	return box
