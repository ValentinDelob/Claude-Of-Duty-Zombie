class_name WallBuy
extends Interactable
## Arme achetable au mur (silhouette tracée à la craie). Acheter l'arme, ou
## racheter ses munitions à moitié prix si on la possède déjà.

var weapon_id := ""
var cost := 0
var _normal := Vector3.FORWARD


func setup(marker: String, cell: Vector2i, weapon: String, data: MapData) -> void:
	weapon_id = weapon
	cost = WeaponDB.wall_cost(weapon)
	interact_id = "wallbuy_" + marker
	name = "WallBuy" + marker
	_normal = MapDef.wall_normal(data, cell)
	# Plaqué contre le mur, à hauteur de poitrine.
	position = MapData.cell_to_world(cell) + _normal * (MapData.CELL * 0.5 - 0.02) + Vector3.UP * 1.45
	interact_range = 1.8


func _ready() -> void:
	# Face au joueur : +Z du nœud tourné vers la pièce (opposé au mur).
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var chalk := WeaponModels.build(WeaponDB.stats(weapon_id).model, false)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.8, 0.82, 0.78, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	for mi in chalk.get_children():
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Aplati contre le mur, vu de profil, agrandi.
	chalk.rotation.y = PI * 0.5
	chalk.scale = Vector3(0.06, 1.6, 1.6)
	chalk.position = Vector3(0.0, 0.0, 0.02)
	add_child(chalk)
	var label := Label3D.new()
	label.text = "%s\n%d" % [WeaponDB.display_name(weapon_id), cost]
	label.font = UiStyle.font("stencil")
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color(0.8, 0.76, 0.62, 0.8)
	label.position = Vector3(0, -0.42, 0.03)
	label.shaded = true
	add_child(label)


func interact_point() -> Vector3:
	return global_position - _normal * 0.3


func prompt(pid: int) -> String:
	var pd := system.game.session.get_data(pid)
	if pd == null:
		return ""
	var slot := pd.has_weapon(weapon_id)
	if slot < 0:
		return "[F] Acheter %s %s" % [WeaponDB.display_name(weapon_id), Interactable.cost_text(cost)]
	var w: Dictionary = pd.weapons[slot]
	if WeaponDB.is_full(w):
		return ""
	return "[F] Munitions %s %s" % [WeaponDB.display_name(w.id, w.pap), Interactable.cost_text(WeaponDB.ammo_cost(w.id, w.pap))]


func srv_use(pid: int) -> void:
	var session := system.game.session
	var pd := session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	var slot := pd.has_weapon(weapon_id)
	if slot >= 0:
		var w: Dictionary = pd.weapons[slot]
		if WeaponDB.is_full(w):
			return
		if not session.try_spend(pid, WeaponDB.ammo_cost(w.id, w.pap)):
			system.deny(pid, "Pas assez de points")
			return
		WeaponDB.refill(pd, slot)
	else:
		if not session.try_spend(pid, cost):
			system.deny(pid, "Pas assez de points")
			return
		WeaponDB.give(pd, weapon_id)
	system.game.combat.cancel_reload(pid)
	system.purchase_fx(self)
	session.sync_inventory(pid)
