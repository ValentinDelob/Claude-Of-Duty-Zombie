class_name MysteryBox
extends Interactable
## CAISSE AU HASARD (GAME_CONCEPT §4.12 bis ; nom interne hérité de la boîte
## mystère de BO1). Payée en ferraille, elle ne donne QUE des objets à lancer
## ou à poser (ThrowableRules.CRATE_ITEMS : grenade, peluche leurre…), rangés
## sur l'emplacement de grenade : jamais une arme, rien n'entre dans l'arsenal.
##
## Une seule caisse FIXE par carte (Game._build_mystery_box) : plus de
## déménagement ni d'ours en peluche, plus de liquidation, plus de tableaux à
## la craie. Le serveur tire l'objet dès l'achat ; les clients jouent
## l'animation de défilement puis affichent le résultat.
##
## États : IDLE (achetable) -> ROLLING -> READY (seul l'acheteur peut prendre
## l'objet) -> IDLE.

enum State { IDLE, ROLLING, READY }

## Prix PROVISOIRE (ancien prix de la boîte mystère), en ferraille.
const COST := 950
const ROLL_TIME := 4.2
## Objet offert : reprise possible 12 s (treasure_chest_timeout de BO1).
const READY_TIME := 12.0

## Apparence (BoxModel). Couvercle : charnière sur l'arête arrière haute,
## ouvert presque à la verticale (au-delà, il entrerait dans le mur).
const LID_HINGE := Vector3(0, 0.75, -0.42)
const LID_OPEN_ANGLE := -1.5
## Ouvert, le couvercle (11,5 cm d'épaisseur au-dessus de la charnière)
## bascule derrière l'arrière du coffre : le centre de la caisse est posé à
## SPOT_WALL_GAP du mur pour qu'il ne s'y enfonce pas.
const SPOT_WALL_GAP := 0.57
## Collision du coffre (longueur, hauteur, profondeur), centrée sur la caisse
## et posée au sol ; l'éditeur retire aussi cette emprise du navmesh pour une
## caisse posée au sol (MapLayoutExport, « nav_blocks »).
const BODY_SIZE := Vector3(1.8, 0.85, 0.85)
## Point visé au-dessus du milieu du coffre (juste au-dessus du couvercle
## fermé) : invite et achat d'une caisse posée au sol, et la ligne de vue de
## toutes les caisses (jamais à travers un mur, sight_ok).
const SIGHT_HEIGHT := 0.95
## Colonne de lumière : pâle, bleutée, douce ; posée sur le couvercle, elle
## s'éteint en montant (sommet à 3,2 m, sous les plafonds).
const BEAM_COLOR := Color(0.62, 0.76, 1.0)
const BEAM_INTENSITY := 0.06
const BEAM_RADIUS := 0.3
const BEAM_BOTTOM := 0.9
const BEAM_HEIGHT := 2.3
## Lumière : faible et froide fermée (lisible dans le noir sans tache sur
## les murs), chaude et dorée quand le fond s'allume. Au-dessus de l'avant
## du coffre, à l'écart de l'objet affiché.
const LIGHT_POS := Vector3(0, 1.5, 0.5)
const LIGHT_RANGE := 3.0
const LIGHT_IDLE_ENERGY := 0.3
const LIGHT_OPEN_ENERGY := 1.0
const LIGHT_IDLE_COLOR := Color(0.72, 0.82, 1.0)
## Fond lumineux, halo et lampe du coffre ouvert.
const GLOW_COLOR := Color(1.0, 0.86, 0.62)
## Halo doré qui monte du coffre ouvert (pendant le tirage).
const HAZE_INTENSITY := 0.16
const HAZE_HEIGHT := 0.9
## Objet affiché au-dessus du coffre, agrandi pour être lisible.
const DISPLAY_SCALE := 2.6

var state: State = State.IDLE
## Objet tiré (identifiant de ThrowableRules.CRATE_ITEMS), "" sinon.
var item := ""
var owner_pid := 0
var uses := 0
## Tests : force le prochain tirage (identifiant d'objet).
var force_result := ""

