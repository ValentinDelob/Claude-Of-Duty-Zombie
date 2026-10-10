extends AutotestScenario
## @rendu : coût de rendu de l'ARCHITECTURE CUBIQUE (docs/VOXEL_ARCHITECTURE_PLAN.md,
## lot E) sur les cartes en maillage : DRAFT ARENA, test_levels, carte des
## escaliers (tous les types, garde-corps), salle ronde (mur courbe, pilier
## tourné, pans en biais) et carte des murs en biais. Une ligne [perf] par vue
## (fps moyens, 1 % bas, GPU, appels de dessin) et les triangles de
## l'architecture. BUNKER K-7 : map_tour (mêmes vues que d'habitude).
## Lancement : sh tools/perf.sh archi_perf (QUALITY=low|medium|high).
## @niveau perf : hors check.

const Diag := preload("res://tests/test_map_editor_diagonal.gd")
const Free := preload("res://tests/test_map_editor_freeform.gd")
const Stairs := preload("res://tests/test_stairs.gd")

var H := AutotestHelpers
var off := MapGeom.WORLD_OFFSET
var worst := 100000.0


func run() -> void:
	timeout_sec = 400
	await _builtin("draft_arena")
	await _builtin("test_levels", [
		["test_levels_escalier", Vector3(15.0, 0.05, 21.0), Vector3(11.2, 1.5, 15.0)],
		["test_levels_mezzanine", Vector3(18.0, 3.05, 10.5), Vector3(13.0, 3.6, 14.0)],
		["test_levels_pente", Vector3(16.0, 0.05, 23.0), Vector3(16.0, -1.4, 30.0)]])
	var stairs := Stairs.stairs_map()
	for o in stairs.objets:
		if o.get("type") == "escalier":
			o["garde_corps"] = true
	await _custom(stairs, "perf_escaliers", [
		["escaliers_ensemble", Vector2(12.0, 19.0), Vector3(6.0, 1.0, 12.0)],
		["escaliers_mezzanine", Vector2(6.5, 6.0), Vector3(2.0, 3.6, 9.0)]])
	await _custom(Free.round_map(), "perf_ronde", [
		["ronde_salle", Vector2(20.0, 20.0), Vector3(6.0, 1.5, 12.0)],
		["ronde_mur_courbe", Vector2(16.0, 15.0), Vector3(16.0, 1.2, 9.0)],
		["ronde_pilier", Vector2(13.0, 15.5), Vector3(10.0, 1.2, 18.0)]])
	await _custom(Diag.diag_map(), "perf_biais", [
		["biais_octogone", Vector2(9.0, 13.0), Vector3(16.0, 1.0, 4.0)],
		["biais_losange", Vector2(19.6, 18.4), Vector3(16.0, 1.3, 16.0)]])
	print("[archi_perf] pire vue : %.0f fps" % worst)


func _start(id: String) -> Player:
	var p := await H.start_solo_game(self, id)
	if p == null:
		return null
	Game.instance.rounds.paused = true
	Game.instance.combat.debug_invulnerable = true
	p.bot_controlled = true
	await H.clear_zombies(self)
	await seconds(1.0)
	var tris := 0
	var meshes := 0
	for mi: MeshInstance3D in Game.instance.world.find_children("*__*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			tris += mi.mesh.get_faces().size() / 3
			meshes += 1
	print("[archi_perf] %s : %d triangles d'architecture et de décor (%d maillages)" % [id, tris, meshes])
	return p


func _measure(label: String) -> void:
	await seconds(0.6)
	at.begin_perf()
	await seconds(1.5)
	worst = minf(worst, at.end_perf(label))


func _back() -> void:
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


## Carte du jeu : vues données (monde), sinon le départ et trois quarts de tour.
func _builtin(id: String, views := []) -> void:
	var p := await _start(id)
	if p == null:
		return
	if views.is_empty():
		var start := p.global_position
		for k in 4:
			p.global_position = start
			H.aim_at(p, start + Vector3.FORWARD.rotated(Vector3.UP, k * PI / 2.0) * 6.0 + Vector3(0, 1.3, 0))
			await _measure("%s_%d" % [id, k])
	for vw: Array in views:
		p.global_position = vw[1]
		H.aim_at(p, vw[2])
		await _measure(String(vw[0]))
	await _back()


## Carte d'essai de l'éditeur : enregistrée puis jouée (vues en repère de l'éditeur).
func _custom(doc: EditorMap, id: String, views: Array) -> void:
	doc.carte["id"] = id
	if doc.save_dir(EditorMap.map_dir(id)) != OK:
		at.fail("carte d'essai non enregistrée : " + id)
		return
	var p := await _start(EditorMapDef.CUSTOM_PREFIX + id)
	if p == null:
		return
	for vw: Array in views:
		var at2: Vector2 = vw[1]
		p.global_position = Vector3(off + at2.x, 0.05, off + at2.y)
		H.aim_at(p, vw[2] + Vector3(off, 0, off))
		await _measure(String(vw[0]))
	await _back()
