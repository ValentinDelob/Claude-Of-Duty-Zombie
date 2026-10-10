class_name VoxelFx
extends RefCounted
## Effets CUBIQUES (GAME_CONCEPT.md § 4.19, docs/ART_DIRECTION.md « Effets ») :
## matériaux et maillages partagés de toutes les particules du jeu (effets de
## l'éditeur MapEffects, impacts Fx / ParticlePool, flammes des chiens, arcs
## électriques, flamme de bouche). Aucune texture, aucun panneau face caméra :
## des cubes de couleur unie dont le côté est un multiple de 2,5 cm
## (voxel_particle.gdshader arrondit la taille de chaque cube).
##
## Tailles : petits éclats, sang, étincelles 2,5 à 5 cm (SMALL) ; flammes,
## fumée 5 à 15 cm (BIG). Une grosse particule (flamme, volute de fumée,
## bouffée de vapeur) est une TOUCHE de cubes (puff, tongue) : quand elle
## grossit, ses cubes s'écartent au lieu de dépasser 15 cm.

const SHADER := preload("res://assets/shaders/voxel_particle.gdshader")
const FLASH_SHADER := preload("res://assets/shaders/muzzle_flash.gdshader")
## Pas des cubes des effets (m) : celui des personnages.
const GRID := 0.025
## Côté maximal d'un cube : petits éclats, sang, étincelles ; flammes, fumée.
const SMALL := 0.05
const BIG := 0.15

static var _shaders: Dictionary = {}
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


## Shader des particules : « mix » (fondu, non éclairé), « add » (additif,
## lumineux) ou « lit » (fondu, éclairé par les lampes et les feux).
static func shader(blend: String) -> Shader:
	if blend == "mix" or blend == "":
		return SHADER
	if _shaders.has(blend):
		return _shaders[blend]
	var sh := Shader.new()
	var mode := "render_mode blend_add, unshaded, cull_back, shadows_disabled;" if blend == "add" \
		else "render_mode blend_mix, cull_back, shadows_disabled, specular_disabled;"
	sh.code = SHADER.code.replace("render_mode blend_mix, unshaded, cull_back, shadows_disabled;", mode)
	_shaders[blend] = sh
	return sh


## Matériau partagé des particules cubiques. `o` : max (côté maximal d'un
## cube, m : float ou Vector3 par axe), opacity, shrink (bool : l'alpha de la
## rampe règle la taille), energy, tint (couleur multipliée), edge (arêtes
## assombries), pattern (plats : 1 rond, 2 disque, 3 brume) et px (pixel des
## plats, m).
static func material(blend: String, o: Dictionary = {}) -> ShaderMaterial:
	var key := "%s|%s" % [blend, o]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader(blend)
	var mx: Variant = o.get("max", BIG)
	m.set_shader_parameter("grid", GRID)
	m.set_shader_parameter("cube_max", mx if mx is Vector3 else Vector3.ONE * float(mx))
	m.set_shader_parameter("opacity", float(o.get("opacity", 1.0)))
	m.set_shader_parameter("shrink", 1.0 if o.get("shrink", true) else 0.0)
	m.set_shader_parameter("energy", float(o.get("energy", 1.0)))
	m.set_shader_parameter("edge", float(o.get("edge", 0.0)))
	# Ombrage peint : cubes de matière non éclairés seulement (« shade » :
	# false pour des cubes lumineux fondus).
	m.set_shader_parameter("shade", 1.0 if (blend == "mix" or blend == "") and o.get("shade", true) else 0.0)
	m.set_shader_parameter("pattern", int(o.get("pattern", 0)))
	m.set_shader_parameter("px", float(o.get("px", GRID)))
	m.set_shader_parameter("tint", o.get("tint", Color.WHITE))
	_mats[key] = m
	return m


# ------------------------------------------------------------------ maillages

## Maillage d'un seul cube de côté 1 (centré).
static func cube() -> ArrayMesh:
	return cluster("cube")


