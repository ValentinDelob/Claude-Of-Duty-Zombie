class_name BuildStation
extends Interactable
## Station de construction (GAME_CONCEPT §4.11 ; règles : BuildRules). Une par
## carte, contre un mur, OBLIGATOIRE (MapValidator), accessible à tout moment
## de la partie.
##
## [F] / X à la station ouvre son interface (StationPanel, chez le joueur qui
## l'utilise ; la partie continue) : armes de l'ARSENAL du profil local avec
## leur prix en ferraille, recharge des munitions de l'arme en main, recyclage.
## Quand la construction du joueur est prête, [F] la récupère (une place libre
## dans l'inventaire de partie est nécessaire : Session.give_to_bag).
##
## Le SERVEUR décide de tout (comme la caisse) : joueur debout et à portée de
## la station, arme relue (BuildRules.clean_weapon : le serveur ne connaît pas
## l'arsenal du client, il reconstruit l'exemplaire), niveau, une seule
## construction à la fois par joueur, ferraille dépensée au lancement. La
## station travaille seule : la construction est prête à la fin de la manche
## BuildRules.ready_round (1 à 3 manches selon le prix), sans accélération.
## État de chaque joueur (arme, prix, manche de fin, prête) : message d'état
## des objets (InteractionSystem._cl_state, get_state / apply_state).
##
## Modèle provisoire en blocs alignés sur la grille de 5 cm (§4.19) : établi,
## étagère, panneau à outils, écran et voyant (ambre : libre, bleu : en
## construction, vert : arme prête, pour le joueur local) ; collision :
## CollisionBox (objet de collision du jeu, aucun modèle Blender).

signal builds_changed

const ID := "station"
## Dimensions (m, multiples de 5 cm) : établi 1,6 x 0,8 m, plateau à 1 m.
const WIDTH := 1.6
const DEPTH := 0.8
const TOP := 1.0
const PANEL_TOP := 2.0
## Couleurs du voyant.
const IDLE_COLOR := Color(1.0, 0.62, 0.15)
const BUSY_COLOR := Color(0.25, 0.55, 1.0)
const READY_COLOR := Color(0.15, 1.0, 0.35)

var game: Game
## Constructions par joueur (pid -> {w (GameWeapon), price, round (manche de
## fin), ready}). Sur le serveur : celles qui font foi ; ailleurs : copie reçue.
var builds: Dictionary = {}
## Serveur : demandes de construction et de recharge (un humain en fait peu).
var _limit := NetGuard.Limiter.new(4.0, 6.0)
var _lamp: MeshInstance3D
var _light: OmniLight3D
var _shown_state := ""


func setup_marker(m: MapMarker) -> void:
	interact_id = ID
	name = "BuildStation"
	var wall := Vector3(m.wall.x, 0.0, m.wall.z).normalized() if Vector2(m.wall.x, m.wall.z).length() > 0.01 else Vector3(0, 0, -1)
	# Origine : sur la face du mur, au sol ; +z vers la pièce.
	var face := m.pos + wall * m.wall_gap
	var z := -wall
	var x := Vector3.UP.cross(z).normalized()
	transform = Transform3D(Basis(x, Vector3.UP, z), face)
	interact_range = 2.2


func _ready() -> void:
	game = Game.instance
	var parts := build_model(self)
	_lamp = parts.lamp
	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.light_energy = 0.7
	_light.position = Vector3(0, PANEL_TOP + 0.2, 0.5)
	add_child(_light)
	# Collision : établi et panneau, pavés du jeu (pas de modèle importé).
	add_child(CollisionBox.make(Vector3(0, TOP * 0.5, DEPTH * 0.5), Vector3(WIDTH, TOP, DEPTH), 0.0, false, "metal"))
	add_child(CollisionBox.make(Vector3(0, (TOP + PANEL_TOP) * 0.5, 0.05), Vector3(WIDTH, PANEL_TOP - TOP, 0.1), 0.0, false, "metal"))
	if game and multiplayer.is_server():
		game.rounds.round_ended.connect(_on_round_ended)
	_refresh_lamp()


