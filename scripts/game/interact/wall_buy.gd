class_name WallBuy
extends Interactable
## Arme achetable au mur (silhouette tracée à la craie). Acheter l'arme, ou
## racheter ses munitions à moitié prix si on la possède déjà.
## Un couteau (KnifeDB, ex. COUTEAU DE CHASSE) s'achète aussi au mur : il
## remplace le couteau de mêlée, sans munitions à racheter.

var weapon_id := ""
var cost := 0
## Vrai si l'objet vendu est un couteau (KnifeDB) et non une arme à feu.
var is_knife := false
## Aspect choisi dans l'éditeur de cartes (format 5, MapCatalog.VARIANTS) :
## « craie » (défaut : la craie à même le mur) ou « planche » (la craie sur
## une planche clouée au mur). Valeur inconnue : l'aspect par défaut.
var variant := ""
var _normal := Vector3.FORWARD


func setup(marker: String, cell: Vector2i, weapon: String, data: MapData) -> void:
	setup_marker(GridMapLayout.cell_marker(marker, cell, data), weapon)


func setup_marker(m: MapMarker, weapon: String) -> void:
	weapon_id = weapon
	is_knife = KnifeDB.exists(weapon)
	cost = KnifeDB.wall_cost(weapon) if is_knife else WeaponDB.wall_cost(weapon)
	if cost <= 0:
		# Arme inconnue ou pas vendue au mur (boîte mystère, bonus) : sans prix,
		# elle serait gratuite ; srv_use refuse tout achat.
		push_error("[WallBuy] « %s » n'a pas de prix au mur (%s) : achat refusé" % [weapon.left(32), m.id])
	interact_id = "wallbuy_" + m.id
	name = "WallBuy" + m.id
	variant = String(m.data.get("variant", ""))
	_normal = m.wall
	# Plaqué contre le mur, à hauteur de poitrine.
	position = m.on_wall(0.02, 1.45)
	mount_height = 1.45  # au mur : son niveau est 1,45 m plus bas (InteractionSystem.same_level)
	interact_range = 1.8


func _ready() -> void:
	# Face au joueur : +Z du nœud tourné vers la pièce (opposé au mur).
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	if variant == "planche":
		_build_board()
	# Contour à la craie (comme BO1) : la silhouette du modèle de l'arme, aplatie
	# contre le mur et vue de profil, en blanc cassé lumineux, doublée d'un
	# halo poudreux un peu plus large.
	var chalk := Node3D.new()
	chalk.name = "Chalk"
	var mid: String = KnifeDB.model(weapon_id) if is_knife else WeaponDB.stats(weapon_id).model
	for layer in [[_chalk_mat(Color(0.92, 0.9, 0.84, 0.62)), 1.0, 0.0], [_chalk_mat(Color(0.85, 0.85, 0.8, 0.14)), 1.06, -0.004]]:
		var shape := WeaponModels.build(mid, false)
		for mi in shape.get_children():
			(mi as MeshInstance3D).material_override = layer[0]
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Aplati contre le mur, vu de profil, agrandi (et centré sur l'arme).
		shape.rotation.y = PI * 0.5
		shape.scale = Vector3(0.02, 1.6, 1.6) * Vector3(1.0, layer[1], layer[1])
		shape.position = Vector3(0.0, 0.0, 0.02 + layer[2])
		chalk.add_child(shape)
	# Centre la silhouette (de la bouche du canon à la crosse) sur l'emplacement.
	chalk.position.x = -WeaponModels.center_z(mid) * 1.6
	add_child(chalk)
	var label := Label3D.new()
	label.text = "%s\n%d" % [_item_name(), cost]
	label.font = UiStyle.font("stencil")
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color(0.8, 0.76, 0.62, 0.8)
	label.position = Vector3(0, -0.42, 0.03)
	label.shaded = true
	add_child(label)


## Variante « planche » : trois planches sombres clouées au mur derrière la
## craie (la craie et le prix restent devant, à 2 cm du mur).
func _build_board() -> void:
	var board := Node3D.new()
	board.name = "Board"
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.7 - 0.08 * float(i % 2), 0.3, 0.018)
		mi.mesh = bm
		mi.material_override = WorldLook.surface("dark_wood" if i != 1 else "wood")
		mi.position = Vector3(0.03 * float(i - 1), 0.31 - 0.31 * i, -0.012)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		board.add_child(mi)
	add_child(board)


static var _chalk_mats: Dictionary = {}


static func _chalk_mat(c: Color) -> StandardMaterial3D:
	if _chalk_mats.has(c):
		return _chalk_mats[c]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_chalk_mats[c] = mat
	return mat


func _item_name() -> String:
	return KnifeDB.display_name(weapon_id) if is_knife else WeaponDB.display_name(weapon_id)


func interact_point() -> Vector3:
	return global_position - _normal * 0.3


func prompt(pid: int) -> String:
	var pd := system.game.session.get_data(pid)
	if pd == null:
		return ""
	if is_knife:
		if pd.knife == weapon_id:
			return ""
		return Lang.t("[F] Acheter %s %s", "[F] Buy %s %s") % [_item_name(), Interactable.cost_text(cost)]
	var slot := pd.has_weapon(weapon_id)
	if slot < 0:
		return Lang.t("[F] Acheter %s %s", "[F] Buy %s %s") % [WeaponDB.display_name(weapon_id), Interactable.cost_text(cost)]
	var w: Dictionary = pd.weapons[slot]
	if WeaponDB.is_full(w):
		return ""
	return Lang.t("[F] Munitions %s %s", "[F] Ammo %s %s") % [WeaponDB.display_name(w.id, w.pap), Interactable.cost_text(WeaponDB.ammo_cost(w.id, w.pap))]


func srv_use(pid: int) -> void:
	var session := system.game.session
	var pd := session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE or cost <= 0:
		return
	if is_knife:
		# Couteau : remplace celui de mêlée ; le client joue la récupération.
		if pd.knife == weapon_id:
			return
		if not session.try_spend(pid, cost):
			system.deny(pid, InteractionSystem.NO_POINTS)
			return
		pd.knife = weapon_id
		VoxSystem.say(pid, "buy_bowie" if weapon_id == "bowie" else "buy_wall", 0.8)
		system.purchase_fx(self)
		# La récupération du couteau occupe les mains et interrompt le
		# rechargement, ici comme chez le client (_on_knife_changed) ;
		# l'inventaire (couteau, cartouches déjà poussées) est renvoyé.
		system.game.combat.srv_hands_busy(pid, KnifeDB.PICKUP_TIME)
		return
	var slot := pd.has_weapon(weapon_id)
	if slot >= 0:
		var w: Dictionary = pd.weapons[slot]
		if WeaponDB.is_full(w):
			return
		if not session.try_spend(pid, WeaponDB.ammo_cost(w.id, w.pap)):
			system.deny(pid, InteractionSystem.NO_POINTS)
			return
		WeaponDB.refill(pd, slot)
		VoxSystem.say(pid, "buy_ammo", 0.5)
	else:
		if not session.try_spend(pid, cost):
			system.deny(pid, InteractionSystem.NO_POINTS)
			return
		WeaponDB.give(pd, weapon_id)
		VoxSystem.say(pid, "buy_wall", 0.6)
	system.game.combat.cancel_reload(pid)
	system.purchase_fx(self)
	session.sync_inventory(pid)
