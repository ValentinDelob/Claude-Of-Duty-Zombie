extends AutotestScenario
## @rendu : TEXTURES PIXEL ART de toutes les surfaces (docs/VOXEL_ARCHITECTURE_PLAN.md,
## lot C) : planche de toutes les textures (vignettes nommées, albédo brut,
## murs le pied en bas), puis captures en jeu sur BUNKER K-7 (courant
## rétabli) et DRAFT ARENA ; mesure du temps de génération des textures au
## chargement de chaque carte.
## @niveau perf : hors check (captures d'un ajout en cours).
## Planche : tests/_out/shots/voxel_textures_look_planche.png ; captures :
## tests/_out/shots/voxel_textures_look_<carte>_<vue>.png.

var H := AutotestHelpers
const VisualLook := preload("res://tests/autotest/visual_look.gd")
const Draft := preload("res://tests/autotest/draft_arena.gd")

var game: Game
var p: Player


func run() -> void:
	timeout_sec = 300
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	print("[voxel_textures] menu : %d textures générées en %.1f ms" % [PixelSurfaces.gen_count, PixelSurfaces.gen_usec / 1000.0])
	for map_id in ["bunker_k7", "draft_arena"]:
		var n0 := PixelSurfaces.gen_count
		var t0 := PixelSurfaces.gen_usec
		var w0 := Time.get_ticks_msec()
		p = await H.start_solo_game(self, map_id)
		if p == null:
			return
		print("[voxel_textures] %s : %d textures générées en %.1f ms (chargement %d ms)" % [map_id,
			PixelSurfaces.gen_count - n0, (PixelSurfaces.gen_usec - t0) / 1000.0, Time.get_ticks_msec() - w0])
		game = Game.instance
		game.combat.debug_invulnerable = true
		game.rounds.paused = true
		await H.clear_zombies(self)
		for id in game.doors:
			game.doors[id].srv_open()
		var power := game.interact.get_obj("power")
		if power is PowerSwitch:
			(power as PowerSwitch).srv_use(1)
		await seconds(2.0)
		if map_id == "bunker_k7":
			for v in VisualLook.BUNKER_VIEWS:
				p.teleport_to(MapData.cell_to_world(v[1], 0.05))
				H.aim_at(p, MapData.cell_to_world(v[2], 1.2))
				await seconds(0.8)
				await at.screenshot("%s_%s" % [map_id, v[0]])
		else:
			for v in Draft.VIEWS:
				p.teleport_to(v[1], v[2])
				p.pitch = v[3]
				p.head.rotation.x = v[3]
				await seconds(0.8)
				await at.screenshot("%s_%s" % [map_id, v[0]])
		# Un zombie de près : cohérence des surfaces avec le personnage cubique.
		if map_id == "bunker_k7":
			var v: Array = VisualLook.BUNKER_VIEWS[3]
			p.teleport_to(MapData.cell_to_world(v[1], 0.05))
			var z := await H.dummy_zombie(self, p.global_position + (MapData.cell_to_world(v[2], 0.0) - p.global_position).normalized() * 2.6)
			if z != null:
				H.aim_at(p, z.global_position + Vector3.UP * 1.0)
				await seconds(0.8)
				await at.screenshot("%s_zombie" % map_id)
		Router.back_to_menu()
		await seconds(1.0)
	await _board()
	var t0 := Time.get_ticks_usec()
	for key: String in PixelSurfaces.DEFS:
		PixelSurfaces._images.erase(key)
		PixelSurfaces.image(key)
	print("[voxel_textures] les %d textures régénérées en %.0f ms" % [PixelSurfaces.DEFS.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	at.check(true, "captures faites")


## Planche de toutes les textures : vignettes 2× (128 px = 3,2 m), nom de la
## clé et luminance moyenne ; rendue dans un SubViewport puis enregistrée.
func _board() -> void:
	var keys := PixelSurfaces.DEFS.keys()
	var cols := 8
	var cell := Vector2i(150, 152)
	@warning_ignore("integer_division")
	var rows := (keys.size() + cols - 1) / cols
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * cell.x + 10, rows * cell.y + 10)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.14)
	bg.size = vp.size
	vp.add_child(bg)
	for i in keys.size():
		var key: String = keys[i]
		var img := PixelSurfaces.image(key).duplicate() as Image
		img.convert(Image.FORMAT_RGB8)
		if bool(PixelSurfaces.def(key).wall):
			img.flip_y()
		var sum := 0.0
		for y in img.get_height():
			for x in img.get_width():
				sum += PixelSurfaces.lum(img.get_pixel(x, y))
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = Vector2(128, 128)
		@warning_ignore("integer_division")
		tr.position = Vector2(10 + (i % cols) * cell.x, 6 + (i / cols) * cell.y)
		vp.add_child(tr)
		var lb := Label.new()
		lb.text = "%s  %.2f" % [key, sum / (img.get_width() * img.get_height())]
		lb.add_theme_font_size_override("font_size", 12)
		lb.position = tr.position + Vector2(0, 129)
		vp.add_child(lb)
	at.add_child(vp)
	await frames(4)
	var out := vp.get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	if out != null and not out.is_empty():
		out.save_png(dir.path_join("voxel_textures_look_planche.png"))
		print("[voxel_textures] planche : %s" % dir.path_join("voxel_textures_look_planche.png"))
	vp.queue_free()