## Emplacement : {pos, normal, floor}.
var spot: Dictionary = {}
var _root: Node3D
## Collision du coffre (couche du monde ; au sol, aussi MeshNav.LOW_LAYER).
var _body: StaticBody3D
var _lid: Node3D
var _beam: MeshInstance3D
## Halo doré au-dessus du coffre ouvert.
var _haze: MeshInstance3D
var _light: OmniLight3D
## Maillages qui s'éclairent à l'ouverture (fond lumineux, intérieur).
var _open_meshes: Array[GeometryInstance3D] = []
## 0 = fermée, 1 = ouverte (suit le couvercle, lissé).
var _open_amount := 0.0
var _display: Node3D
var _display_model: Node3D
var _timer := 0.0
var _cycle_t := 0.0
var _rng := RandomNumberGenerator.new()
## Collisions de la caisse (créées une fois, _collider) : exclues du rayon de
## sight_ok, sans parcourir l'arbre à chaque image de visée.
var _own_rids: Array[RID] = []
## État affiché (apply_state) : sur le serveur, `state` est déjà modifié quand
## l'état diffusé revient (call_local).
var _shown_state: State = State.IDLE


## Emplacement de la caisse : `m.wall` pointe vers le mur, dont m.pos est à
## m.wall_gap. Caisse posée au sol (éditeur, format 15) : mur fictif derrière
## elle, « floor ».
func setup_spot(m: MapMarker) -> void:
	interact_id = "box"
	name = "MysteryBox"
	interact_range = 2.0
	spot = {"pos": m.pos + m.wall * (m.wall_gap - SPOT_WALL_GAP), "normal": m.wall, "floor": bool(m.data.get("floor", false))}
	_rng.randomize()


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = LID_HINGE
	_root.add_child(_lid)
	# Caisse de matériel cubique cerclée d'acier (BoxModel).
	_open_meshes = BoxModel.build(_root, _lid)
	# Colonne de lumière douce qui signale la caisse de loin.
	_beam = BoxModel.build_beam()
	_root.add_child(_beam)
	_haze = BoxModel.build_haze()
	_root.add_child(_haze)
	# Lumière de lisibilité : faible et froide couvercle fermé, chaude quand
	# le fond s'allume ; portée courte, presque rien dans la brume.
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_IDLE_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.6
	_light.light_energy = LIGHT_IDLE_ENERGY
	_light.light_volumetric_fog_energy = 0.15
	_light.light_specular = 0.3
	_light.position = LIGHT_POS
	_root.add_child(_light)
	_display = Node3D.new()
	_display.position = Vector3(0, 1.05, 0)
	_root.add_child(_display)
	_body = _collider(BODY_SIZE)
	_root.add_child(_body)
	_place()


