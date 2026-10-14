class_name WindowOutside
extends Node3D
## Le « dehors » d'une fenêtre barricadée ou d'une porte à zombies : une
## impostor bon marché posé sur le mur du fond de la poche (où apparaissent
## les zombies), et la lumière froide qui entre par les interstices des
## planches. Purement visuel : aucune collision, aucune navigation, aucun
## état réseau (tout se déduit du masque des planches, déjà diffusé, et de la
## phase de la manche) ; aspect déterministe tiré de la graine de la fenêtre.
## Cible : docs/art/gemini_target.webp (docs/ART_DIRECTION.md « Fenêtres :
## le dehors »).
##
## * Carte du dehors (« Outside », window_outside.gdshader, UN dessin) :
##   fenêtre : vitres crasseuses (certaines fêlées ou cassées), brume
##   rétroéclairée bleu-vert, silhouettes de zombies qui passent et parfois se
##   collent à la vitre ; porte : couloir sombre au néon qui grésille. Parallaxe :
##   la profondeur est simulée dans le shader.
## * Cadre cubique (« Frame », cubes de 5 cm, matériau du décor) : châssis et
##   petits bois de la fenêtre, chambranle de la porte.
## * Faisceaux : projecteur bleu-vert (« Shaft ») derrière la poche, sans
##   ombre, dont la texture de projection est l'ouverture vue de la source,
##   planches présentes en noir (gap_mask, refaite à chaque planche arrachée ou
##   reposée) : raies de lumière au sol de la salle et, avec la brume
##   volumétrique, faisceaux visibles ; grains de poussière (« Motes ») allumés
##   seulement dans ces raies.
## * Lueur de la poche (« OutsideGlow ») : les zombies qui attendent dehors se
##   découpent en contre-jour.
## * Silhouettes : moins nombreuses entre deux manches, éteintes (fondu) quand
##   la fenêtre est grande ouverte (le vrai zombie passe).
## * Préréglage LOW : carte fixe seulement (ni silhouettes, ni faisceau, ni
##   poussière) ; au loin, tout s'efface (visibility_range).
##
## Repère : celui de la Barricade (+Z vers la salle, X le long du mur, origine
## au sol au milieu du mur).

## Couleur du dehors par défaut (bleu-vert de WorldLook, plus lumineux).
const TINT := Color(0.36, 0.62, 0.64)
## Accroche des ambiances de pièce : Callable(zone: String) -> Color ; vide
## ou couleur transparente : TINT.
static var mood_provider: Callable

## Recherche du mur du fond de la poche (m depuis la face extérieure du mur).
const PROBE_DEPTH := 9.0
const PROBE_HEIGHT := 1.6
## Poche sans fond trouvé (dehors ouvert, test sans carte) : fond supposé à
## cette distance de la face extérieure du mur.
const DEFAULT_BACK := 2.0
## La carte est décollée du mur (le cadre fait 10 cm) : la vitre au milieu.
const CARD_GAP := 0.1
const FRAME_DEPTH := 3  # cubes
## Fenêtre du fond : bas de la vitre, largeur et hauteur bornées (m).
const GLASS_BOTTOM := 0.9
const GLASS_TOP := 2.45
const GLASS_WIDTH := Vector2(0.8, 2.0)
## Sol du dehors au-dessus de celui de la salle, derrière une fenêtre (m).
const OUTSIDE_GROUND := 0.5
## Porte : couloir haut de 2,2 m au plus.
const CORRIDOR_HEIGHT := 2.2
## Texture de l'ouverture (gap_mask) et du projecteur.
const MASK_RES := Vector2i(32, 48)
const PROJ_RES := 64
## Disparition au loin (m).
const FAR := 36.0
const SHAFT_FAR := 20.0
const MOTES := 40
## Projecteur (énergie, sans atténuation) ; faisceaux visibles : longueur dans
## la salle (m) et intensité.
const SHAFT_ENERGY := 1.6
const BEAM_LENGTH := 3.2
const BEAM_ENERGY := 0.08
## Porte : faisceau et projecteur plus faibles.
const DOOR_LIGHT := 0.5
## Activité des silhouettes : manche en cours, entre deux manches.
const ACTIVE := 1.0
const CALM := 0.35
## Vitesse du fondu de l'activité (par seconde).
const FADE_RATE := 0.6

