class_name PropBuilder
extends MapProps
## Décor de la carte : caisses, barils, lits, paillasses, générateur,
## tuyauteries, lampes grillagées (dont certaines clignotent), flaques de sang.
##
## Les meshes statiques sont fusionnés par matériau (SurfaceTool.append_from) :
## quelques draw calls pour tout le décor. Déterministe (même rendu partout).

## Code du marqueur de fenêtre (MapDef.WINDOW).
const WINDOW_CHAR := 87

var data: MapData
var def: MapDef
var _tools: Dictionary = {}
var _body: StaticBody3D
var _box_meshes: Dictionary = {}


func _init(map_data: MapData, map_def: MapDef) -> void:
	data = map_data
	def = map_def


static func _h(c: Vector2i, salt := 0) -> float:
	return fposmod(sin(c.x * 12.9898 + c.y * 78.233 + salt * 37.719) * 43758.5453, 1.0)


func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Props"
	parent.add_child(root)
	_body = StaticBody3D.new()
	_body.name = "PropCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	root.add_child(_body)
	flicker = LightFlicker.new()
	flicker.name = "LightFlicker"
	root.add_child(flicker)
	power = PowerGrid.new()
	power.name = "PowerGrid"
	power.setup(flicker)
	root.add_child(power)

	for c in data.markers.get("C", []):
		_crate(c)
	for c in data.markers.get("O", []):
		_barrel(c)
	for g in MapDef.group_cells(data.markers.get("I", [])):
		_bed(g)
	for g in MapDef.group_cells(data.markers.get("N", [])):
		_bench(g)
	for g in MapDef.group_cells(data.markers.get("Y", [])):
		_generator(g)
	for c in data.markers.get(",", []):
		_blood(c)
	_windows()
	_pipes()
	_lamps()

	for tkey in _tools:
		var key: String = tkey.get_slice("@", 0)
		var mi := MeshInstance3D.new()
		mi.name = "Props_%s_%s" % [key.replace("#", "_"), tkey.get_slice("@", 1)]
		mi.mesh = (_tools[tkey] as SurfaceTool).commit()
		# Suffixe « #ns » : ne projette pas d'ombre (lampes : sinon l'abat-jour
		# dessine un disque noir au plafond ; petits détails : ombre invisible
		# mais coûteuse à redessiner dans les cubemaps).
		mi.material_override = _material(key.get_slice("#", 0))
		if key.ends_with("#ns"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _material(key: String) -> Material:
	match key:
		"glow_green":
			return _emissive(Color(0.3, 1.0, 0.4), 2.5)
		"glow_red":
			return _emissive(Color(1.0, 0.1, 0.05), 3.0)
		"bulb":
			return _emissive(Color(1.0, 0.72, 0.42), 4.0)
		"plank":
			return Barricade.plank_material()
	return WorldLook.surface(key)


static func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


# --------------------------------------------------------------------------
# Primitives fusionnées
# --------------------------------------------------------------------------

## Fusionne `mesh` dans le lot du matériau `key`, par tuile de
## MapBuilder.CHUNK cellules (élimination hors champ / hors portée des ombres).
func _add(key: String, mesh: Mesh, xf: Transform3D) -> void:
	var c := MapData.world_to_cell(xf.origin)
	@warning_ignore("integer_division")
	var tkey := "%s@%d_%d" % [key, c.x / MapBuilder.CHUNK, c.y / MapBuilder.CHUNK]
	if not _tools.has(tkey):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[tkey] = st
	(_tools[tkey] as SurfaceTool).append_from(mesh, 0, xf)


func _box(key: String, size: Vector3, pos: Vector3, rot_y := 0.0, collide := false) -> void:
	var skey := var_to_str(size)
	if not _box_meshes.has(skey):
		var b := BoxMesh.new()
		b.size = size
		_box_meshes[skey] = b
	var xf := Transform3D(Basis(Vector3.UP, rot_y), pos)
	_add(key, _box_meshes[skey], xf)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = xf
		# Matériau touché par les balles (effet d'impact, Fx.surface_of).
		cs.set_meta("surface", key)
		_body.add_child(cs)


func _cyl(key: String, radius: float, height: float, xf: Transform3D, collide := false, segments := 10) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	_add(key, c, xf)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		cs.shape = shape
		cs.transform = xf
		cs.set_meta("surface", key)
		_body.add_child(cs)


# --------------------------------------------------------------------------
# Objets
# --------------------------------------------------------------------------

func _crate(c: Vector2i) -> void:
	var base := MapData.cell_to_world(c)
	var rot := (_h(c) - 0.5) * 0.3
	_box("crate", Vector3(0.92, 0.9, 0.92), base + Vector3(0, 0.45, 0), rot, true)
	# Lattes de renfort.
	for s in [-1, 1]:
		_box("steel#ns", Vector3(0.94, 0.06, 0.06), base + Vector3(0, 0.45 + s * 0.3, 0.44).rotated(Vector3.UP, rot), rot)
	if _h(c, 1) > 0.55:
		var rot2 := rot + (_h(c, 2) - 0.5) * 0.8
		_box("crate", Vector3(0.7, 0.62, 0.7), base + Vector3(0, 1.21, 0), rot2, true)


func _barrel(c: Vector2i) -> void:
	var base := MapData.cell_to_world(c)
	_cyl("barrel", 0.32, 0.95, Transform3D(Basis.IDENTITY, base + Vector3(0, 0.475, 0)), true)
	for y in [0.2, 0.75]:
		_cyl("steel#ns", 0.335, 0.05, Transform3D(Basis.IDENTITY, base + Vector3(0, y, 0)))


func _bed(g: Array) -> void:
	var center := MapData.cells_center(g)
	var along_z: bool = g.size() > 1 and g[0].x == g[1].x
	var rot := 0.0 if along_z else PI * 0.5
	var seg_len := g.size() * MapData.CELL
	_box("steel", Vector3(0.9, 0.08, seg_len - 0.1), center + Vector3(0, 0.42, 0), rot, true)
	_box("fabric", Vector3(0.82, 0.14, seg_len - 0.25), center + Vector3(0, 0.53, 0), rot)
	for sx in [-0.4, 0.4]:
		for sz in [-(seg_len * 0.5 - 0.1), seg_len * 0.5 - 0.1]:
			_box("steel#ns", Vector3(0.05, 0.45, 0.05), center + Vector3(sx, 0.22, sz).rotated(Vector3.UP, rot), rot)
	_box("steel", Vector3(0.9, 0.5, 0.05), center + Vector3(0, 0.7, -(seg_len * 0.5 - 0.05)).rotated(Vector3.UP, rot), rot)


func _bench(g: Array) -> void:
	var center := MapData.cells_center(g)
	var along_x: bool = g.size() > 1 and g[0].y == g[1].y
	var rot := PI * 0.5 if along_x else 0.0
	var seg_len := g.size() * MapData.CELL
	_box("steel", Vector3(0.95, 0.06, seg_len - 0.05), center + Vector3(0, 0.9, 0), rot, true)
	_box("steel", Vector3(0.85, 0.7, seg_len - 0.3), center + Vector3(0, 0.45, 0), rot, true)
	# Verrerie de laboratoire (certaines fioles luisent encore).
	for k in g.size() * 2:
		var cell: Vector2i = g[k % g.size()]
		var off := Vector3((_h(cell, k) - 0.5) * 0.7, 0, (_h(cell, k + 7) - 0.5) * 0.8)
		var hgt := 0.12 + _h(cell, k + 3) * 0.2
		var key := "glow_green#ns" if _h(cell, k + 11) > 0.6 else "steel#ns"
		_cyl(key, 0.035 + _h(cell, k + 5) * 0.03, hgt, Transform3D(Basis.IDENTITY, MapData.cell_to_world(cell) + off + Vector3(0, 0.93 + hgt * 0.5, 0)), false, 6)


func _generator(g: Array) -> void:
	var center := MapData.cells_center(g)
	_box("door", Vector3(1.9, 1.7, 1.9), center + Vector3(0, 0.85, 0), 0.0, true)
	_box("steel", Vector3(2.0, 0.12, 2.0), center + Vector3(0, 1.76, 0))
	for s in [-0.55, 0.55]:
		_cyl("barrel", 0.28, 1.2, Transform3D(Basis.IDENTITY, center + Vector3(s, 2.4, 0)), false)
	_box("glow_red", Vector3(0.5, 0.2, 0.02), center + Vector3(0, 1.3, 0.96))
	_cyl("steel", 0.12, 1.4, Transform3D(Basis.IDENTITY, center + Vector3(0.7, 2.5, 0.7)))


func _blood(c: Vector2i) -> void:
	var d := Decal.new()
	# Pixel art de 5 cm (32 pixels sur 1,6 m), quart de tour (style cubique).
	d.texture_albedo = Fx.blood_splat_texture(int(_h(c) * 4.0), 32)
	d.modulate = Color(0.5, 0.02, 0.02)
	d.size = Vector3(1.6, 0.5, 1.6)
	d.position = MapData.cell_to_world(c, 0.1)
	d.rotation.y = floorf(_h(c, 3) * 4.0) * PI * 0.5
	d.cull_mask = 1
	d.add_to_group(RenderQuality.DECAL_GROUP)
	RenderQuality.apply_decal(d, RenderQuality.current())
	root.add_child(d)


## Tuyauteries le long des murs des zones industrielles.
## Encadrement fixe des fenêtres barricadées (les planches, animées, sont
## gérées par Barricade) : allège et linteau dans la maçonnerie de la zone
## (collision : arrêtent aussi les balles), appui, traverse et montants en
## bois. Fusionnés avec le reste du décor : aucun draw call par fenêtre.
func _windows() -> void:
	var sill := Barricade.SILL_TOP
	var top := Barricade.LINTEL_BOTTOM
	var lh := MapBuilder.WALL_HEIGHT - top
	for w: BarricadeLayout.Opening in BarricadeLayout.analyze(data):
		var center := MapData.cell_to_world(w.cell)
		var rot := atan2(float(w.inward.x), float(w.inward.y))
		var b := Basis(Vector3.UP, rot)
		var zm: Array = def.zone_materials.get(w.zone, []) if def else []
		# Sans ombre portée : noyés dans le plan du mur, redessinés sinon dans
		# les cubemaps des lampes à chaque mouvement de zombie.
		var wall_key: String = (zm[1] if zm.size() > 1 else "wall") + "#ns"
		_box(wall_key, Vector3(1.0, sill, 1.0), center + Vector3(0, sill * 0.5, 0), rot, true)
		_box(wall_key, Vector3(1.0, lh, 1.0), center + Vector3(0, top + lh * 0.5, 0), rot, true)
		_box("plank#ns", Vector3(1.08, 0.06, 1.06), center + Vector3(0, sill + 0.03, 0), rot)
		_box("plank#ns", Vector3(1.08, 0.1, 1.02), center + Vector3(0, top - 0.05, 0), rot)
		for sx in [-0.47, 0.47]:
			for sz in [-0.45, 0.45]:
				_box("plank#ns", Vector3(0.07, top - sill, 0.1), center + b * Vector3(sx, (sill + top) * 0.5, sz), rot)


func _pipes() -> void:
	var h := MapBuilder.WALL_HEIGHT
	for y in data.height:
		for x in data.width:
			var c := Vector2i(x, y)
			if not data.is_floor(c) or data.at(c) == WINDOW_CHAR or not (data.zone_at(c) in def.pipe_zones):
				continue
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				# Les tuyaux passent au-dessus des fenêtres (au niveau du linteau).
				if not data.is_wall(c + d) and data.at(c + d) != WINDOW_CHAR:
					continue
				var center := MapData.cell_to_world(c)
				var wall_off := Vector3(d.x, 0, d.y) * 0.34
				# Orientation : le tuyau longe le mur.
				var basis := Basis(Vector3.FORWARD, PI * 0.5) if d.y != 0 else Basis(Vector3.RIGHT, PI * 0.5)
				_cyl("steel", 0.07, 1.0, Transform3D(basis, center + wall_off + Vector3(0, h - 0.25, 0)), false, 8)
				_cyl("barrel#ns", 0.045, 1.0, Transform3D(basis, center + wall_off * 0.92 + Vector3(0, h - 0.45, 0)), false, 6)
				if (x + y) % 4 == 0:
					_cyl("steel#ns", 0.095, 0.08, Transform3D(basis, center + wall_off + Vector3(0, h - 0.25, 0)), false, 8)


## Lampes grillagées au plafond. Une sur cinq grésille ; ombres portées sur 0,
## 1 ou 2 lampes sur 3 selon la qualité (RenderQuality).
func _lamps() -> void:
	for c in data.markers.get("L", []):
		var pos := MapData.cell_to_world(c, MapBuilder.WALL_HEIGHT)
		# Tige, abat-jour conique et ampoule.
		_cyl("steel#ns", 0.015, 0.25, Transform3D(Basis.IDENTITY, pos + Vector3(0, -0.125, 0)), false, 4)
		var shade := CylinderMesh.new()
		shade.top_radius = 0.07
		shade.bottom_radius = 0.24
		shade.height = 0.14
		shade.radial_segments = 10
		shade.rings = 1
		_add("steel#ns", shade, Transform3D(Basis.IDENTITY, pos + Vector3(0, -0.3, 0)))
		_cyl("bulb#ns", 0.06, 0.12, Transform3D(Basis.IDENTITY, pos + Vector3(0, -0.4, 0)), false, 8)
		_map_light(c, pos + Vector3(0, -0.5, 0), 2.4, 11.0)


## Lampe de la carte (groupe RenderQuality, courant, grésillement 1 sur 5).
func _map_light(c: Vector2i, pos: Vector3, energy: float, light_range: float) -> OmniLight3D:
	return add_lamp(pos, energy, light_range, _h(c, 9) < 0.22)