func _collider(size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")  # impacts de balles (Fx.surface_at)
	_own_rids.append(body.get_rid())
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	return body


## Cellules occupées par un emplacement de carte ASCII (la caisse fait 3 cases
## de long).
static func spot_cells(c: Vector2i, data: MapData) -> Array:
	var n := MapDef.wall_normal(data, c)
	var along := Vector2i(1, 0) if absf(n.z) > 0.5 else Vector2i(0, 1)
	return [c - along, c, c + along]


func _place() -> void:
	position = spot.pos
	basis = Basis.looking_at(-spot.normal, Vector3.UP).rotated(Vector3.UP, PI)
	if _body != null:
		# Posée au sol : obstacle bas que les zombies contournent (MeshNav.LOW_LAYER).
		_body.collision_layer = 1 | (MeshNav.LOW_LAYER if bool(spot.get("floor", false)) else 0)


# --------------------------------------------------------------------------
# Interaction
# --------------------------------------------------------------------------

func interact_point() -> Vector3:
	if bool(spot.get("floor", false)):
		# Caisse posée au sol (format 15) : on l'utilise de tous les côtés
		# (déclencheur autour du coffre) : le point visé est son milieu.
		return global_position + Vector3.UP * SIGHT_HEIGHT
	return global_position - (spot.normal as Vector3) * 0.7 + Vector3.UP * 0.9


## Ligne de vue de l'œil `eye` jusqu'au-dessus du coffre (couche du monde :
## murs, portes fermées, machines ; ni joueurs ni zombies ; la caisse ne
## compte pas) : jamais d'achat à travers un mur.
func sight_ok(eye: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(eye, global_position + Vector3.UP * SIGHT_HEIGHT, 1, _own_rids)
	return space.intersect_ray(q).is_empty()


func own_rids() -> Array[RID]:
	return _own_rids


func prompt(pid: int) -> String:
	match state:
		State.IDLE:
			return Lang.t("[F] Caisse %s", "[F] Crate %s") % Interactable.cost_text(COST)
		State.READY:
			if pid == owner_pid:
				return Lang.t("[F] Prendre %s", "[F] Take %s") % item_name(item)
	return ""


## Nom affiché d'un objet de la caisse.
static func item_name(id: String) -> String:
	var it := ThrowableRules.crate_item(id)
	return ThrowableRules.kind_name(int(it.kind)) if not it.is_empty() else ""


func srv_use(pid: int) -> void:
	var game := system.game
	var pd := game.session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	match state:
		State.IDLE:
			if not game.session.try_spend(pid, COST):
				system.deny(pid, InteractionSystem.NO_POINTS)
				return
			owner_pid = pid
			uses += 1
			_roll()
			state = State.ROLLING
			_timer = ROLL_TIME
			broadcast_state()
		State.READY:
			if pid != owner_pid:
				return
			var it := ThrowableRules.crate_item(item)
			if not it.is_empty():
				# Emplacement de grenade rempli avec cet objet (jamais l'arsenal).
				game.throwables.srv_fill_slot(pid, int(it.kind))
			_close()


## Serveur : tirage de l'objet (ThrowableRules.CRATE_ITEMS, pondéré).
func _roll() -> void:
	if force_result != "" and not ThrowableRules.crate_item(force_result).is_empty():
		item = force_result
	else:
		item = ThrowableRules.pick_crate_item(_rng)
	force_result = ""


func _close() -> void:
	state = State.IDLE
	owner_pid = 0
	item = ""
	broadcast_state()


func _process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server() or state == State.IDLE:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	match state:
		State.ROLLING:
			state = State.READY
			_timer = READY_TIME
			broadcast_state()
		State.READY:
			_close()


# --------------------------------------------------------------------------
# Réplication et visuels (toutes les machines)
# --------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {"state": state, "item": item, "owner": owner_pid}


func apply_state(s: Dictionary, animate: bool) -> void:
	var prev := _shown_state
	state = s.get("state", State.IDLE)
	_shown_state = state
	item = s.get("item", "")
	owner_pid = s.get("owner", 0)
	match state:
		State.ROLLING:
			_cycle_t = 0.0
			_timer = ROLL_TIME
			if animate:
				Audio.play_3d("box_open", global_position + Vector3.UP, 0.0, 0.03)
				Audio.play_3d("box_music", global_position + Vector3.UP, -2.0, 0.0)
		State.READY:
			_show_model(item)
		State.IDLE:
			_show_model("")
			if animate and prev != State.IDLE:
				Audio.play_3d("box_open", global_position + Vector3.UP, -6.0, 0.1)


func _animate(delta: float) -> void:
	if _lid == null:
		return
	var open := state == State.ROLLING or state == State.READY
	_lid.rotation.x = lerp_angle(_lid.rotation.x, LID_OPEN_ANGLE if open else 0.0, 1.0 - exp(-delta * 6.0))
	var target := 1.0 if open else 0.0
	var amount := lerpf(_open_amount, target, 1.0 - exp(-delta * 4.0))
	if absf(target - amount) < 0.002:
		amount = target
	if amount != _open_amount:
		_open_amount = amount
		_light.light_energy = lerpf(LIGHT_IDLE_ENERGY, LIGHT_OPEN_ENERGY, _open_amount)
		_light.light_color = LIGHT_IDLE_COLOR.lerp(GLOW_COLOR, _open_amount)
		for mi in _open_meshes:
			mi.set_instance_shader_parameter("open", _open_amount)
		_haze.set_instance_shader_parameter("fade", _open_amount)
		_haze.visible = _open_amount > 0.0
	if state == State.ROLLING:
		# Défilement des objets : de plus en plus lent, monte hors de la caisse.
		_cycle_t -= delta
		_timer -= delta if not multiplayer.is_server() else 0.0
		var progress := 1.0 - clampf(_timer / ROLL_TIME, 0.0, 1.0)
		_display.position.y = 0.4 + progress * 0.75
		if _cycle_t <= 0.0:
			_cycle_t = lerpf(0.07, 0.35, progress * progress)
			var items: Array = ThrowableRules.CRATE_ITEMS
			_show_model(String(items[randi() % items.size()].id))
	if _display_model:
		_display.rotation.y += delta * (1.5 if state == State.READY else 0.0)


func _show_model(id: String) -> void:
	if _display_model:
		_display_model.queue_free()
		_display_model = null
	var it := ThrowableRules.crate_item(id)
	if it.is_empty():
		return
	_display_model = Throwable.build_model(int(it.kind), false)
	_display_model.scale = Vector3.ONE * DISPLAY_SCALE
	_display_model.position.y = -0.25
	_display.add_child(_display_model)
