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
	_theater_props()

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
		"exit_red":
			return _emissive(Color(1.0, 0.08, 0.04), 3.5)
		"glow_crystal":
			return _emissive(Color(1.0, 0.9, 0.75), 1.2)
		"mirror":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.5, 0.52, 0.5)
			m.metallic = 1.0
			m.roughness = 0.12
			return m
	if key.begins_with("poster"):
		var pm := TheaterLook.poster_material(key.substr(6).to_int())
		_warm(pm)
		return pm
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
	var len := g.size() * MapData.CELL
	_box("steel", Vector3(0.9, 0.08, len - 0.1), center + Vector3(0, 0.42, 0), rot, true)
	_box("fabric", Vector3(0.82, 0.14, len - 0.25), center + Vector3(0, 0.53, 0), rot)
	for sx in [-0.4, 0.4]:
		for sz in [-(len * 0.5 - 0.1), len * 0.5 - 0.1]:
			_box("steel#ns", Vector3(0.05, 0.45, 0.05), center + Vector3(sx, 0.22, sz).rotated(Vector3.UP, rot), rot)
	_box("steel", Vector3(0.9, 0.5, 0.05), center + Vector3(0, 0.7, -(len * 0.5 - 0.05)).rotated(Vector3.UP, rot), rot)


func _bench(g: Array) -> void:
	var center := MapData.cells_center(g)
	var along_x: bool = g.size() > 1 and g[0].y == g[1].y
	var rot := PI * 0.5 if along_x else 0.0
	var len := g.size() * MapData.CELL
	_box("steel", Vector3(0.95, 0.06, len - 0.05), center + Vector3(0, 0.9, 0), rot, true)
	_box("steel", Vector3(0.85, 0.7, len - 0.3), center + Vector3(0, 0.45, 0), rot, true)
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
	d.texture_albedo = Fx.blood_splat_texture(int(_h(c) * 4.0))
	d.modulate = Color(0.5, 0.02, 0.02)
	d.size = Vector3(1.6 + _h(c, 1), 0.5, 1.6 + _h(c, 2))
	d.position = MapData.cell_to_world(c, 0.1)
	d.rotation.y = _h(c, 3) * TAU
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
		var ceil_h := def.cell_height(data, c) if def else MapBuilder.WALL_HEIGHT
		# Salles hautes : la lampe pend au bout d'une longue tige.
		var drop := maxf(0.25, ceil_h - 4.2)
		var pos := MapData.cell_to_world(c, ceil_h - drop + 0.25)
		# Tige, abat-jour conique et ampoule.
		_cyl("steel#ns", 0.015, drop, Transform3D(Basis.IDENTITY, pos + Vector3(0, drop * 0.5 - 0.25, 0)), false, 4)
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
func _map_light(c: Vector2i, pos: Vector3, energy: float, light_range: float, flicker_chance := 0.22) -> OmniLight3D:
	return add_lamp(pos, energy, light_range, _h(c, 9) < flicker_chance)


# --------------------------------------------------------------------------
# Décor de théâtre (KINO) : voir TheaterLook pour les matériaux dédiés.
# --------------------------------------------------------------------------

func _theater_props() -> void:
	if def == null or not def.theater_props:
		return
	var screen: Array = data.markers.get("]", [])
	for g in MapDef.group_cells(data.markers.get("=", [])):
		_seat_row(g, screen)
	for g in MapDef.group_cells(data.markers.get("~", [])):
		_curtain(g)
	for g in MapDef.group_cells(screen):
		_screen(g)
	for c in data.markers.get("?", []):
		_chandelier(c)
	for c in data.markers.get("!", []):
		_sconce(c)
	for c in data.markers.get("+", []):
		_exit_sign(c)
	for c in data.markers.get("&", []):
		_poster(c)
	for c in data.markers.get("$", []):
		_vanity(c)
	for c in data.markers.get("@", []):
		_projector(c, screen)
	for c in data.markers.get("|", []):
		_pillar(c)
	for c in data.markers.get("^", []):
		_costume_rack(c)
	if def and def.stage_zone != "":
		_stage_front()
	if def and def.balcony_zone != "":
		_balcony()


