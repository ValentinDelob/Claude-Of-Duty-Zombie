class_name PerkMachine
extends Interactable
## Distributeur d'atout. S'allume avec le courant (sauf Lazarus), joue sa
## ritournelle de temps en temps. Achat validé par le serveur.
##
## Apparence : distributeur de soda des années 50 modélisé sous Blender
## (tools/blender/props/perk_machines.py -> assets/models/perks/<id>.glb),
## une silhouette par atout comme dans BO1, nom et emblème originaux en
## relief sur le panneau lumineux. Sans modèle : repli en boîtes.

const MODEL_DIR := "res://assets/models/perks/"
const SHADER := preload("res://assets/shaders/perk_machine.gdshader")
## Pièce du modèle -> [usure, énergie lumineuse allumée, teinte éteinte, ombre].
const PARTS := {
	"paint": [0.55, 0.0, 1.0, true],
	"paint2": [0.45, 0.0, 1.0, false],
	"chrome": [0.3, 0.0, 1.0, false],
	"dark": [0.35, 0.0, 1.0, false],
	"glass": [0.2, 0.0, 1.0, false],
	"lit_sign": [0.3, 0.3, 0.42, true],
	"lit_ink": [0.3, 0.12, 0.6, false],
	"lit_lamp": [0.15, 0.8, 0.3, false],
}
static var _materials := {}

var perk_id := ""
var _normal := Vector3.FORWARD
## Repli en boîtes : matériau du panneau.
var _sign_mat: StandardMaterial3D
## Modèle : pièces lumineuses (paramètre d'instance « lit »).
var _lit_meshes: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _jingle_t := 0.0
var _lit := false
var _gone := false


func setup(marker: String, cell: Vector2i, perk: String, data: MapData) -> void:
	setup_marker(GridMapLayout.cell_marker(marker, cell, data), perk)


func setup_marker(m: MapMarker, perk: String) -> void:
	perk_id = perk
	interact_id = "perk_" + m.id
	name = "Perk_" + perk
	_normal = m.wall
	position = m.pos + _normal * 0.08
	interact_range = 2.0
	_jingle_t = 20.0 + fposmod(float(m.seed), 40.0)


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var col := PerkDB.color(perk_id)
	if not _build_model():
		_build_boxes(col)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.omni_range = 4.5
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.8, 1.2)
	add_child(_light)
	system.game.power_changed.connect(func(_on): _refresh())
	_refresh()


## Modèle Blender de l'atout (assets/models/perks/<id>.glb). Un maillage par
## matériau (voir l'en-tête de perk_machines.py) : peinture et panneau
## projettent une ombre, pas les petits détails. Les boîtes « col_* »
## deviennent la collision de la machine. Faux si le modèle manque.
func _build_model() -> bool:
	var path := MODEL_DIR + perk_id + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	scene.name = "Model"
	add_child(scene)
	var body := StaticBody3D.new()
	body.name = "Body"
	# Machine pleine : ni les joueurs ni les zombies ne la traversent (les
	# balles s'y arrêtent, effet d'impact métallique : Fx.surface_of).
	body.collision_layer = 1
	body.collision_mask = 0
	var to_local := global_transform.affine_inverse()
	var grain := float(absi(hash(interact_id)) % 97)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var part := String(mi.name)
		if part.begins_with("col_"):
			var box := (to_local * mi.global_transform) * mi.get_aabb()
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			cs.shape = shape
			cs.position = box.get_center()
			body.add_child(cs)
			mi.get_parent().remove_child(mi)
			mi.free()
			continue
		var cfg: Array = PARTS.get(part, PARTS.paint)
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, _part_material(perk_id, part, mi.mesh.surface_get_material(s)))
		mi.set_instance_shader_parameter("seed", grain)
		if not cfg[3]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cfg[1] > 0.0:
			_lit_meshes.append(mi)
	if body.get_child_count() == 0:
		body.free()
		_add_box_body()
	else:
		add_child(body)
	return true


## Collision d'une machine sans boîtes « col_* » (ou du repli en boîtes).
func _add_box_body() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.04, 2.2, 0.82)
	cs.shape = shape
	cs.position = Vector3(0, 1.1, 0)
	body.add_child(cs)
	add_child(body)


## Matériau partagé par toutes les machines du même atout (l'allumage passe
## par le paramètre d'instance « lit ») : couleur, rugosité et métal du .glb.
static func _part_material(perk: String, part: String, src: Material) -> ShaderMaterial:
	var key := perk + "/" + part
	if _materials.has(key):
		return _materials[key]
	var cfg: Array = PARTS.get(part, PARTS.paint)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var base := src as BaseMaterial3D
	if base:
		m.set_shader_parameter("albedo", base.albedo_color)
		m.set_shader_parameter("roughness_base", base.roughness)
		m.set_shader_parameter("metallic_base", base.metallic)
	m.set_shader_parameter("wear", cfg[0])
	m.set_shader_parameter("glow", cfg[1])
	m.set_shader_parameter("off_dim", cfg[2])
	m.set_shader_parameter("noise_lattice", NoiseLattice.tex2d())
	_materials[key] = m
	return m