## Modèle en blocs sous `root` (repère : origine au pied, sur la face du mur,
## +z vers la pièce). Toutes les faces tombent sur la grille de 5 cm
## (tests/test_build_rules.gd, VoxelCheck). Rend {lamp, screen}.
static func build_model(root: Node3D) -> Dictionary:
	var steel := WorldLook.surface("steel")
	var wood := WorldLook.surface("wood")
	var metal := WorldLook.surface("metal")
	# Plateau, pieds, étagère basse.
	_block(root, Vector3(0, 0.95, 0.4), Vector3(WIDTH, 0.1, DEPTH), wood)
	for sx in [-1.0, 1.0]:
		for zc in [0.05, 0.75]:
			_block(root, Vector3(sx * 0.75, 0.45, zc), Vector3(0.1, 0.9, 0.1), steel)
	_block(root, Vector3(0, 0.325, 0.4), Vector3(1.4, 0.05, 0.6), metal)
	# Panneau à outils contre le mur, écran et étau.
	_block(root, Vector3(0, 1.5, 0.05), Vector3(WIDTH, 1.0, 0.1), metal)
	var screen := _block(root, Vector3(-0.35, 1.5, 0.125), Vector3(0.6, 0.4, 0.05), PropBuilder._emissive(Color(0.2, 0.75, 1.0), 1.2))
	_block(root, Vector3(0.45, 1.6, 0.125), Vector3(0.3, 0.1, 0.05), steel)
	_block(root, Vector3(0.55, 1.075, 0.4), Vector3(0.3, 0.15, 0.2), steel)
	# Caisse à pièces sur l'étagère.
	_block(root, Vector3(-0.4, 0.45, 0.4), Vector3(0.4, 0.2, 0.3), wood)
	# Voyant au-dessus du panneau.
	var lamp := _block(root, Vector3(0, 2.05, 0.1), Vector3(0.3, 0.1, 0.1), PropBuilder._emissive(IDLE_COLOR, 3.0))
	return {"lamp": lamp, "screen": screen}


