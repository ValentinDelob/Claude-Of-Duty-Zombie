class_name EvacDoor
extends Interactable
## Porte d'évacuation (GAME_CONCEPT.md §4.5 ; règles : EvacRules). Une par
## carte, contre un mur, accessible dès le départ (MapValidator).
##
## Après une vague spéciale ou de boss vaincue, RoundManager l'ouvre
## (srv_open) : fenêtre de EvacRules.DURATION s sans zombies, la manche
## suivante attend. Chaque joueur vote à la porte ([F] / X : « partir », puis
## « prêt », en alternance). Le SERVEUR décide (EvacRules.decide) : reprise de
## la partie, ou évacuation de toute l'équipe (Game.srv_end_match). L'état
## (ouverte, temps restant, votes) passe par le message d'état des objets
## (InteractionSystem._cl_state) ; aucun RPC propre.
##
## Modèle provisoire en blocs alignés sur la grille de 5 cm (§4.19) : bâti,
## battant, voyant rouge (fermée) ou vert (ouverte) ; collision : CollisionBox
## (objet de collision du jeu, aucun modèle Blender). Zone de la porte
## marquée au sol pendant la fenêtre.

const ID := "evac"
## Dimensions (m, multiples de 5 cm) : battant 1,2 x 2 m, bâti de 10 cm.
const DOOR_W := 1.2
const DOOR_H := 2.0
const FRAME := 0.1
const DEPTH := 0.15
## Renvoi de l'état (temps restant) aux clients, en plus de chaque vote.
const RESYNC := 5.0

var game: Game
## Toutes les machines : fenêtre ouverte, temps restant, votes (pid -> Vote).
var is_open := false
var time_left := 0.0
var votes: Dictionary = {}
## Repère : origine au pied de la porte sur la face du mur, +z vers la pièce.
var _wall := Vector3(0, 0, -1)
var _resync := 0.0
var _decided := false
var _panel: MeshInstance3D
var _lamp: MeshInstance3D
var _light: OmniLight3D
var _zone_marks: Node3D
var _hud_text := ""
## Fenêtre ouverte telle qu'affichée (bandeaux d'ouverture et de fermeture).
var _ui_open := false


func setup_marker(m: MapMarker) -> void:
	interact_id = ID
	name = "EvacDoor"
	_wall = Vector3(m.wall.x, 0.0, m.wall.z).normalized() if Vector2(m.wall.x, m.wall.z).length() > 0.01 else Vector3(0, 0, -1)
	# Pied de la porte : sur la face du mur, au niveau du sol.
	var face := m.pos + _wall * m.wall_gap
	var z := -_wall
	var x := Vector3.UP.cross(z).normalized()
	transform = Transform3D(Basis(x, Vector3.UP, z), face)
	interact_range = 2.4