## Repli sans modèle : machine en boîtes.
func _build_boxes(col: Color) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = col.darkened(0.55)
	body_mat.roughness = 0.5
	body_mat.metallic = 0.3
	_part(Vector3(1.0, 2.05, 0.78), Vector3(0, 1.025, 0), body_mat)
	_add_box_body()
	_part(Vector3(1.04, 0.12, 0.82), Vector3(0, 2.1, 0), WorldLook.surface("steel"))
	_part(Vector3(1.04, 0.12, 0.82), Vector3(0, 0.06, 0), WorldLook.surface("steel"))
	# Panneau lumineux + fente de distribution.
	_sign_mat = StandardMaterial3D.new()
	_sign_mat.albedo_color = col
	_sign_mat.emission_enabled = true
	_sign_mat.emission = col
	_sign_mat.emission_energy_multiplier = 0.0
	_part(Vector3(0.84, 0.5, 0.04), Vector3(0, 1.62, 0.39), _sign_mat)
	_part(Vector3(0.5, 0.18, 0.04), Vector3(0, 0.55, 0.39), WorldLook.surface("steel"))
	# Bouteille géante décorative sur le côté.
	var bottle := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.05
	bm.bottom_radius = 0.11
	bm.height = 0.42
	bm.radial_segments = 8
	bottle.mesh = bm
	bottle.material_override = _sign_mat
	bottle.position = Vector3(0.33, 2.38, 0.1)
	add_child(bottle)
	var label := Label3D.new()
	label.text = PerkDB.display_name(perk_id)
	label.font = UiStyle.font("impact")
	label.font_size = 64
	label.pixel_size = 0.0035
	label.modulate = Color(0.95, 0.9, 0.8)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 12
	label.position = Vector3(0, 1.62, 0.42)
	add_child(label)


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func powered() -> bool:
	return not PerkDB.needs_power(perk_id, Net.mode == Net.Mode.SOLO) or system.game.power_on


## Solo : LAZARUS TONIC épuisé (acheté 3 fois) : la machine a disparu.
func sold_out() -> bool:
	return perk_id == "lazarus" and Net.mode == Net.Mode.SOLO \
			and system.game.perks.solo_revive_buys >= PerkDB.SOLO_REVIVE_LIMIT


func _refresh() -> void:
	_lit = powered()
	if _sign_mat:
		_sign_mat.emission_energy_multiplier = 2.2 if _lit else 0.05
	for mi in _lit_meshes:
		mi.set_instance_shader_parameter("lit", 1.0 if _lit else 0.0)
	_light.light_energy = 1.3 if _lit else 0.0


func _process(delta: float) -> void:
	if not _gone and sold_out() and not _anyone_holds():
		_vanish()
	if not _lit or _gone:
		return
	_jingle_t -= delta
	if _jingle_t <= 0.0:
		_jingle_t = randf_range(45.0, 90.0)
		Audio.play_3d("jingle_" + perk_id, global_position + Vector3.UP * 1.5, -8.0, 0.0, 1)


func interact_point() -> Vector3:
	return global_position - _normal * 0.7 + Vector3.UP * 1.2


func prompt(pid: int) -> String:
	var pd := system.game.session.get_data(pid)
	if pd == null or pd.has_perk(perk_id) or sold_out():
		return ""
	if not powered():
		return "Le courant doit être rétabli"
	return "[F] Boire %s %s — %s" % [PerkDB.display_name(perk_id), Interactable.cost_text(_cost()), PerkDB.PERKS[perk_id].desc]


func can_interact(pid: int) -> bool:
	return prompt(pid) != ""


func _cost() -> int:
	return PerkDB.cost(perk_id, Net.mode == Net.Mode.SOLO)


func srv_use(pid: int) -> void:
	var game := system.game
	var pd := game.session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE or pd.has_perk(perk_id):
		return
	if not powered():
		system.deny(pid, "Pas de courant")
		return
	if sold_out():
		return
	if not game.session.try_spend(pid, _cost()):
		system.deny(pid, "Pas assez de points")
		return
	system.purchase_fx(self)
	game.perks.srv_grant(pid, perk_id)


func _anyone_holds() -> bool:
	for pd: PlayerData in system.game.session.data.values():
		if pd.has_perk(perk_id):
			return true
	return false


## Comme BO1 : la dernière LAZARUS TONIC consommée, la machine s'envole.
func _vanish() -> void:
	_gone = true
	Audio.play_3d("box_fly", global_position + Vector3.UP, -2.0, 0.0)
	var tw := create_tween()
	tw.tween_property(self, "position", position + Vector3.UP * 6.0, 2.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(hide)
	print("[Perks] LAZARUS TONIC épuisé : la machine disparaît")
