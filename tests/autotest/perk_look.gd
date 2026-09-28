extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## @parts 2 : partie 0 = BUNKER K-7, partie 1 = KINO.
## Machines d'atouts façon BO1 (modèles Blender assets/models/perks/) : chaque
## machine est le modèle de son atout, pleine (le joueur bute dessus, une
## balle s'y arrête), panneau éteint sans courant et allumé avec. Captures de
## chaque machine courant coupé puis rétabli.

var H := AutotestHelpers
var game: Game
var p: Player


func run() -> void:
	timeout_sec = 240
	var split := parts() > 1
	var mi := -1
	for map_id in ["bunker_k7", "kino"]:
		mi += 1
		if split and not owns(mi):
			continue
		await _map_pass(map_id)
		if p == null:
			return
		Router.back_to_menu()
		await seconds(1.0)


func machines() -> Array[PerkMachine]:
	var out: Array[PerkMachine] = []
	for n in game.world.get_node("PerkMachines").get_children():
		if n is PerkMachine:
			out.append(n)
	return out


## Direction « face avant » de la machine (vers le joueur qui achète).
func front(m: PerkMachine) -> Vector3:
	var f := m.interact_point() - m.global_position
	f.y = 0.0
	return f.normalized()


func _map_pass(map_id: String) -> void:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	await seconds(0.5)
	var list := machines()
	# Kino der Toten : Quick Revive, Juggernog, Speed Cola, Double Tap (Mule
	# Kick à venir) ; BUNKER K-7 : les 7 atouts.
	var want := 4 if map_id == "kino" else 7
	at.check(list.size() >= want, "%s : %d machines d'atouts (au moins %d)" % [map_id, list.size(), want])
	for m in list:
		_check_model(m)
	for m in list:
		await _check_solid(m)
	for m in list:
		await _shot(m, map_id, "off")
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await seconds(3.0)
	for m in list:
		at.check(_lit(m) == 1.0, "%s allumée avec le courant" % m.perk_id)
		await _shot(m, map_id, "on")


func _lit(m: PerkMachine) -> float:
	for mi in m._lit_meshes:
		return float(mi.get_instance_shader_parameter("lit"))
	return -1.0


## Le modèle .glb de l'atout est chargé, sa collision est à sa taille.
func _check_model(m: PerkMachine) -> void:
	var model := m.get_node_or_null("Model")
	var body := m.get_node_or_null("Body") as StaticBody3D
	at.check(model != null and m._lit_meshes.size() > 0, "%s : modèle Blender et pièces lumineuses" % m.perk_id)
	if body == null:
		at.check(false, "%s : corps de collision" % m.perk_id)
		return
	var top := 0.0
	var half_w := 0.0
	for cs in body.get_children():
		var b := (cs as CollisionShape3D).shape as BoxShape3D
		top = maxf(top, cs.position.y + b.size.y * 0.5)
		half_w = maxf(half_w, b.size.x * 0.5)
	at.check(top > 1.2 and top < 2.4 and half_w > 0.4 and half_w < 0.56,
			"%s : collision à la taille du modèle (hauteur %.2f m, demi-largeur %.2f m)" % [m.perk_id, top, half_w])
	if m.perk_id != "lazarus" or not Net.mode == Net.Mode.SOLO:
		at.check(_lit(m) == 0.0, "%s éteinte sans courant" % m.perk_id)


## Le joueur qui fonce dessus s'arrête devant ; une balle tirée de face
## (hauteur de poitrine) touche la machine.
func _check_solid(m: PerkMachine) -> void:
	var f := front(m)
	var start := m.global_position + f * 1.3 + Vector3(0, 0.05, 0)
	p.teleport_to(start)
	H.aim_at(p, m.global_position + Vector3.UP * 1.0)
	p.pitch = 0.0
	await seconds(0.2)
	p.input.move = Vector2(0, 1)
	await seconds(1.0)
	p.input.move = Vector2.ZERO
	var d := (p.global_position - m.global_position).dot(f)
	at.check(d > 0.38, "%s : le joueur bute sur la machine (%.2f m du centre)" % [m.perk_id, d])
	var from := m.global_position + f * 2.0 + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, m.global_position + Vector3.UP * 1.0 - f * 0.6)
	q.exclude = [p.get_rid()]
	var hit := game.world.get_world_3d().direct_space_state.intersect_ray(q)
	var ok: bool = not hit.is_empty() and (hit.collider as Node).get_parent() == m
	at.check(ok and Fx.surface_of(hit.collider, hit.shape) == "metal", "%s : une balle s'arrête sur la machine (impact métal)" % m.perk_id)


func _shot(m: PerkMachine, map_id: String, state: String) -> void:
	var f := front(m)
	var side := f.cross(Vector3.UP).normalized()
	p.teleport_to(m.global_position + f * 2.9 + side * 0.8 + Vector3(0, 0.05, 0))
	H.aim_at(p, m.global_position + Vector3.UP * 1.25)
	await seconds(0.5)
	await at.screenshot("%s_%s_%s" % [map_id, m.perk_id, state])