var barricade: Barricade
## Profondeur du fond de la poche (z local, négatif) ; demi-largeur dégagée ;
## hauteur du plafond (m au-dessus du sol de l'ouverture).
var back_z := 0.0
var half_width := 1.5
var ceil_y := MapBuilder.WALL_HEIGHT
## Vrai si un mur a été trouvé derrière (sinon : pas de carte).
var has_back := false
## Carte : taille, milieu (repère local) ; vitres.
var card_size := Vector2.ZERO
var card_center := Vector3.ZERO
var params := {}
## Activité actuelle et visée des silhouettes.
var activity := 0.0
var _target := 0.0
var live := true
## Captures (tests) : activité imposée (>= 0), sinon celle du jeu.
var activity_override := -1.0

var card: MeshInstance3D
var frame: MeshInstance3D
var shaft: SpotLight3D
var beams: MeshInstance3D
var motes: MultiMeshInstance3D
var glow: OmniLight3D
var mask_image: Image
var _mask_tex: ImageTexture
var _proj_tex: ImageTexture
var _motes_mat: ShaderMaterial
var _beams_mat: ShaderMaterial
var _proj_index := PackedInt32Array()
var _poll := 0.0

static var _card_mat: ShaderMaterial
static var _frames: Dictionary = {}


func _init(b: Barricade = null) -> void:
	barricade = b
	name = "Outside"


func _ready() -> void:
	add_to_group(RenderQuality.GROUP)
	_build_glow()
	# Le mur du fond se mesure sur la géométrie de la carte (collisions du
	# monde), prête à l'image de physique suivante.
	_place_deferred.call_deferred()


func _place_deferred() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var probe := probe_pocket()
	place(probe.x, probe.y, probe.z, probe.w > 0.5)


# --------------------------------------------------------------------------
# Paramètres déterministes (testés)
# --------------------------------------------------------------------------