func _ready() -> void:
	game = Game.instance
	var frame_mat := WorldLook.surface("steel")
	# Bâti : deux montants et un linteau (blocs alignés).
	_block(Vector3(-(DOOR_W + FRAME) * 0.5, DOOR_H * 0.5, DEPTH * 0.5), Vector3(FRAME, DOOR_H, DEPTH), frame_mat)
	_block(Vector3((DOOR_W + FRAME) * 0.5, DOOR_H * 0.5, DEPTH * 0.5), Vector3(FRAME, DOOR_H, DEPTH), frame_mat)
	_block(Vector3(0, DOOR_H + FRAME * 0.5, DEPTH * 0.5), Vector3(DOOR_W + FRAME * 2.0, FRAME, DEPTH), frame_mat)
	# Battant (recule dans le mur quand la porte est ouverte) et barre de poussée.
	_panel = _block(Vector3(0, DOOR_H * 0.5, 0.05), Vector3(DOOR_W, DOOR_H, 0.1), WorldLook.surface("door"))
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.1, 0.05)
	bar.mesh = bm
	bar.material_override = frame_mat
	bar.position = Vector3(0, 0.0, 0.075)
	_panel.add_child(bar)
	# Voyant au-dessus de la porte.
	_lamp = _block(Vector3(0, DOOR_H + FRAME + 0.1, 0.1), Vector3(0.4, 0.15, 0.1), PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0))
	_light = OmniLight3D.new()
	_light.omni_range = 5.0
	_light.light_energy = 0.6
	_light.position = Vector3(0, DOOR_H + 0.2, 0.5)
	add_child(_light)
	# Collision : un pavé du jeu (pas de modèle importé).
	add_child(CollisionBox.make(Vector3(0, (DOOR_H + FRAME) * 0.5, DEPTH * 0.5),
			Vector3(DOOR_W + FRAME * 2.0, DOOR_H + FRAME, DEPTH), 0.0, false, "metal"))
	_zone_marks = Node3D.new()
	add_child(_zone_marks)
	var mark := PropBuilder._emissive(Color(0.15, 0.9, 0.3), 1.5)
	var w := EvacRules.ZONE_HALF_WIDTH * 2.0
	var d := EvacRules.ZONE_DEPTH
	for b in [[Vector3(0, 0.025, d), Vector3(w, 0.05, 0.1)],
			[Vector3(-EvacRules.ZONE_HALF_WIDTH, 0.025, d * 0.5), Vector3(0.1, 0.05, d)],
			[Vector3(EvacRules.ZONE_HALF_WIDTH, 0.025, d * 0.5), Vector3(0.1, 0.05, d)]]:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = b[1]
		mi.mesh = m
		mi.material_override = mark
		mi.position = b[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_zone_marks.add_child(mi)
	_show_open(false)


func _block(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _show_open(on: bool) -> void:
	if _panel == null:
		return
	_panel.position.z = -0.05 if on else 0.05
	_lamp.material_override = PropBuilder._emissive(Color(0.1, 1.0, 0.3) if on else Color(1.0, 0.1, 0.05), 3.0)
	_light.light_color = Color(0.2, 1.0, 0.4) if on else Color(1.0, 0.15, 0.08)
	_light.light_energy = 1.4 if on else 0.6
	_zone_marks.visible = on


func interact_point() -> Vector3:
	return global_position + global_basis.z * 0.6 + Vector3.UP * 1.1


## Joueur aux pieds `feet` dans la zone de la porte ?
func in_zone(feet: Vector3) -> bool:
	return EvacRules.in_zone_local(global_transform.affine_inverse() * feet)


func prompt(pid: int) -> String:
	if not is_open:
		return ""
	if int(votes.get(pid, EvacRules.Vote.NONE)) == EvacRules.Vote.LEAVE:
		return Lang.t("[F] Rester : voter PRÊT", "[F] Stay: vote READY")
	return Lang.t("[F] Voter PARTIR (évacuation)", "[F] Vote LEAVE (evacuate)")


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Ouvre la fenêtre d'évacuation (vague spéciale ou de boss vaincue). Les
## morts réapparaissent : la vague est terminée (§4.6).
func srv_open() -> void:
	if not multiplayer.is_server() or is_open:
		return
	game.respawn_dead_players()
	is_open = true
	time_left = EvacRules.DURATION
	votes = {}
	_decided = false
	_resync = 0.0
	print("[Evac] porte d'évacuation ouverte (%d s)" % int(EvacRules.DURATION))
	broadcast_state()


func srv_use(pid: int) -> void:
	if not is_open or _decided:
		return
	votes[pid] = EvacRules.next_vote(int(votes.get(pid, EvacRules.Vote.NONE)))
	print("[Evac] vote de %d : %s" % [pid, "partir" if votes[pid] == EvacRules.Vote.LEAVE else "prêt"])
	broadcast_state()
	_srv_decide()


## Serveur : vies et présence dans la zone des joueurs de la partie.
func _srv_status() -> Array:
	var life := {}
	var zone := {}
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		life[pid] = pd.life
		var p: Player = game.players.get(pid)
		zone[pid] = p != null and in_zone(p.srv_origin())
	return [life, zone]


func _srv_decide() -> void:
	if _decided:
		return
	var st := _srv_status()
	match EvacRules.decide(votes, st[0], st[1], time_left):
		EvacRules.EVACUATE:
			_decided = true
			print("[Evac] toute l'équipe est à la porte : évacuation")
			# Fin de partie d'abord : les clients ne verront pas « la partie continue ».
			game.srv_end_match(true)
			_srv_close()
		EvacRules.RESUME:
			_decided = true
			print("[Evac] fenêtre fermée (%s) : la partie continue" % ("tous prêts" if time_left > 0.0 else "temps écoulé"))
			_srv_close()
			game.rounds.srv_resume_after(EvacRules.RESUME_DELAY)


func _srv_close() -> void:
	is_open = false
	time_left = 0.0
	broadcast_state()


func get_state() -> Dictionary:
	return {"open": is_open, "left": time_left, "votes": votes}


func apply_state(state: Dictionary, _animate: bool) -> void:
	var o: Variant = state.get("open", false)
	is_open = o is bool and o
	var l: Variant = state.get("left", 0.0)
	time_left = clampf(float(l), 0.0, EvacRules.DURATION) if (l is float or l is int) and is_finite(float(l)) else 0.0
	var v: Variant = state.get("votes", {})
	votes = v.duplicate() if v is Dictionary else {}
	_show_open(is_open)
	# Affichage suivi à part : sur le serveur, is_open a déjà changé (srv_open).
	if game == null or game.hud == null or _ui_open == is_open:
		return
	_ui_open = is_open
	if is_open:
		Audio.play_2d("round_end", 0.0, 0.0)
		game.hud.show_banner(Lang.t("LA PORTE D'ÉVACUATION EST OUVERTE", "THE EVACUATION DOOR IS OPEN"), 4.0)
	else:
		_hud_text = ""
		game.hud.set_evac_status("")
		if GameState.state != GameState.State.GAME_OVER:
			game.hud.show_banner(Lang.t("LA PARTIE CONTINUE", "THE GAME GOES ON"), 2.5)


func _process(delta: float) -> void:
	if not is_open:
		return
	time_left = maxf(time_left - delta, 0.0)
	if multiplayer.is_server():
		_resync += delta
		if _resync >= RESYNC:
			_resync = 0.0
			broadcast_state()
		_srv_decide()
	if game == null or game.hud == null or not is_open:
		return
	# Bandeau : compte à rebours et état des votes (présence vue d'ici).
	var life := {}
	var zone := {}
	for pid in game.session.data:
		life[pid] = (game.session.data[pid] as PlayerData).life
		var p: Player = game.players.get(pid)
		zone[pid] = p != null and in_zone(p.global_position)
	var text := EvacRules.status_text(time_left, EvacRules.tally(votes, life, zone),
			int(votes.get(multiplayer.get_unique_id(), EvacRules.Vote.NONE)))
	if text != _hud_text:
		_hud_text = text
		game.hud.set_evac_status(text)


func _exit_tree() -> void:
	if game and game.hud and is_instance_valid(game.hud):
		game.hud.set_evac_status("")
