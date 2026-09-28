class_name MeshMapBuilder
extends MapProps
## Décor d'une carte en maillage : instancie le .glb produit par
## tools/blender/mesh_map.py et le branche sur le rendu du jeu.
##
## Objets du .glb : « <matériau>__<salle>__<type> » (visible) et
## « ...__col » (collision, StaticBody3D créé à l'import par le suffixe
## -colonly). Le matériau est une clé de WorldLook.SURFACES : le shader
## procédural BO1 du jeu remplace le matériau d'aperçu de Blender. Sols et
## plafonds ne projettent pas d'ombre (comme MapBuilder).

const NO_SHADOW_KINDS := ["floor", "ceil"]

var layout: Dictionary
var glb_path := ""


func _init(layout_data: Dictionary, glb: String) -> void:
	layout = layout_data
	glb_path = glb


func build(parent: Node3D) -> void:
	_make_root(parent, "Props")
	var scene: Node3D = (load(glb_path) as PackedScene).instantiate()
	scene.name = "Architecture"
	root.add_child(scene)
	var floors := {}
	for r in layout.get("rooms", []):
		floors[r.id] = _room_floor(r)
	for n in scene.find_children("*", "", true, false):
		var parts := String(n.name).split("__")
		if parts.size() < 3:
			continue
		var mat := parts[0]
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.material_override = WorldLook.surface(mat)
			mi.set_instance_shader_parameter("floor_y", float(floors.get(parts[1], 0.0)))
			if parts[2] in NO_SHADOW_KINDS:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n is StaticBody3D:
			var body := n as StaticBody3D
			body.collision_layer = 1
			body.collision_mask = 0
			# Effets d'impact selon la matière (Fx.surface_of).
			for cs in body.get_children():
				if cs is CollisionShape3D:
					cs.set_meta("surface", mat)
			body.set_meta("surface", mat)
	var lamps: Array = layout.get("markers", {}).get("lamps", [])
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		# Une lampe sur cinq grésille (déterministe).
		add_lamp(MeshMapLayout.vec(l.p), float(l.get("energy", 2.2)), float(l.get("range", 10.0)), i % 5 == 3)


## Sol de référence d'une salle (bas de la pente s'il y en a une).
static func _room_floor(r: Dictionary) -> float:
	if r.has("slope"):
		var y := INF
		for p in r.slope:
			y = minf(y, float(p[1]))
		return y
	return float(r.get("floor", 0.0))