## Colonne du hall (bloquante) : fût, base et chapiteau, bagues de laiton.
func _pillar(c: Vector2i) -> void:
	var base := MapData.cell_to_world(c)
	var h := _ceil(c)
	_cyl("dark_wood", 0.3, h, Transform3D(Basis.IDENTITY, base + Vector3(0, h * 0.5, 0)), true, 12)
	_box("marble", Vector3(0.85, 0.35, 0.85), base + Vector3(0, 0.175, 0), 0.0, true)
	_box("dark_wood#ns", Vector3(0.8, 0.3, 0.8), base + Vector3(0, h - 0.15, 0))
	for y in [0.5, 1.6, h - 0.45]:
		_cyl("brass#ns", 0.32, 0.06, Transform3D(Basis.IDENTITY, base + Vector3(0, y, 0)), false, 12)


## Portant de costumes des loges (bloquant) : barre, pieds, habits suspendus.
func _costume_rack(c: Vector2i) -> void:
	var base := MapData.cell_to_world(c)
	var rot := (_h(c) - 0.5) * 0.6
	var b := Basis(Vector3.UP, rot)
	_box("steel#ns", Vector3(0.95, 0.04, 0.04), base + Vector3(0, 1.75, 0), rot)
	for s in [-0.45, 0.45]:
		_box("steel#ns", Vector3(0.04, 1.75, 0.04), base + b * Vector3(s, 0.875, 0), rot)
		_box("steel#ns", Vector3(0.04, 0.04, 0.5), base + b * Vector3(s, 0.02, 0), rot)
	var keys := ["velvet", "fabric", "velvet", "dark_wood", "fabric"]
	for k in 5:
		var x := -0.36 + k * 0.18
		var len := 0.8 + _h(c, k) * 0.5
		_box(keys[(k + int(_h(c, 7) * 5.0)) % keys.size()], Vector3(0.12, len, 0.42), base + b * Vector3(x, 1.72 - len * 0.5, 0), rot + (_h(c, k + 3) - 0.5) * 0.2)
	_blocker(Vector3(0.95, 1.8, 0.5), base + Vector3(0, 0.9, 0), 1)


## Galerie à mi-hauteur le long des murs de la zone (le foyer « à l'étage »
## vu du hall) : corniche en bois, consoles et balustrade de laiton. Décor
## pur (hors d'atteinte), fusionné par matériau.
func _balcony() -> void:
	var y := def.balcony_height
	for cy in data.height:
		for cx in data.width:
			var c := Vector2i(cx, cy)
			if not data.is_floor(c) or data.zone_at(c) != def.balcony_zone or def.cell_height(data, c) <= y + 0.5:
				continue
			for d: Vector2i in MapBuilder.DIRS:
				if not data.is_wall(c + d):
					continue
				var n := Vector3(d.x, 0, d.y)
				var side := Vector3(-d.y, 0, d.x)
				var center := MapData.cell_to_world(c) + n * 0.05
				var rot := atan2(n.x, n.z)
				_box("dark_wood#ns", Vector3(1.0, 0.22, 0.9), center + Vector3(0, y, 0), rot)
				_box("brass#ns", Vector3(1.0, 0.05, 0.05), center - n * 0.42 + Vector3(0, y + 0.95, 0), rot)
				_box("dark_wood#ns", Vector3(1.0, 0.08, 0.08), center - n * 0.42 + Vector3(0, y + 0.15, 0), rot)
				for s in [-0.25, 0.25]:
					_box("brass#ns", Vector3(0.035, 0.8, 0.035), center - n * 0.42 + side * s + Vector3(0, y + 0.55, 0), rot)
				if (cx + cy) % 2 == 0:
					_box("dark_wood#ns", Vector3(0.12, 0.45, 0.5), center + n * 0.2 + Vector3(0, y - 0.33, 0), rot)


func _warm(mat: Material) -> void:
	if not mat in warmup_materials:
		warmup_materials.append(mat)


## Hauteur sous plafond (salles hautes).
func _ceil(c: Vector2i) -> float:
	return def.cell_height(data, c) if def else MapBuilder.WALL_HEIGHT


