class_name LootDrop
extends Interactable
## Arme de butin posée au sol (GAME_CONCEPT §4.7) : BUTIN PERSONNEL, à la
## couleur de son propriétaire (couleur de joueur du tableau des scores,
## HudStyle.PLAYER_COLORS : anneau au sol et faisceau), rareté sur l'arme
## elle-même, étiquette avec nom, niveau, rareté et nom du joueur (daltoniens).
## Visible de tous, seul le propriétaire a l'invite [F] ; le serveur refuse
## tout autre joueur (LootSystem.srv_pick).
##
## Modèle en blocs alignés sur la grille de 5 cm (§4.19, vérifié par
## VoxelCheck dans tests/test_loot.gd) : aucune rotation, seul un léger
## flottement vertical de l'arme.

## Préfixe des identifiants d'interaction.
const ID_PREFIX := "loot_"
const RING := 0.6
const BEAM_H := 1.2

var drop_id := 0
var owner_pid := 0
## Arme de partie (GameWeapon).
var weapon: Dictionary = {}
var loot: LootSystem
var _gun: Node3D
var _label: Label3D
var _t := 0.0


func setup(id: int, owner: int, w: Dictionary, pos: Vector3, sys: LootSystem) -> void:
	drop_id = id
	owner_pid = owner
	weapon = w
	loot = sys
	interact_id = ID_PREFIX + str(id)
	name = "Loot%d" % id
	position = pos
	interact_range = 2.0


func _ready() -> void:
	build_model(self, Net.player_slot(owner_pid), GameWeapon.rarity_of(weapon))
	_gun = get_node_or_null("Gun")
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.outline_size = 10
	_label.position = Vector3(0, 0.75, 0)
	_label.text = label_text(weapon, Net.player_name(owner_pid))
	_label.modulate = GameWeapon.rarity_color(GameWeapon.rarity_of(weapon))
	add_child(_label)


func _process(delta: float) -> void:
	if _gun:
		_t += delta
		_gun.position.y = 0.05 * sin(_t * 2.0)


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.35


## Texte de l'étiquette : nom, niveau, rareté, joueur (pure, tests).
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


## Modèle en blocs (pur : ajoute les blocs sous `root`). Anneau et faisceau à
## la couleur du joueur `slot`, arme à la couleur de la rareté.
static func build_model(root: Node3D, slot: int, rarity: int) -> void:
	var pc := HudStyle.player_color(slot)
	var ring := PropBuilder._emissive(pc, 2.0)
	var h := RING * 0.5
	# Anneau carré au sol (4 barres de 5 cm).
	_box(root, Vector3(0, 0.025, -h + 0.025), Vector3(RING, 0.05, 0.05), ring)
	_box(root, Vector3(0, 0.025, h - 0.025), Vector3(RING, 0.05, 0.05), ring)
	_box(root, Vector3(-h + 0.025, 0.025, 0), Vector3(0.05, 0.05, RING - 0.1), ring)
	_box(root, Vector3(h - 0.025, 0.025, 0), Vector3(0.05, 0.05, RING - 0.1), ring)
	# Faisceau vertical (repère de loin).
	var beam := PropBuilder._emissive(pc, 3.0)
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.albedo_color.a = 0.35
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var b := _box(root, Vector3(-0.2, BEAM_H * 0.5, -0.2),Vector3(0.1, BEAM_H, 0.1), beam)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Arme stylisée (boîtier, canon, poignée, chargeur) à la couleur de la rareté.
	var gun := Node3D.new()
	gun.name = "Gun"
	root.add_child(gun)
	var rc := GameWeapon.rarity_color(rarity)
	var body := StandardMaterial3D.new()
	body.albedo_color = rc
	body.emission_enabled = true
	body.emission = rc
	body.emission_energy_multiplier = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	_box(gun, Vector3(0, 0.35, 0), Vector3(0.4, 0.1, 0.1), body)
	_box(gun, Vector3(0.275, 0.375, 0), Vector3(0.15, 0.05, 0.1), dark)
	_box(gun, Vector3(-0.1, 0.25, 0), Vector3(0.1, 0.1, 0.1), dark)
	_box(gun, Vector3(0.05, 0.25, 0), Vector3(0.1, 0.1, 0.1), body)


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
