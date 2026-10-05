class_name GrenadeBuy
extends Interactable
## Achat mural de grenades (Kino der Toten) : 250 points, réserve remplie à 4.
## Deux grenades dessinées à la craie sur le mur, comme les autres achats.

var cost := ThrowableRules.FRAG_WALL_COST
var _normal := Vector3.FORWARD


func setup(cell: Vector2i, data: MapData) -> void:
	setup_marker(GridMapLayout.cell_marker("%d_%d" % [cell.x, cell.y], cell, data))


func setup_marker(m: MapMarker) -> void:
	interact_id = "grenades_" + m.id
	name = "GrenadeBuy_" + m.id
	_normal = m.wall
	position = m.on_wall(0.02, 1.45)
	mount_height = 1.45  # au mur : son niveau est 1,45 m plus bas (InteractionSystem.same_level)
	interact_range = 1.8


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var chalk := Node3D.new()
	chalk.name = "Chalk"
	for layer in [[WallBuy._chalk_mat(Color(0.92, 0.9, 0.84, 0.62)), 1.0, 0.0], [WallBuy._chalk_mat(Color(0.85, 0.85, 0.8, 0.14)), 1.08, -0.004]]:
		for x in [-0.13, 0.13]:
			var g := Throwable.build_model(ThrowableRules.Kind.FRAG, false)
			for mi in g.get_children():
				(mi as MeshInstance3D).material_override = layer[0]
			# Aplatie contre le mur, agrandie, légèrement inclinée.
			g.scale = Vector3(3.2, 3.2, 0.15) * Vector3(layer[1], layer[1], 1.0)
			g.rotation.z = -0.25 if x < 0.0 else 0.25
			g.position = Vector3(x, 0.03, 0.02 + layer[2])
			chalk.add_child(g)
	add_child(chalk)
	var label := Label3D.new()
	label.text = "GRENADES\n%d" % cost
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
	if pd == null or not ThrowableRules.can_buy_frags(pd.grenades):
		return ""
	return Lang.t("[F] Acheter des grenades %s", "[F] Buy grenades %s") % Interactable.cost_text(cost)


func srv_use(pid: int) -> void:
	var session := system.game.session
	var pd := session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE or not ThrowableRules.can_buy_frags(pd.grenades):
		return
	if not session.try_spend(pid, cost):
		system.deny(pid, InteractionSystem.NO_POINTS)
		return
	pd.grenades = ThrowableRules.FRAG_MAX
	system.purchase_fx(self)
	session.sync_stats(pid)