## Boîte de collision seule (sans rendu) sur une couche donnée.
func _blocker(size: Vector3, pos: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.position = pos
	body.add_child(cs)
	root.add_child(body)


## Rangée de fauteuils de cinéma (2 par cellule), tournés vers l'écran.
## Tout est fusionné par matériau ; une seule collision par rangée (dossiers
## à hauteur de balle) + une barrière haute invisible pour joueurs et zombies
## (on ne marche pas sur les fauteuils) que les balles traversent.
func _seat_row(g: Array, screen: Array) -> void:
	var center := MapData.cells_center(g)
	var along_x: bool = g.size() == 1 or g[0].y == g[1].y
	var target := MapData.cells_center(screen) if not screen.is_empty() else center + Vector3(0, 0, -10)
	var face := Vector3(0, 0, signf(target.z - center.z)) if along_x else Vector3(signf(target.x - center.x), 0, 0)
	if face == Vector3.ZERO:
		face = Vector3.FORWARD
	# Base du fauteuil : +Z local = vers l'écran.
	var rot := atan2(face.x, face.z)
	var b := Basis(Vector3.UP, rot)
	for c: Vector2i in g:
		var base := MapData.cell_to_world(c)
		for k in 2:
			var side := (k - 0.5) * 0.5
			var lateral := Vector3(side, 0, 0) if along_x else Vector3(0, 0, side)
			var o := base + lateral
			var rnd := _h(c, k + 20)
			# Quelques fauteuils cassés : assise relevée ou dossier renversé.
			var folded := rnd > 0.8
			var tilt := (rnd - 0.5) * 0.12
			var sb := b.rotated(Vector3.UP, tilt)
			if folded:
				_add("velvet", _box_mesh(Vector3(0.44, 0.4, 0.08)), Transform3D(sb, o + sb * Vector3(0, 0.62, -0.05)))
			else:
				_add("velvet", _box_mesh(Vector3(0.44, 0.1, 0.42)), Transform3D(sb, o + sb * Vector3(0, 0.44, 0.06)))
			var back_tilt := sb.rotated(sb.x, -0.18 - (0.35 if rnd < 0.08 else 0.0))
			_add("velvet", _box_mesh(Vector3(0.46, 0.56, 0.09)), Transform3D(back_tilt, o + sb * Vector3(0, 0.78, -0.2)))
			_add("dark_wood#ns", _box_mesh(Vector3(0.05, 0.08, 0.4)), Transform3D(sb, o + sb * Vector3(0.245, 0.66, 0.02)))
			_add("steel#ns", _box_mesh(Vector3(0.04, 0.5, 0.36)), Transform3D(sb, o + sb * Vector3(0.245, 0.25, 0.0)))
	var span := Vector3(g.size() * MapData.CELL, 0, 0.7) if along_x else Vector3(0.7, 0, g.size() * MapData.CELL)
	_blocker(Vector3(span.x, 1.0, span.z), center + Vector3(0, 0.5, 0), 1)
	_blocker(Vector3(span.x, 3.0, span.z), center + Vector3(0, 1.5, 0), Barricade.BARRIER_LAYER)


func _box_mesh(size: Vector3) -> BoxMesh:
	var skey := var_to_str(size)
	if not _box_meshes.has(skey):
		var bm := BoxMesh.new()
		bm.size = size
		_box_meshes[skey] = bm
	return _box_meshes[skey]


## Rideau de velours contre le mur (toute la hauteur).
func _curtain(g: Array) -> void:
	var center := MapData.cells_center(g)
	var n := MapDef.wall_normal(data, g[0])
	var h := _ceil(g[0])
	var along_x := absf(n.z) > 0.5
	var width := g.size() * MapData.CELL
	var size := Vector3(width, h - 0.05, 0.25) if along_x else Vector3(0.25, h - 0.05, width)
	_box("velvet#ns", size, center + n * 0.36 + Vector3(0, h * 0.5, 0), 0.0)
	# Embrasse dorée.
	_box("brass#ns", Vector3(size.x + 0.02, 0.08, size.z + 0.02), center + n * 0.36 + Vector3(0, 1.4, 0))


## Grand écran de cinéma (panneau unique animé : film muet quand le courant
## est rétabli).
func _screen(g: Array) -> void:
	var center := MapData.cells_center(g)
	var n := MapDef.wall_normal(data, g[0])
	var h := _ceil(g[0])
	var along_x := absf(n.z) > 0.5
	var width := g.size() * MapData.CELL
	var mi := MeshInstance3D.new()
	mi.name = "CinemaScreen"
	var q := QuadMesh.new()
	q.size = Vector2(width - 0.4, minf(h - 2.2, width * 0.42))
	mi.mesh = q
	mi.position = center + n * 0.47 + Vector3(0, 1.2 + q.size.y * 0.5, 0)
	mi.rotation.y = atan2(-n.x, -n.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := TheaterLook.screen_material()
	_warm(mat)
	mi.material_override = mat
	root.add_child(mi)
	power.add_hook(func(on: bool): mat.set_shader_parameter("playing", 1.0 if on else 0.0))
	# Cadre noir autour de l'écran.
	var fs := Vector3(width, 0.25, 0.1) if along_x else Vector3(0.1, 0.25, width)
	for y in [1.1, 1.3 + q.size.y]:
		_box("dark_wood#ns", fs, center + n * 0.46 + Vector3(0, y, 0))


## Lustre : anneau de laiton, bougies électriques, pampilles, chaîne.
func _chandelier(c: Vector2i) -> void:
	var h := _ceil(c)
	var y := h - minf(1.6, h * 0.3)
	var pos := MapData.cell_to_world(c, y)
	_cyl("brass#ns", 0.02, h - y, Transform3D(Basis.IDENTITY, pos + Vector3(0, (h - y) * 0.5, 0)), false, 4)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.62
	ring.rings = 16
	ring.ring_segments = 4
	_add("brass#ns", ring, Transform3D(Basis.IDENTITY, pos))
	var ring2 := TorusMesh.new()
	ring2.inner_radius = 0.3
	ring2.outer_radius = 0.35
	ring2.rings = 12
	ring2.ring_segments = 4
	_add("brass#ns", ring2, Transform3D(Basis.IDENTITY, pos + Vector3(0, -0.3, 0)))
	for k in 8:
		var a := k * TAU / 8.0
		var p := pos + Vector3(cos(a), 0, sin(a)) * 0.58
		_cyl("bulb#ns", 0.025, 0.12, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.08, 0)), false, 5)
		_cyl("glow_crystal#ns", 0.015, 0.22, Transform3D(Basis.IDENTITY, p + Vector3(0, -0.14, 0)), false, 4)
	_map_light(c, pos + Vector3(0, -0.2, 0), 2.2, 12.0, 0.3)