static func _block(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	return mi


func interact_point() -> Vector3:
	return global_position + global_basis.z * (DEPTH + 0.1) + Vector3.UP * 1.1


func prompt(pid: int) -> String:
	var b: Dictionary = builds.get(pid, {})
	if bool(b.get("ready", false)):
		return Lang.t("[F] Récupérer : %s", "[F] Collect: %s") % weapon_name(b.w)
	return Lang.t("[F] Station de construction", "[F] Construction station")


static func weapon_name(w: Dictionary) -> String:
	return WeaponDB.localized(GameWeapon.stats(w).name) if not w.is_empty() else ""


## Construction du joueur local ({} : aucune).
func local_build() -> Dictionary:
	return builds.get(multiplayer.get_unique_id(), {})


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## [F] à la station : récupère l'arme prête (place libre exigée), sinon ouvre
## l'interface du joueur (inventaire plein : message, et l'interface s'ouvre
## pour recycler ou s'organiser).
func srv_use(pid: int) -> void:
	var b: Dictionary = builds.get(pid, {})
	if bool(b.get("ready", false)):
		if game.session.give_to_bag(pid, (b.w as Dictionary).duplicate(true)):
			builds.erase(pid)
			print("[Station] %d récupère %s" % [pid, b.w.id])
			game.interact.purchase_fx(self)
			broadcast_state()
			return
		game.interact.deny(pid, InteractionSystem.BAG_FULL)
	if pid == multiplayer.get_unique_id():
		_cl_open()
	else:
		_cl_open.rpc_id(pid)


## Joueur `pid` à portée de la station (position de référence du serveur) ?
func _srv_near(pid: int) -> bool:
	var p: Player = game.players.get(pid)
	return p != null and InteractionSystem.in_reach(p.srv_origin(), srv_point(), interact_range)


## Lance la construction d'une arme de l'arsenal du client (`wd` : arme de
## partie, voir BuildRules.clean_weapon).
@rpc("any_peer", "call_local", "reliable")
func srv_build(wd: Variant) -> void:
	var pid := NetGuard.alive_sender(self, game, _limit)
	if pid == NetGuard.NO_SENDER:
		return
	if not _srv_near(pid):
		print("[Station] %d trop loin pour construire" % pid)
		return
	var w := BuildRules.clean_weapon(wd)
	var why := BuildRules.build_refusal(game.session.get_data(pid), w, builds.has(pid))
	if why != BuildRules.OK:
		print("[Station] construction refusée (%d) : %s" % [pid, why])
		game.interact.deny(pid, why)
		return
	var cost := BuildRules.price(w)
	if not game.session.try_spend(pid, cost):
		game.interact.deny(pid, InteractionSystem.NO_POINTS)
		return
	var active := game.rounds.phase == RoundManager.Phase.ACTIVE
	builds[pid] = {"w": w, "price": cost, "round": BuildRules.ready_round(game.rounds.round_n, active, cost), "ready": false}
	print("[Station] %d construit %s niv. %d (%d ferraille, prête à la fin de la manche %d)" % [pid, w.id, w.level, cost, builds[pid]["round"]])
	game.interact.purchase_fx(self)
	broadcast_state()


## Recharge les munitions de l'arme en main contre de la ferraille.
@rpc("any_peer", "call_local", "reliable")
func srv_refill() -> void:
	var pid := NetGuard.alive_sender(self, game, _limit)
	if pid == NetGuard.NO_SENDER or not _srv_near(pid):
		return
	var pd := game.session.get_data(pid)
	var w := pd.current_weapon()
	if w.is_empty():
		return
	if BuildRules.ammo_full(w):
		game.interact.deny(pid, InteractionSystem.AMMO_FULL)
		return
	if not game.session.try_spend(pid, BuildRules.refill_price(w)):
		game.interact.deny(pid, InteractionSystem.NO_POINTS)
		return
	GameWeapon.refill(w)
	print("[Station] %d recharge %s" % [pid, w.id])
	game.session.sync_inventory(pid)
	game.interact.purchase_fx(self)


## Serveur : fin d'une manche : les constructions qui l'attendaient sont prêtes.
func _on_round_ended(n: int) -> void:
	var changed := false
	for pid in builds.keys():
		if game.session.get_data(pid) == null:
			builds.erase(pid)
			changed = true
		elif not bool(builds[pid].ready) and n >= int(builds[pid]["round"]):
			builds[pid].ready = true
			changed = true
	if changed:
		broadcast_state()


func get_state() -> Dictionary:
	return {"b": builds.duplicate(true)}


func apply_state(state: Dictionary, _animate: bool) -> void:
	var before := local_build()
	if not multiplayer.is_server():
		builds = _clean_builds(state.get("b", {}))
	var now := local_build()
	if game != null and game.hud != null and bool(now.get("ready", false)) and not bool(before.get("ready", false)):
		Audio.play_2d("purchase", -2.0, 0.0)
		game.hud.flash_message(Lang.t("Arme prête à la station : %s", "Weapon ready at the station: %s") % weapon_name(now.w))
	_refresh_lamp()
	builds_changed.emit()


## Copie reçue du serveur relue (types, armes bornées).
static func _clean_builds(v: Variant) -> Dictionary:
	var out := {}
	if not v is Dictionary:
		return out
	for pid in v:
		var b: Variant = v[pid]
		if not pid is int or not b is Dictionary:
			continue
		var w := BuildRules.clean_weapon(b.get("w"))
		if w.is_empty():
			continue
		var r: Variant = b.get("ready", false)
		out[pid] = {"w": w, "price": ProfileValues.to_int(b.get("price"), 0, 0, 1 << 30),
			"round": ProfileValues.to_int(b.get("round"), 1, 1, 1 << 30), "ready": r is bool and r}
	return out


## Voyant : état de la construction du joueur local.
func _refresh_lamp() -> void:
	if _lamp == null:
		return
	var b := local_build()
	var st := "idle" if b.is_empty() else ("ready" if bool(b.ready) else "busy")
	if st == _shown_state:
		return
	_shown_state = st
	var c: Color = {"idle": IDLE_COLOR, "busy": BUSY_COLOR, "ready": READY_COLOR}[st]
	_lamp.material_override = PropBuilder._emissive(c, 3.0)
	_light.light_color = c


# --------------------------------------------------------------------------
# Client
# --------------------------------------------------------------------------

## Ouvre l'interface de la station chez ce joueur (ordre du serveur après [F]).
@rpc("authority", "call_remote", "reliable")
func _cl_open() -> void:
	if game and game.hud and game.hud.station_panel and GameState.state != GameState.State.GAME_OVER:
		game.hud.station_panel.open(self)


## Demandes du joueur local (interface) : le serveur décide.
func request_build(o: OwnedWeapon) -> void:
	srv_build.rpc_id(1, GameWeapon.from_owned(o))


func request_refill() -> void:
	srv_refill.rpc_id(1)
