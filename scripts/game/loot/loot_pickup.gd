class_name LootPickup
extends Node3D
## Pièce ou échantillon qui JAILLIT d'un zombie tué (LootArc, comme une arme
## de butin), vu de son seul propriétaire (butin personnel). Le serveur l'a
## DÉJÀ rangé dans les onglets de la partie (LootSystem._on_killed : rien ne
## se perd) ; ce nœud est la récompense visible : l'objet se pose, flotte,
## scintille selon sa rareté, puis, quand le joueur passe à côté (MAGNET m)
## ou au bout de AUTO_COLLECT s, file vers lui avec le son de sa rareté.
## Sa fiche s'affiche quand on le regarde (LootCard).

const KIND_PART := "part"
const KIND_SAMPLE := "sample"
## Rayon d'aimantation (m) et délai de ramassage automatique (s, après le repos).
const MAGNET := 1.5
const AUTO_COLLECT := 14.0
## Durée du vol vers le joueur (s).
const FLY_TIME := 0.32
## Délai minimal au repos avant l'aimantation (on voit l'objet se poser).
const MIN_REST := 0.35

var kind := KIND_SAMPLE
## Pièce (format LootRules.roll_part) ou {"id": échantillon}.
var data: Dictionary = {}
var rarity := 0
var from := Vector3.ZERO
var arc: Dictionary = {}
var age := 0.0
var body: Node3D
var spin_node: Node3D
var fx: Dictionary = {}
var half_size := 0.08
## Vol vers le joueur : temps écoulé (< 0 : pas encore).
var collecting := -1.0
var _fly_from := Vector3.ZERO
var _landed := 0
var _seed := 0


func setup(k: String, d: Dictionary, start: Vector3, end: Vector3, seed_v: int) -> void:
	kind = k
	data = d
	from = start
	position = end
	_seed = seed_v
	rarity = LootFx.part_rarity(d) if k == KIND_PART else LootFx.sample_rarity(String(d.get("id", "")))
	name = "Pickup%d" % seed_v


func _ready() -> void:
	arc = LootArc.plan(from, global_position, _seed)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	spin_node = Node3D.new()
	spin_node.name = "Spin"
	body.add_child(spin_node)
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = LootFx.part_mesh(rarity) if kind == KIND_PART else LootFx.sample_mesh(rarity)
	mi.material_override = LootFx.item_material()
	spin_node.add_child(mi)
	LootFx.dress(mi, rarity)
	fx = LootFx.build(self, body, rarity, half_size)
	_place(0.0)
	if rarity >= LootFx.LEGENDARY:
		Audio.play_3d(LootFx.DROP_LEGENDARY_SOUND, from, 0.0, 0.0)


## Titre de la fiche (nom de la pièce ou de l'échantillon).
func title() -> String:
	if kind == KIND_PART:
		return LootRules.part_title(data)
	return LootRules.sample_name(String(data.get("id", "")))


func card_point() -> Vector3:
	return body.global_position + Vector3.UP * 0.08 if body else global_position


## Posé et pas encore en vol vers le joueur ?
func resting() -> bool:
	return collecting < 0.0 and age >= float(arc.get("settle", 0.0))


## Commence le vol vers le joueur (une seule fois).
func collect() -> void:
	if collecting >= 0.0:
		return
	collecting = 0.0
	_fly_from = body.global_position if body else global_position


## Avance d'une image ; `target` : poitrine du joueur local (null : aucun).
## Rend vrai quand l'objet est ramassé (à libérer par l'appelant).
func tick(delta: float, target: Variant) -> bool:
	age += delta
	if collecting >= 0.0:
		collecting += delta
		var k := clampf(collecting / FLY_TIME, 0.0, 1.0)
		var to: Vector3 = target if target != null else _fly_from + Vector3.UP * 0.5
		# Accélère vers le joueur en se réduisant un peu (aspiré).
		body.global_position = _fly_from.lerp(to, k * k)
		spin_node.rotation.y += delta * 14.0
		body.scale = Vector3.ONE * lerpf(1.0, 0.45, k)
		return k >= 1.0
	_place(age)
	if target != null and age >= float(arc.settle) + MIN_REST:
		var t: Vector3 = target
		var flat := Vector2(t.x - global_position.x, t.z - global_position.z).length()
		if flat <= MAGNET and absf(t.y - global_position.y) < 2.2:
			collect()
	if age >= float(arc.settle) + AUTO_COLLECT:
		collect()
	return false


func _place(t: float) -> void:
	var p := LootArc.position(arc, t) - global_position
	p.y += LootArc.hover(arc, t - float(arc.settle)) * 0.6 + half_size
	body.position = p
	spin_node.rotation = Vector3(LootArc.tumble(arc, t), LootArc.spin(arc, t), 0.0)
	var lands := LootArc.landings(arc)
	if _landed < lands.size() and t >= lands[_landed]:
		if t - lands[_landed] < 0.25:
			Audio.play_3d(LootFx.LAND_SOUND, global_position, -5.0 - 3.0 * _landed, 0.12, 6, 1.25)
		_landed += 1
	LootFx.set_fade(fx, clampf((t - float(lands[0])) / 0.45, 0.0, 1.0), float(LootFx.tier(rarity).light))