## Applique murale : platine de laiton et tulipe lumineuse.
func _sconce(c: Vector2i) -> void:
	var n := MapDef.wall_normal(data, c)
	var pos := MapData.cell_to_world(c, 2.3) + n * 0.44
	var rot := atan2(n.x, n.z)
	_box("brass#ns", Vector3(0.18, 0.3, 0.04), pos + n * 0.02, rot)
	_box("brass#ns", Vector3(0.04, 0.04, 0.2), pos - n * 0.08, rot)
	var tulip := CylinderMesh.new()
	tulip.top_radius = 0.1
	tulip.bottom_radius = 0.04
	tulip.height = 0.16
	tulip.radial_segments = 8
	tulip.rings = 1
	_add("bulb#ns", tulip, Transform3D(Basis.IDENTITY, pos - n * 0.18 + Vector3(0, 0.08, 0)))
	_map_light(c, pos - n * 0.4 + Vector3(0, 0.1, 0), 1.8, 8.5, 0.35)


## Panneau SORTIE rouge au-dessus d'une issue (éclairage de secours : ne
## dépend pas du courant).
func _exit_sign(c: Vector2i) -> void:
	var n := MapDef.wall_normal(data, c)
	var pos := MapData.cell_to_world(c, 2.75) + n * 0.44
	var rot := atan2(n.x, n.z)
	_box("dark_wood#ns", Vector3(0.7, 0.26, 0.08), pos, rot)
	_box("exit_red#ns", Vector3(0.62, 0.18, 0.02), pos - n * 0.045, rot)
	var label := Label3D.new()
	label.text = "SORTIE"
	label.font = UiStyle.font("stencil")
	label.font_size = 48
	label.pixel_size = 0.0032
	label.modulate = Color(1.0, 0.85, 0.8)
	label.outline_size = 0
	label.shaded = false
	label.position = pos - n * 0.06
	label.rotation.y = atan2(-n.x, -n.z)
	root.add_child(label)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.1, 0.06)
	l.light_energy = 0.9
	l.omni_range = 3.5
	l.shadow_enabled = false
	l.position = pos - n * 0.5 - Vector3(0, 0.2, 0)
	root.add_child(l)