## Aspect du dehors d'une fenêtre de graine `s` (le même sur toutes les
## machines) : graine du shader, vitres (colonnes, rangées), vitres cassées et
## fêlées (bits), position de la source de lumière le long du mur.
static func params_for(s: int, door := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([s, "outside"])
	var seed4 := Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf())
	var cols := 2 + rng.randi() % 2
	var rows := 2
	var n := cols * rows
	var broken := 0
	var cracked := 0
	if not door:
		# Une à deux vitres cassées, une à deux fêlées (jamais toutes).
		var order := range(n)
		for i in range(n - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var tmp: int = order[i]
			order[i] = order[j]
			order[j] = tmp
		var nb := 1 + rng.randi() % 2
		var nc := 1 + int(rng.randi() % 4 == 0)
		for k in nb:
			broken |= 1 << int(order[k])
		for k in nc:
			cracked |= 1 << int(order[nb + k])
	return {"seed": seed4, "panes": Vector2(cols, rows), "broken": broken, "cracked": cracked,
		"light_x": snappedf(rng.randf_range(-0.3, 0.3), 0.05)}


## Couleur du dehors de la zone `zone` (ambiance de la pièce si un système
## d'ambiances la fournit, sinon TINT).
static func tint_for(zone: String) -> Color:
	if mood_provider.is_valid():
		var c: Variant = mood_provider.call(zone)
		if c is Color and (c as Color).a > 0.0:
			return c
	return TINT


## Activité visée des silhouettes : `active` (manche en cours ou non), planches
## présentes `planks` sur `total`. Fenêtre grande ouverte : 0 (le vrai zombie
## passe, on ne mélange pas les deux) ; moins de planches, moins d'agitation
## derrière (l'attention va aux vrais).
static func activity_for(active: bool, planks: int, total: int) -> float:
	if planks <= 0 or total <= 0:
		return 0.0
	var base := ACTIVE if active else CALM
	return base * (0.5 + 0.5 * float(planks) / float(total))


## Ouverture (repère local, plan des planches) : x0, y0, largeur, hauteur.
static func opening_rect(b: Barricade) -> Rect2:
	if b.is_door():
		return Rect2(-b.width * 0.5, 0.0, b.width, b.opening_height)
	var w := b.barrier_width if b.barrier_width > 0.0 else 1.0
	var top := minf(Barricade.LINTEL_BOTTOM, b.opening_height)
	return Rect2(b.barrier_off - w * 0.5, Barricade.SILL_TOP, w, top - Barricade.SILL_TOP)


## Ce qui bouche l'ouverture (repère local, x / y) : planches présentes
## (masque `m`), battants cassés d'une porte (jusqu'à LEAF_TOP).
static func blockers(b: Barricade, m: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in b.plank_count:
		if (m >> i) & 1 == 0:
			continue
		var bb: AABB = b._rest[i] * b.plank_mesh_of(i).get_aabb()
		out.append(Rect2(bb.position.x, bb.position.y, bb.size.x, bb.size.y))
	if b.is_door():
		out.append(Rect2(-b.width * 0.5, 0.0, b.width, ZombieDoorModel.LEAF_TOP))
	return out


## Masque de l'ouverture `area` (repère local) : MASK_RES texels, 255 = jour
## (aucun bloc `rects` devant), 0 = planche ; ligne 0 en haut.
static func gap_mask(area: Rect2, rects: Array[Rect2], res := MASK_RES) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(res.x * res.y)
	for j in res.y:
		var y := area.end.y - (j + 0.5) * area.size.y / res.y
		for i in res.x:
			var x := area.position.x + (i + 0.5) * area.size.x / res.x
			var open := true
			for r in rects:
				if r.has_point(Vector2(x, y)):
					open = false
					break
			out[j * res.x + i] = 255 if open else 0
	return out


## Part de jour dans un masque (0..1).
static func open_fraction(m: PackedByteArray) -> float:
	if m.is_empty():
		return 0.0
	var n := 0
	for v in m:
		if v > 127:
			n += 1
	return float(n) / m.size()


# --------------------------------------------------------------------------
# Placement
# --------------------------------------------------------------------------

## Mesure la poche derrière l'ouverture sur la géométrie de la carte :
## (z du mur du fond, demi-largeur dégagée, hauteur du plafond, mur trouvé).
func probe_pocket() -> Vector4:
	var b := barricade
	var outer := b.barrier_mid - b.barrier_depth * 0.5
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var bz := outer - DEFAULT_BACK
	var found := false
	var hw := 1.5
	var cy := MapBuilder.WALL_HEIGHT
	if space == null:
		return Vector4(bz, hw, cy, 0.0)
	var from := Vector3(0.0, PROBE_HEIGHT, outer - 0.05)
	var hit := _ray(space, from, from + Vector3(0, 0, -PROBE_DEPTH))
	if not hit.is_empty():
		bz = to_local(hit.position).z
		found = true
	var mid := Vector3(0.0, PROBE_HEIGHT, bz + 0.3)
	var l := _ray(space, mid, mid + Vector3(-3.0, 0, 0))
	var r := _ray(space, mid, mid + Vector3(3.0, 0, 0))
	hw = minf(3.0 if l.is_empty() else -to_local(l.position).x, 3.0 if r.is_empty() else to_local(r.position).x)
	var up := _ray(space, Vector3(0.0, 1.0, bz + 0.3), Vector3(0.0, 6.0, bz + 0.3))
	if not up.is_empty():
		cy = to_local(up.position).y
	return Vector4(bz, hw, cy, 1.0 if found else 0.0)


## Rayon contre le monde seul (couche 1 : ni joueurs, ni zombies, ni barrières),
## de `a` à `b` en repère local.
func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(to_global(a), to_global(b), 1)
	q.hit_back_faces = false
	return space.intersect_ray(q)


## Construit la carte, le cadre, le faisceau et la poussière pour une poche au
## fond en `bz` (z local), dégagée sur ±`hw`, sous un plafond à `cy`.
## `found` faux : dehors ouvert (aucun mur derrière), pas de carte.
func place(bz: float, hw: float, cy: float, found: bool) -> void:
	back_z = bz
	half_width = hw
	ceil_y = cy
	has_back = found
	var b := barricade
	params = params_for(b.seed, b.is_door())
	var tint := tint_for(b.zone)
	if found:
		var w: float
		var y0: float
		var y1: float
		if b.is_door():
			w = clampf(snappedf(minf(b.width + 0.2, 2.0 * hw - 0.3), 0.1), 0.9, 2.4)
			y0 = 0.0
			y1 = minf(CORRIDOR_HEIGHT, cy - 0.2)
		else:
			w = clampf(snappedf(2.0 * hw - 0.5, 0.1), GLASS_WIDTH.x, GLASS_WIDTH.y)
			y0 = GLASS_BOTTOM
			y1 = minf(GLASS_TOP, cy - 0.3)
		if y1 - y0 >= 0.6 and 2.0 * hw >= w * 0.5:
			card_size = Vector2(w, snappedf(y1 - y0, 0.05))
			card_center = Vector3(snappedf(float(params.light_x) * 0.5, 0.05) if not b.is_door() else 0.0,
					y0 + card_size.y * 0.5, bz + CARD_GAP)
			_build_card(tint)
			_build_frame()
	# Lueur de la poche : devant la carte (ou au fond supposé).
	glow.position = Vector3(0.0, 2.0, maxf(bz + 0.6, b.barrier_mid - b.barrier_depth * 0.5 - 1.4))
	glow.light_color = tint.lerp(Color(0.45, 0.55, 0.78), 0.3)
	_build_shaft(tint)
	_build_beams(tint)
	_build_motes(tint)
	apply_quality(RenderQuality.current())
	refresh_mask()
	_target = _target_activity()
	activity = _target
	_push_activity()
	set_process(true)


func _build_glow() -> void:
	glow = OmniLight3D.new()
	glow.name = "OutsideGlow"
	glow.light_color = Color(0.45, 0.55, 0.78)
	glow.light_energy = 0.55
	glow.omni_range = 3.2
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 22.0
	glow.distance_fade_length = 6.0
	glow.position = Vector3(0, 2.0, -1.4)
	add_child(glow)


static func card_material() -> ShaderMaterial:
	if _card_mat == null:
		_card_mat = ShaderMaterial.new()
		_card_mat.shader = load("res://assets/shaders/window_outside.gdshader")
	return _card_mat


func _build_card(tint: Color) -> void:
	var q := QuadMesh.new()
	q.size = card_size
	card = MeshInstance3D.new()
	card.name = "OutsideCard"
	card.mesh = q
	card.material_override = card_material()
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.position = card_center
	card.visibility_range_end = FAR
	card.visibility_range_end_margin = 4.0
	card.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var p := params
	card.set_instance_shader_parameter("wo_seed", p.seed)
	card.set_instance_shader_parameter("wo_tint", tint)
	card.set_instance_shader_parameter("wo_size", card_size)
	# Fenêtre : le sol du dehors est plus haut que celui de la salle (la poche
	# est en contrebas, comme un soupirail) : les silhouettes passent au
	# milieu de la vitre, pas sous l'appui.
	card.set_instance_shader_parameter("wo_floor", card_center.y - (0.0 if barricade.is_door() else OUTSIDE_GROUND))
	card.set_instance_shader_parameter("wo_mode", 1.0 if barricade.is_door() else 0.0)
	card.set_instance_shader_parameter("wo_panes", p.panes)
	card.set_instance_shader_parameter("wo_broken", float(p.broken))
	card.set_instance_shader_parameter("wo_cracked", float(p.cracked))
	add_child(card)


## Cadre cubique autour de la carte (partagé par taille et type).
func _build_frame() -> void:
	var door := barricade.is_door()
	var key := [card_size, params.panes, door]
	var m: ArrayMesh = _frames.get(key)
	if m == null:
		m = frame_mesh(card_size, params.panes, door)
		_frames[key] = m
	frame = MeshInstance3D.new()
	frame.name = "OutsideFrame"
	frame.mesh = m
	frame.material_override = VoxelBuild.material()
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Collé au mur du fond (le dos du cadre sur le mur).
	frame.position = Vector3(card_center.x, card_center.y, back_z)
	frame.visibility_range_end = FAR
	frame.visibility_range_end_margin = 4.0
	frame.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(frame)


## Cadre en cubes de 5 cm d'une vitre (ou d'une porte) de taille `size` :
## châssis de 2 cubes, petits bois d'un cube entre les vitres `panes`, appui
## en saillie ; porte : chambranle de 3 cubes et seuil. Origine : milieu de
## l'ouverture, dos du cadre (contre le mur) en z = 0, +Z vers la salle.
@warning_ignore("integer_division")
static func frame_mesh(size: Vector2, panes: Vector2, door := false) -> ArrayMesh:
	var vb := VoxelBuild.new()
	var nx := VoxelBuild.cubes(size.x)
	var ny := VoxelBuild.cubes(size.y)
	var bw := 3 if door else 2
	var base := VoxelBuild.col("door_frame") if door else VoxelBuild.col("metal_dark").lerp(VoxelBuild.col("rust"), 0.25)
	var x0 := -nx / 2 - bw
	var x1 := nx - nx / 2 + bw
	# Montants et traverses (z 0..FRAME_DEPTH-1).
	vb.fill(x0, x0 + bw, 0, ny + (bw if not door else bw), 0, FRAME_DEPTH, base, 31)
	vb.fill(x1 - bw, x1, 0, ny + bw, 0, FRAME_DEPTH, base, 32)
	vb.fill(x0, x1, ny, ny + bw, 0, FRAME_DEPTH, base, 33)
	if door:
		# Seuil sombre.
		vb.fill(x0, x1, -1, 0, 0, FRAME_DEPTH + 1, VoxelBuild.col("metal_dark"), 34)
	else:
		vb.fill(x0, x1, -bw, 0, 0, FRAME_DEPTH, base, 35)
		# Appui en saillie d'un cube de plus.
		vb.fill(x0 - 1, x1 + 1, -bw - 1, -bw + 1, 0, FRAME_DEPTH + 2, VoxelBuild.tone(base, 0.85), 36)
		# Petits bois (couche de devant : la vitre est derrière).
		var cols := int(panes.x)
		var rows := int(panes.y)
		for k in range(1, cols):
			var x := -nx / 2 + nx * k / cols
			vb.fill(x, x + 1, 0, ny, 1, FRAME_DEPTH, base, 37 + k)
		for k in range(1, rows):
			var y := ny * k / rows
			vb.fill(-nx / 2, nx - nx / 2, y, y + 1, 1, FRAME_DEPTH, base, 41 + k)
	# Le bas de la vitre (y = 0) est au milieu de la carte - size.y / 2.
	return vb.mesh(Vector3(0.0, -size.y * 0.5, 0.0))


## Projecteur sans ombre derrière la poche, vers l'ouverture : sa texture de
## projection (gap_mask vue depuis la source) découpe les raies de lumière au
## sol de la salle. Pas de brume volumétrique (elle ignore la texture de
## projection : un cône plein à travers le mur) : les faisceaux visibles sont
## marchés par window_beams.gdshader.
func _build_shaft(tint: Color) -> void:
	var b := barricade
	var area := opening_rect(b)
	shaft = SpotLight3D.new()
	shaft.name = "Shaft"
	shaft.light_color = tint.lerp(Color(0.8, 0.95, 1.0), 0.3)
	shaft.light_energy = SHAFT_ENERGY * (DOOR_LIGHT if b.is_door() else 1.0)
	shaft.light_volumetric_fog_energy = 0.0
	shaft.shadow_enabled = false
	shaft.light_specular = 0.25
	var outer := b.barrier_mid - b.barrier_depth * 0.5
	# Source haute et lointaine (lumière du dehors, rayons presque parallèles).
	var src := Vector3(area.get_center().x + float(params.light_x), area.end.y + 1.1, outer - 3.2)
	var aim := Vector3(area.get_center().x, area.position.y + area.size.y * 0.4, b.barrier_mid)
	shaft.transform = Transform3D(Basis.looking_at(aim - src, Vector3.UP), src)
	# Cône : couvre l'ouverture vue de la source (+ marge).
	var ang := 0.0
	var fwd := (aim - src).normalized()
	for cx in [area.position.x, area.end.x]:
		for cy2 in [area.position.y, area.end.y]:
			var d := (Vector3(cx, cy2, _plane_z()) - src).normalized()
			ang = maxf(ang, acos(clampf(d.dot(fwd), -1.0, 1.0)))
	shaft.spot_angle = rad_to_deg(ang) + 3.0
	shaft.spot_angle_attenuation = 0.2
	# Lumière du dehors : pas d'atténuation avec la distance (rayons parallèles).
	shaft.spot_range = 12.0
	shaft.spot_attenuation = 0.0
	shaft.distance_fade_enabled = true
	shaft.distance_fade_begin = SHAFT_FAR
	shaft.distance_fade_length = 5.0
	add_child(shaft)
	_proj_index = projector_index(area)


## Plan des planches (z local).
func _plane_z() -> float:
	return Barricade.DOOR_PLANK_Z if barricade.is_door() else Barricade.PLANK_Z


## Faces extérieure et intérieure du mur percé (z local).
func _faces() -> Vector2:
	var b := barricade
	return Vector2(b.barrier_mid - b.barrier_depth * 0.5, b.barrier_mid + b.barrier_depth * 0.5)


## Faisceaux visibles : boîte devant l'ouverture (de la couche des planches à
## BEAM_LENGTH dans la salle), marchée par window_beams.gdshader.
func _build_beams(tint: Color) -> void:
	var area := opening_rect(barricade)
	var src := shaft.position
	var f := _faces()
	var z1 := f.y + BEAM_LENGTH
	# Boîte : l'ouverture et son image au bout du faisceau, vues de la source.
	var lo := Vector3(area.position.x, 0.0, _plane_z() - 0.05)
	var hi := Vector3(area.end.x, area.end.y, z1)
	for cx in [area.position.x, area.end.x]:
		for cy in [area.position.y, area.end.y]:
			var d := Vector3(cx, cy, f.x) - src
			var p := src + d * ((z1 - src.z) / d.z)
			lo.x = minf(lo.x, p.x)
			hi.x = maxf(hi.x, p.x)
	lo.x -= 0.05
	hi.x += 0.05
	var bm := BoxMesh.new()
	bm.size = hi - lo
	_beams_mat = ShaderMaterial.new()
	_beams_mat.shader = load("res://assets/shaders/window_beams.gdshader")
	_beams_mat.set_shader_parameter("light_pos", src)
	_beams_mat.set_shader_parameter("plane_z", _plane_z())
	_beams_mat.set_shader_parameter("faces", f)
	_beams_mat.set_shader_parameter("area", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	_beams_mat.set_shader_parameter("box_min", lo)
	_beams_mat.set_shader_parameter("box_max", hi)
	_beams_mat.set_shader_parameter("color", tint.lerp(Color(0.85, 0.95, 1.0), 0.35))
	# Porte : la cour est plus sombre qu'un dehors derrière une vitre.
	_beams_mat.set_shader_parameter("energy", BEAM_ENERGY * (DOOR_LIGHT if barricade.is_door() else 1.0))
	_beams_mat.set_shader_parameter("offset", (lo + hi) * 0.5)
	beams = MeshInstance3D.new()
	beams.name = "Beams"
	beams.mesh = bm
	beams.position = (lo + hi) * 0.5
	beams.material_override = _beams_mat
	beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beams.visibility_range_end = SHAFT_FAR
	beams.visibility_range_end_margin = 4.0
	beams.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(beams)


## Grains de poussière : cubes de 2,5 cm qui flottent devant l'ouverture,
## allumés seulement dans les raies (window_motes.gdshader).
func _build_motes(tint: Color) -> void:
	var area := opening_rect(barricade)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * VoxelBuild.CUBE * 0.5
	mm.mesh = cube
	mm.instance_count = MOTES
	for i in MOTES:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	_motes_mat = ShaderMaterial.new()
	_motes_mat.shader = load("res://assets/shaders/window_motes.gdshader")
	var f := _faces()
	var bmin := Vector3(area.position.x - 0.4, 0.3, f.y + 0.05)
	var bsize := Vector3(area.size.x + 0.8, area.end.y - 0.3, BEAM_LENGTH * 0.8)
	_motes_mat.set_shader_parameter("light_pos", shaft.position)
	_motes_mat.set_shader_parameter("plane_z", _plane_z())
	_motes_mat.set_shader_parameter("faces", f)
	_motes_mat.set_shader_parameter("area", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	_motes_mat.set_shader_parameter("box_min", bmin)
	_motes_mat.set_shader_parameter("box_size", bsize)
	_motes_mat.set_shader_parameter("color", tint.lerp(Color.WHITE, 0.5))
	motes = MultiMeshInstance3D.new()
	motes.name = "Motes"
	motes.multimesh = mm
	motes.material_override = _motes_mat
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.custom_aabb = AABB(bmin, bsize)
	motes.visibility_range_end = 12.0
	motes.visibility_range_end_margin = 2.0
	motes.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(motes)


# --------------------------------------------------------------------------
# Planches, activité, qualité
# --------------------------------------------------------------------------

## Planches arrachées ou reposées (Barricade.set_mask) : masque de l'ouverture
## (faisceaux, poussière) et texture du projecteur refaits, activité revue.
func refresh_mask() -> void:
	if shaft == null:
		return
	var area := opening_rect(barricade)
	var m := gap_mask(area, blockers(barricade, barricade.mask))
	mask_image = Image.create_from_data(MASK_RES.x, MASK_RES.y, false, Image.FORMAT_L8, m)
	if _mask_tex == null:
		_mask_tex = ImageTexture.create_from_image(mask_image)
		_motes_mat.set_shader_parameter("gap_mask", _mask_tex)
		_beams_mat.set_shader_parameter("gap_mask", _mask_tex)
	else:
		_mask_tex.update(mask_image)
	var proj := Image.create_from_data(PROJ_RES, PROJ_RES, false, Image.FORMAT_L8, projector_data(m, _proj_index))
	if _proj_tex == null:
		_proj_tex = ImageTexture.create_from_image(proj)
		shaft.light_projector = _proj_tex
	else:
		_proj_tex.update(proj)
	_target = _target_activity()
	set_process(true)


## Pour chaque texel de la texture de projection (PROJ_RES², repère de la
## lumière, perspective d'angle 2 × spot_angle ; ligne 0 = BAS du cône) :
## texel du masque de l'ouverture que touche ce rayon dans le plan des
## planches, ou -1 si le mur l'arrête (faces extérieure et intérieure de
## l'embrasure). Calculé une fois ; le masque change, pas la géométrie.
func projector_index(area: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(PROJ_RES * PROJ_RES)
	var tn := tan(deg_to_rad(shaft.spot_angle))
	var xf := shaft.transform
	var pz := _plane_z()
	var f := _faces()
	for j in PROJ_RES:
		for i in PROJ_RES:
			var lx := ((i + 0.5) / PROJ_RES * 2.0 - 1.0) * tn
			var ly := ((j + 0.5) / PROJ_RES * 2.0 - 1.0) * tn
			var d := xf.basis * Vector3(lx, ly, -1.0)
			var k := -1
			if d.z > 0.001:
				var po := xf.origin + d * ((f.x - xf.origin.z) / d.z)
				var p_in := xf.origin + d * ((f.y - xf.origin.z) / d.z)
				if area.has_point(Vector2(po.x, po.y)) and area.has_point(Vector2(p_in.x, p_in.y)):
					var p := xf.origin + d * ((pz - xf.origin.z) / d.z)
					var mi := clampi(int((p.x - area.position.x) / area.size.x * MASK_RES.x), 0, MASK_RES.x - 1)
					var mj := clampi(int((area.end.y - p.y) / area.size.y * MASK_RES.y), 0, MASK_RES.y - 1)
					k = mj * MASK_RES.x + mi
			out[j * PROJ_RES + i] = k
	return out


## Texture de projection d'après le masque `m` et l'index `idx`.
static func projector_data(m: PackedByteArray, idx: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(idx.size())
	for t in idx.size():
		var k := idx[t]
		out[t] = m[k] if k >= 0 else 0
	return out


func _target_activity() -> float:
	if activity_override >= 0.0:
		return activity_override
	if not live:
		return 0.0
	var g := Game.instance
	var active := g != null and is_instance_valid(g) and g.rounds != null and g.rounds.phase == RoundManager.Phase.ACTIVE
	return activity_for(active, barricade.planks(), barricade.plank_count)


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		_target = _target_activity()
	if is_equal_approx(activity, _target):
		return
	activity = move_toward(activity, _target, FADE_RATE * delta)
	_push_activity()


func _push_activity() -> void:
	if card:
		card.set_instance_shader_parameter("wo_activity", activity)


## RenderQuality : LOW = carte fixe seulement (ni silhouettes, ni raies, ni
## faisceaux, ni poussière).
func apply_quality(q: Dictionary) -> void:
	live = bool(q.get("window_life", true))
	if card:
		card.set_instance_shader_parameter("wo_live", 1.0 if live else 0.0)
	for n: Node3D in [shaft, beams, motes]:
		if n:
			n.visible = live
	_target = _target_activity()
	if not live:
		activity = 0.0
		_push_activity()