## Touffe de cubes de diamètre 1 (repère de la particule) : « cube » (un
## cube), « puff » (boule de 5 x 5 x 5 cellules, quelques trous : cœur du
## feu, éclair, lueur), « cloud » (boule de 7 x 7 x 7 cellules, plus de
## trous : volute de fumée, bouffée de vapeur), « tongue » (langue de
## flamme : colonne qui s'amincit vers le haut). Centres dans une boule de
## rayon 0,42 : avec le demi-côté d'un cube, la touffe garde à peu près le
## diamètre de la particule. Métas : vox_cell (côté d'un cube, unités du
## maillage), vox_ext (demi-étendue des centres), vox_rxy (plus grande
## distance d'un centre à l'axe z).
static func cluster(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var centers := PackedVector3Array()
	var cell := 1.0
	if kind == "cube":
		centers.append(Vector3.ZERO)
	elif kind == "puff" or kind == "cloud":
		var n := 5 if kind == "puff" else 7
		var holes := 0.2 if kind == "puff" else 0.35
		cell = 1.0 / n
		var rng := RandomNumberGenerator.new()
		rng.seed = 51 + n
		for x in n:
			for y in n:
				for z in n:
					var c := (Vector3(x, y, z) + Vector3.ONE * 0.5) * cell - Vector3.ONE * 0.5
					if c.length() > 0.42:
						continue
					# Quelques trous (jamais au centre) : contour irrégulier.
					if c.length() > cell and rng.randf() < holes:
						continue
					# Léger décalage de chaque cube : pas de quadrillage visible
					# quand la touffe s'écarte.
					c += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * cell * 0.25
					centers.append(c)
	elif kind == "tongue":
		cell = 0.2
		# Demi-largeur (en cellules, depuis l'axe) de chaque rang, du bas vers le haut.
		var rows := [1, 1, 1, 0, 0]
		for y in rows.size():
			var h: int = rows[y]
			for x in range(-h, h + 1):
				for z in range(-h, h + 1):
					if h > 0 and absi(x) == h and absi(z) == h and y > 0:
						continue
					centers.append(Vector3(x * cell, (y + 0.5) * cell - 0.5, z * cell))
	else:
		centers.append(Vector3.ZERO)
	var mesh := _with_meta(build(centers, cell), centers, cell)
	_meshes[kind] = mesh
	return mesh


## File de `n` cubes de côté `cell` le long de y, de longueur totale
## `length` (m, repère de la particule ; cubes espacés si elle dépasse
## n × cell) : étincelle, goutte, filet d'eau.
static func chain(n: int, cell: float, length: float) -> ArrayMesh:
	var key := "chain|%d|%.4f|%.4f" % [n, cell, length]
	if _meshes.has(key):
		return _meshes[key]
	var centers := PackedVector3Array()
	var span := maxf(length - cell, 0.0)
	for i in n:
		centers.append(Vector3(0.0, (float(i) / (n - 1) - 0.5) * span if n > 1 else 0.0, 0.0))
	var mesh := _with_meta(build(centers, cell), centers, cell)
	_meshes[key] = mesh
	return mesh


static func _with_meta(mesh: ArrayMesh, centers: PackedVector3Array, cell: float) -> ArrayMesh:
	var ext := Vector3.ZERO
	var rxy := 0.0
	for c in centers:
		ext = ext.max(c.abs())
		rxy = maxf(rxy, Vector2(c.x, c.y).length())
	mesh.set_meta("vox_cell", cell)
	mesh.set_meta("vox_ext", ext)
	mesh.set_meta("vox_rxy", rxy)
	return mesh


## Cubes de côté `cell` aux `centers` (UV = centre.xy, UV2 = (centre.z,
## côté) : voxel_particle.gdshader garde chaque cube à l'échelle).
## `colors` (facultatif) : couleur de chaque cube.
static func build(centers: PackedVector3Array, cell: float, colors := PackedColorArray()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in centers.size():
		var c := centers[i]
		var h := cell * 0.5
		for ax in 3:
			for sg in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[ax] = sg
				var u := Vector3.ZERO
				var v := Vector3.ZERO
				u[(ax + 1) % 3] = 1.0
				v[(ax + 2) % 3] = 1.0
				var corners := [c + (n - u - v) * h, c + (n + u - v) * h, c + (n + u + v) * h, c + (n - u + v) * h]
				# Faces avant dans le sens horaire vues de dehors (convention de Godot).
				var order := [0, 2, 1, 0, 3, 2] if sg > 0.0 else [0, 1, 2, 0, 2, 3]
				for k in order:
					st.set_normal(n)
					st.set_uv(Vector2(c.x, c.y))
					st.set_uv2(Vector2(c.z, cell))
					if not colors.is_empty():
						st.set_color(colors[i])
					st.add_vertex(corners[k])
	return st.commit()


## Diamètre visible d'une particule de taille `s` dessinée par `mesh`
## (cluster) : demi-étendue (par axe, repère de la particule, sans rotation)
## des centres × s + demi-côté des cubes (arrondi à la grille, au plus `mx`).
static func half_extent(mesh: Mesh, s: float, mx: Vector3) -> Array:
	var cell := float(mesh.get_meta("vox_cell", 1.0))
	var ext: Vector3 = mesh.get_meta("vox_ext", Vector3.ZERO)
	var side := (Vector3.ONE * maxf(s * cell + GRID * 0.5, GRID)).min(mx.max(Vector3.ONE * GRID))
	return [ext * s, side]


# ------------------------------------------------------------------ chaînes (arcs)

## Instances `start`.. d'un MultiMesh : cubes de côté `cube` (m) le long de
## la ligne brisée `pts` (repère local), espacés d'un côté (instances
## jusqu'à `end` exclu, -1 : toutes ; plus espacés s'il en manque).
## `metric` : taille d'une unité locale sur chaque axe (m ; arc : largeur,
## longueur, 1) ; les cubes gardent leur côté réel. Rend le nombre posé.
static func fill_chain(mm: MultiMesh, pts: PackedVector3Array, cube: float, metric := Vector3.ONE, start := 0, end := -1) -> int:
	var cap := (mm.instance_count if end < 0 else mini(end, mm.instance_count)) - start
	if cap < 2 or pts.size() < 2:
		return 0
	var total := 0.0
	for i in range(1, pts.size()):
		total += ((pts[i] - pts[i - 1]) * metric).length()
	var n := clampi(ceili(total / cube) + 1, 2, cap)
	var step := total / maxf(n - 1, 1)
	var inv := Basis.from_scale(Vector3(cube / metric.x, cube / metric.y, cube / metric.z))
	var seg := 1
	var seg_t := 0.0
	var placed := 0
	var at_len := 0.0
	for k in n:
		var want := step * k
		# Avance jusqu'au segment qui contient `want` (m depuis le début).
		while seg < pts.size() - 1:
			var l := ((pts[seg] - pts[seg - 1]) * metric).length()
			if at_len + l >= want:
				break
			at_len += l
			seg += 1
		var a := pts[seg - 1]
		var b := pts[seg]
		var seg_len := maxf(((b - a) * metric).length(), 0.000001)
		seg_t = clampf((want - at_len) / seg_len, 0.0, 1.0)
		mm.set_instance_transform(start + placed, Transform3D(inv, a.lerp(b, seg_t)))
		placed += 1
	return placed


## MultiMesh de cubes unités (arcs, pièges) : `cap` instances au plus.
static func chain_multimesh(cap: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cube()
	mm.instance_count = cap
	mm.visible_instance_count = 0
	return mm


## Ligne brisée en zigzag de `a` à `b` : `segs` segments, écarts au hasard
## d'au plus `amp` (vecteurs `side` et `up`, en travers), bouts fixes.
static func zigzag(rng: RandomNumberGenerator, a: Vector3, b: Vector3, segs: int, side: Vector3, up: Vector3, amp: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in segs + 1:
		var t := float(i) / segs
		var p := a.lerp(b, t)
		if i > 0 and i < segs:
			p += side * rng.randf_range(-amp, amp) + up * rng.randf_range(-amp, amp) * 0.5
		pts.append(p)
	return pts


# ------------------------------------------------------------------ flamme de bouche

## Flamme de bouche en cubes de 2,5 cm (repère : canon vers -z) : cœur de
## rayon `rc` cubes dans le plan xy, branches en étoile, pointes le long du
## canon (longueur `pl`, largeur `pw` cubes). Couleur par cube : blanc-jaune
## au cœur, orange aux bouts. Variante `v` (0..3) : longueurs des branches.
static func flash_mesh(rc: int, pl: int, pw: int, v: int) -> ArrayMesh:
	rc = clampi(rc, 1, 6)
	pl = clampi(pl, 1, 16)
	pw = clampi(pw, 1, 6)
	var key := "flash|%d|%d|%d|%d" % [rc, pl, pw, v % 4]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + v * 17
	var cells := {}
	var hot := func(d: float) -> Color:
		var k := clampf(d, 0.0, 1.0)
		return Color(1.0, lerpf(0.95, 0.55, k), lerpf(0.8, 0.2, k), 1.0)
	# Cœur : disque de cubes (une couche, plus une derrière au centre).
	for x in range(-rc, rc + 1):
		for y in range(-rc, rc + 1):
			var d := Vector2(x, y).length()
			if d <= rc + 0.3:
				cells[Vector3i(x, y, 0)] = hot.call(d / (rc + 1.0) * 0.6)
	# Branches en étoile (4 à 6), longueurs au hasard.
	var arms := rng.randi_range(4, 6)
	for k in arms:
		var ang := TAU * (k + rng.randf_range(-0.15, 0.15)) / arms
		var length := rc + rng.randi_range(1, rc + 2)
		for r in range(rc, length + 1):
			var c := Vector3i(roundi(cos(ang) * r), roundi(sin(ang) * r), 0)
			cells[c] = hot.call(0.5 + 0.5 * float(r - rc) / maxf(length - rc, 1))
	# Pointes le long du canon : section de pw x pw qui s'amincit.
	for z in range(1, pl + 1):
		var w := maxi(0, roundi((pw - 1) * 0.5 * (1.0 - float(z) / (pl + 1))))
		for x in range(-w, w + 1):
			for y in range(-w, w + 1):
				cells[Vector3i(x, y, -z)] = hot.call(0.2 + 0.8 * float(z) / pl)
	var centers := PackedVector3Array()
	var colors := PackedColorArray()
	for c: Vector3i in cells:
		centers.append(Vector3(c) * GRID)
		colors.append(cells[c])
	var mesh := build(centers, GRID, colors)
	_meshes[key] = mesh
	return mesh


## Nouvelle flamme sur `mi` (matériau flash_material) : cœur de `core` m de
## diamètre, pointes de `length` m sur `width` m, en cubes de 2,5 cm ;
## variante et angle autour du canon tirés au hasard.
static func reroll_flash(mi: MeshInstance3D, core: float, length: float, width: float) -> void:
	mi.mesh = flash_mesh(roundi(core * 0.5 / GRID), roundi(length / GRID), roundi(width / GRID), randi() % 4)
	(mi.material_override as ShaderMaterial).set_shader_parameter("spin", randf() * TAU)


## Matériau additif de la flamme de bouche (muzzle_flash.gdshader) :
## `viewmodel` : flamme de la vue FPS, cachée par l'arme là où elle passe
## derrière (profondeur de l'arme).
static func flash_material(viewmodel := false) -> ShaderMaterial:
	var fm := ShaderMaterial.new()
	fm.shader = FLASH_SHADER
	fm.set_shader_parameter("viewmodel", 1.0 if viewmodel else 0.0)
	return fm