## Affiche de film encadrée (texture procédurale, 4 variantes).
func _poster(c: Vector2i) -> void:
	var n := MapDef.wall_normal(data, c)
	var pos := MapData.cell_to_world(c, 1.75) + n * 0.47
	var rot := atan2(n.x, n.z)
	_box("brass#ns", Vector3(0.82, 1.18, 0.04), pos + n * 0.01, rot)
	var q := QuadMesh.new()
	q.size = Vector2(0.72, 1.06)
	_add("poster%d#ns" % int(_h(c, 5) * TheaterLook.POSTERS), q, Transform3D(Basis(Vector3.UP, rot + PI), pos - n * 0.015))


## Coiffeuse de loge : table, miroir cerclé d'ampoules (bloquante).
func _vanity(c: Vector2i) -> void:
	var n := MapDef.wall_normal(data, c)
	var base := MapData.cell_to_world(c) + n * 0.2
	var rot := atan2(n.x, n.z)
	_box("dark_wood", Vector3(0.95, 0.08, 0.55), base + Vector3(0, 0.78, 0), rot, true)
	_box("dark_wood", Vector3(0.9, 0.7, 0.5), base + Vector3(0, 0.37, 0), rot, true)
	var mirror_c := MapData.cell_to_world(c, 1.55) + n * 0.46
	_box("dark_wood#ns", Vector3(0.86, 0.86, 0.04), mirror_c + n * 0.01, rot)
	_box("mirror#ns", Vector3(0.7, 0.7, 0.02), mirror_c - n * 0.015, rot)
	var side := Vector3(n.z, 0, -n.x)
	for k in 5:
		var t := (k - 2) * 0.17
		for s in [-1.0, 1.0]:
			_cyl("bulb#ns", 0.03, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, rot), mirror_c + side * s * 0.4 + Vector3(0, t, 0) - n * 0.03), false, 6)
	# Fioles, poudriers et perruque.
	for k in 3:
		var p := base + side * ((_h(c, k) - 0.5) * 0.7) + Vector3(0, 0.87, 0) - n * (_h(c, k + 3) * 0.2)
		_cyl("steel#ns", 0.03 + _h(c, k + 6) * 0.03, 0.08 + _h(c, k + 9) * 0.1, Transform3D(Basis.IDENTITY, p), false, 6)


## Projecteur de la cabine, et son faisceau poussiéreux vers l'écran
## (visible une fois le courant rétabli).
func _projector(c: Vector2i, screen: Array) -> void:
	var base := MapData.cell_to_world(c)
	var target := MapData.cells_center(screen, 3.4) if not screen.is_empty() else base + Vector3(0, 1.4, -10)
	var dir := (Vector3(target.x, 0, target.z) - base).normalized()
	var rot := atan2(dir.x, dir.z)
	_box("steel", Vector3(0.6, 0.9, 0.9), base + Vector3(0, 0.45, 0), rot, true)
	_box("barrel", Vector3(0.45, 0.4, 0.8), base + Vector3(0, 1.1, 0), rot, true)
	for s in [-0.3, 0.3]:
		_cyl("steel#ns", 0.28, 0.06, Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, rot), base + Vector3(0, 1.62, 0) + dir * s), false, 12)
	var lens := base + Vector3(0, 1.15, 0) + dir * 0.5
	_cyl("bulb#ns", 0.09, 0.12, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, rot), lens), false, 10)
	# Faisceau : cône additif qui sort d'une lucarne haute du mur du fond de
	# la salle (la cabine est « au-dessus » du balcon) jusqu'à l'écran.
	var here := data.zone_at(c)
	var probe := base
	for k in 80:
		probe += dir * 0.25
		var pc := MapData.world_to_cell(probe)
		if data.is_floor(pc) and data.zone_at(pc) != here:
			break
	var port_cell := MapData.world_to_cell(probe)
	var from := Vector3(probe.x, _ceil(port_cell) - 1.1, probe.z) - dir * 0.2
	_box("glow_crystal#ns", Vector3(0.5, 0.35, 0.05), from - dir * 0.02, rot)
	_box("dark_wood#ns", Vector3(0.7, 0.55, 0.04), from - dir * 0.05, rot)
	var to := target
	var beam := MeshInstance3D.new()
	beam.name = "ProjectorBeam"
	var cm := CylinderMesh.new()
	var length := from.distance_to(to)
	cm.top_radius = 1.7
	cm.bottom_radius = 0.06
	cm.height = length
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = TheaterLook.beam_material()
	_warm(beam.material_override)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := (to - from).normalized()
	var bx := up.cross(Vector3.UP).normalized()
	if bx.length() < 0.1:
		bx = Vector3.RIGHT
	beam.transform = Transform3D(Basis(bx, up, bx.cross(up)).orthonormalized(), (from + to) * 0.5)
	beam.visible = false
	root.add_child(beam)
	power.add_hook(func(on: bool): beam.visible = on)


## Avant-scène : rampe de lampes au sol, bordure de scène, lambrequin et
## manteau d'arlequin (rideaux latéraux) côté salle.
func _stage_front() -> void:
	var front := []
	for y in data.height:
		for x in data.width:
			var c := Vector2i(x, y)
			if data.zone_at(c) == def.stage_zone and data.is_floor(c + Vector2i(0, 1)) \
					and data.zone_at(c + Vector2i(0, 1)) != def.stage_zone and data.zone_at(c + Vector2i(0, 1)) != "":
				front.append(c)
	if front.is_empty():
		return
	var h := _ceil(front[0] as Vector2i)
	var minx := 9999
	var maxx := -9999
	for c: Vector2i in front:
		minx = mini(minx, c.x)
		maxx = maxi(maxx, c.x)
		var edge := MapData.cell_to_world(c) + Vector3(0, 0, 0.5)
		_box("dark_wood#ns", Vector3(1.0, 0.12, 0.18), edge + Vector3(0, 0.06, -0.09))
		_box("brass#ns", Vector3(1.0, 0.03, 0.2), edge + Vector3(0, 0.135, -0.09))
		for s in [-0.25, 0.25]:
			_cyl("bulb#ns", 0.035, 0.06, Transform3D(Basis.IDENTITY, edge + Vector3(s, 0.17, -0.12)), false, 6)
	var z: float = (front[0] as Vector2i).y + 1.0
	var width := float(maxx - minx + 1)
	var cx := (minx + maxx + 1) * 0.5
	# Lambrequin (bande de velours en haut de la baie) et frange dorée.
	_box("velvet", Vector3(width, 1.3, 0.2), Vector3(cx, h - 0.65, z), 0.0)
	_box("brass#ns", Vector3(width, 0.08, 0.22), Vector3(cx, h - 1.3, z))
	# Rideaux latéraux retenus de chaque côté.
	for sx in [minx + 0.5, maxx + 0.5]:
		_box("velvet", Vector3(1.0, h - 0.1, 0.3), Vector3(sx, (h - 0.1) * 0.5, z - 0.1), 0.0)
	# Deux projecteurs de poursuite suspendus, braqués sur la scène.
	for sx in [cx - width * 0.3, cx + width * 0.3]:
		_box("steel#ns", Vector3(0.3, 0.3, 0.5), Vector3(sx, h - 0.35, z + 1.2), 0.0)
