extends AutotestScenario
## @rendu
## @niveau perf
## CAPTURES D'UN CORRECTIF EN COURS (« la crosse des armes rentre dans la
## caméra ») : hors check par défaut (« @niveau perf »), à lancer à la main :
##   SCENARIOS="view_model_stock" JOBS=1 GUI_JOBS=1 bash tools/check.sh
## À retirer (ou à garder hors check) une fois le correctif publié.
##
## Vue FPS RENDUE (SubViewport, plan proche 0,03 m comme Player) de chaque
## arme (normale et Pack-a-Punch, couteaux exclus), pour chaque champ de
## vision (min, défaut, max des options) et chaque format d'écran (16:9, 21:9,
## 4:3) : hanche, montée en visée (une image toutes les 0,033 s), visée tenue,
## tir en visée, visée en marchant / en regardant en haut, en bas, sur le
## côté, rechargement demandé en visée, sprint, sortie de visée.
##
## Mesure sur l'IMAGE : chaque image est rendue une seconde fois avec un
## shader de diagnostic qui reprend MOT POUR MOT le vertex() de
## weapon.gdshader (vm_bend, vm_fov_scale, profondeur) et dont le fragment
## code la profondeur du point vu et le côté de la face (cull_disabled) :
## - « dos » : faces arrière visibles = maillage ouvert (plan proche, ou long
##   triangle resté plat sous la joue qui traverse l'arme : intérieur de la
##   crosse visible) ;
## - « proche » : part de l'écran couverte, à moins de NEAR_BAD m de l'œil,
##   par la carcasse derrière le cran ou les mains (crosse contre l'œil) ;
## - « arrière » : visée tenue, part de l'écran couverte par la carcasse
##   entre l'œil et le cran (au-delà de DEF_REAR : elle bouche l'écran) ;
## - « saut » : en montant en visée, couverture qui baisse d'une image à
##   l'autre (morceau qui disparaît : l'ancienne crosse masquée d'un coup),
##   l'inverse en sortant (armes à lunette : écran de lunette exclu).
## Images : tests/_out/shots/view_model_stock/ (normale + diagnostic pour
## les pires images de chaque arme, et quelques poses fixes au réglage par
## défaut). Tableau complet : tests/_out/view_model_stock.csv.
##
## Variables d'environnement : VMS_ONLY=id1,id2 (armes), VMS_QUICK=1
## (réglage par défaut seulement), VMS_TAG=avant|apres (préfixe des images).

const DT := 1.0 / 60.0
## Champ de vision : minimum, défaut, maximum du menu des options.
const FOVS := [60.0, 80.0, 110.0]
const ASPECTS := [["16x9", 16.0 / 9.0], ["21x9", 21.0 / 9.0], ["4x3", 4.0 / 3.0]]
## Hauteur des images de diagnostic et des captures (px).
const DBG_H := 144
const SHOT_H := 540
## Profondeurs (m) des classes du diagnostic (bornes hautes).
const BINS := [0.03, 0.05, 0.06, 0.09, 0.115]
## Au-delà : défaut. Faces arrière (intérieur) > DEF_BACK de l'écran ;
## arme à moins de NEAR_BAD m de l'œil sur > DEF_NEAR de l'écran.
const NEAR_BAD := 0.06
const DEF_BACK := 0.002
const DEF_NEAR := 0.002
## Visée tenue : part de l'écran couverte par la carcasse entre l'œil et le
## cran (boîtier, crosse, poignée de transport...) ; saut de couverture d'une
## image à l'autre (crosse masquée d'un coup) pendant l'entrée / la sortie.
const DEF_REAR := 0.10
const DEF_POP := 0.01
var _prev_phase := ""
var _prev_cover := -1.0
var _prev_ads := 0.0
var _prev_delta := 0.0
var _phase_n := 0
## VMS_ALLSHOTS=1 : une capture à chaque image mesurée (mise au point).
var _all_shots := OS.get_environment("VMS_ALLSHOTS") == "1"
var _prev_scoped := false

var vp_dbg: SubViewport
var vp_shot: SubViewport
var cam: Camera3D
var cam2: Camera3D
var vm: ViewModel
var p: Player
var dbg_mat: ShaderMaterial
var dbg_hand: ShaderMaterial
var tag := "avant"
var csv: FileAccess
var shot_dir := ""
## [arme, pap, fov, format] -> pire défaut.
var report: Array = []
var _saved := {}
var _base_fov := 80.0
var _aspect := 16.0 / 9.0
var _pass_worst := {}


func run() -> void:
	timeout_sec = 6000
	tag = OS.get_environment("VMS_TAG") if OS.get_environment("VMS_TAG") != "" else "avant"
	shot_dir = ProjectSettings.globalize_path("res://tests/_out/shots/view_model_stock")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	if OS.get_environment("VMS_GAME") == "1":
		await _game_pass()
		return
	csv = FileAccess.open(ProjectSettings.globalize_path("res://tests/_out/view_model_stock_%s.csv" % tag), FileAccess.WRITE)
	csv.store_line("weapon,pap,fov,aspect,state,ads,cam_fov,cover,back,d03,d05,d06,d09,d115,rear")
	# Temps de jeu figé : seul ce scénario fait avancer GameClock (pas fixes).
	var old_scale := Engine.time_scale
	Engine.time_scale = 0.0
	tree().root.disable_3d = true
	_build()
	var ids: Array = WeaponDB.WEAPONS.keys()
	var only := OS.get_environment("VMS_ONLY")
	if only != "":
		ids = Array(only.split(","))
	var quick := OS.get_environment("VMS_QUICK") == "1"
	var t0 := Time.get_ticks_msec()
	for id in ids:
		for pap in [false, true]:
			for fov in FOVS:
				for asp in ASPECTS:
					if quick and (fov != 80.0 or asp[0] == "4x3"):
						continue
					await _weapon_pass(String(id), pap, fov, asp)
		print("[vms] %s fait (%.0f s)" % [id, (Time.get_ticks_msec() - t0) / 1000.0])
	csv.close()
	Engine.time_scale = old_scale
	tree().root.disable_3d = false
	_summary()
	vp_dbg.queue_free()
	vp_shot.queue_free()
	p.weapons.free()
	p.free()


func _build() -> void:
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.52)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	vp_dbg = SubViewport.new()
	vp_dbg.own_world_3d = false
	vp_dbg.world_3d = world
	vp_dbg.transparent_bg = false
	vp_dbg.render_target_update_mode = SubViewport.UPDATE_DISABLED
	at.add_child(vp_dbg)
	vp_shot = SubViewport.new()
	vp_shot.world_3d = world
	vp_shot.render_target_update_mode = SubViewport.UPDATE_DISABLED
	at.add_child(vp_shot)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	sun.light_energy = 1.2
	vp_shot.add_child(sun)
	cam = Camera3D.new()
	cam.near = 0.03
	cam.far = 120.0
	vp_dbg.add_child(cam)
	cam.current = true
	# Diagnostic : fond noir (B = 0), l'arme seule est codée.
	var black := Environment.new()
	black.background_mode = Environment.BG_COLOR
	black.background_color = Color.BLACK
	black.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = black
	cam2 = Camera3D.new()
	cam2.near = 0.03
	cam2.far = 120.0
	vp_shot.add_child(cam2)
	cam2.current = true
	p = Player.new()
	p.weapons = WeaponController.new()
	# Shader de diagnostic : vertex() de weapon.gdshader inchangé.
	var src: String = (load("res://assets/shaders/weapon.gdshader") as Shader).code
	var cut := src.find("void fragment()")
	src = src.substr(0, cut).replace("render_mode cull_back;", "render_mode cull_disabled, unshaded;")
	src += """
uniform float vms_sight = 0.0;
uniform float vms_hand = 0.0;
float _lin(float c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
void fragment() {
	float d = -VERTEX.z;
	float bin = d < 0.03 ? 1.0 : d < 0.05 ? 2.0 : d < 0.06 ? 3.0 : d < 0.09 ? 4.0 : d < 0.115 ? 5.0 : 0.0;
	// B : 255 devant le cran, ~128 entre l'œil et le cran (carcasse arrière).
	ALBEDO = vec3(FRONT_FACING ? 0.0 : 1.0, _lin(bin * 40.0 / 255.0), vms_hand > 0.5 ? _lin(0.5) : d < vms_sight - 0.01 ? _lin(0.75) : 1.0);
}
"""
	var sh := Shader.new()
	sh.code = src
	dbg_mat = ShaderMaterial.new()
	dbg_mat.shader = sh
	dbg_mat.set_shader_parameter("viewmodel", 1.0)
	dbg_hand = dbg_mat.duplicate()


func _equip(id: String, pap: bool) -> Dictionary:
	if vm:
		vm.free()
	vm = ViewModel.new()
	cam.add_child(vm)
	var w := WeaponDB.new_instance(id, pap)
	p.weapons.weapons = [w]
	p.weapons.slot = 0
	p.aiming = false
	p.sprinting = false
	p.diving = false
	p.velocity = Vector3.ZERO
	p.input = PlayerInput.new()
	vm.set_weapon(id, pap)
	vm.ads = 0.0
	vm.scoped = false
	cam.fov = _base_fov
	return WeaponDB.stats(id, pap)


## Un pas de jeu, dans l'ordre du jeu : Player (champ de vision de la caméra)
## puis WeaponController (ViewModel.update, écran de lunette).
func _step(n := 1, walk := 0.0) -> void:
	for i in n:
		GameClock._t += DT
		var s := vm._stats
		var target := _base_fov
		if p.aiming:
			target = _base_fov * 0.72
		elif p.sprinting:
			target = _base_fov * 1.06
		cam.fov = _camera_fov(s, target)
		if walk > 0.0:
			# Pas au sol (Player.is_on_floor faux hors partie) : même avance.
			vm._bob += DT * walk * (1.7 if p.sprinting else 2.0)
		vm.update(DT, p)
		var busy := vm.is_busy()
		vm.apply_scope(WeaponDB.scope_kind(s) != "" and p.aiming and vm.ads >= ViewModel.SCOPE_ADS and not busy)


## WeaponController.camera_fov.
func _camera_fov(s: Dictionary, target: float) -> float:
	if vm.scoped and s.has("scope_fov"):
		return float(s.scope_fov)
	if p.aiming and not s.is_empty():
		var k := clampf(vm.ads, 0.0, 1.0)
		target = lerpf(_base_fov, _base_fov * float(s.ads_zoom), k * k * (3.0 - 2.0 * k))
		if vm.scoped:
			return target
	return lerpf(cam.fov, target, 1.0 - exp(-DT * 14.0))


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and n.get_parent().name != "MuzzleFlash":
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _set_debug(on: bool) -> void:
	var all := []
	_meshes(vm, all)
	for mi: MeshInstance3D in all:
		if on:
			if not mi.has_meta("vms_orig"):
				mi.set_meta("vms_orig", mi.material_override)
			# Mains et bras : jamais comptés comme carcasse arrière.
			mi.material_override = dbg_hand if vm.hands and vm.hands.is_ancestor_of(mi) else dbg_mat
		elif mi.has_meta("vms_orig"):
			mi.material_override = mi.get_meta("vms_orig")
	vm._flash_rig.visible = vm._flash_rig.visible and not on


func _render(v: SubViewport) -> Image:
	v.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	return v.get_texture().get_image()


## Mesure de l'image courante : [couverture, dos, classes de profondeur...].
func _measure() -> Array:
	var sd := 0.0
	if vm.model and not WeaponModels.info(vm.model_id, "no_sights", false):
		sd = -(vm.transform * vm.model.transform * WeaponModels.anchor(vm.model_id, "sight")).z
	dbg_mat.set_shader_parameter("vms_sight", sd)
	dbg_hand.set_shader_parameter("vms_hand", 1.0)
	_set_debug(true)
	var img: Image = await _render(vp_dbg)
	_set_debug(false)
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var n := data.size() / 3
	var cover := 0
	var back := 0
	var bins := [0, 0, 0, 0, 0, 0]
	var rear := 0
	var i := 0
	while i < data.size():
		if data[i + 2] > 64:
			cover += 1
			# B : 255 arme devant le cran, 191 arme entre l'œil et le cran,
			# 128 mains et bras.
			if data[i + 2] > 160 and data[i + 2] < 225:
				rear += 1
			if data[i] > 128:
				back += 1
			# Profondeurs : tout sauf l'arme devant le cran (l'oculaire d'une
			# lunette, le cran lui-même, sont la visée).
			var b := int(round(data[i + 1] / 40.0))
			if b > 0 and b <= 5 and data[i + 2] < 225:
				bins[b] += 1
		i += 3
	var f := float(n)
	return [cover / f, back / f, bins[1] / f, bins[2] / f, bins[3] / f, bins[4] / f, bins[5] / f, img, rear / f]


var _cur := {}


func _sample(state: String, force_shot := false) -> void:
	cam2.fov = cam.fov
	var m: Array = await _measure()
	var near := float(m[2]) + float(m[3]) + float(m[4])
	var rear := float(m[8])
	csv.store_line("%s,%s,%d,%s,%s,%.3f,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [_cur.id, _cur.pap, int(_base_fov), _cur.asp, state, vm.ads, cam.fov, m[0], m[1], m[2], m[3], m[4], m[5], m[6], rear])
	# Saut d'une image à l'autre (crosse qui disparaît d'un coup) pendant
	# l'entrée / la sortie de visée, hors écran de lunette.
	var phase := state.get_slice(" ", 0)
	var pop := 0.0
	var delta := 0.0
	_phase_n = _phase_n + 1 if phase == _prev_phase else 0
	# Armes à lunette : l'oculaire vient à l'œil puis l'écran de lunette
	# remplace l'arme (voulu) ; fin de mise en joue exclue.
	var scope_end := WeaponDB.scope_kind(vm._stats) != "" and vm.ads > 0.8
	if _phase_n >= 1 and (phase == "montee" or phase == "sortie") and not vm.scoped and not _prev_scoped and not scope_end:
		# En montant, l'arme approche de l'œil : sa couverture grandit ; une
		# baisse est un morceau qui disparaît (l'ancienne crosse masquée d'un
		# coup). En descendant, l'inverse.
		delta = float(m[0]) - _prev_cover
		pop = maxf(-delta if phase == "montee" else delta, 0.0)
	_prev_delta = delta
	_prev_scoped = vm.scoped
	_prev_phase = phase
	_prev_cover = float(m[0])
	_prev_ads = vm.ads
	# Carcasse entre l'œil et le cran : mesurée en visée tenue.
	var held := vm.ads >= 1.0 and (phase == "visee" or phase == "tir" or phase == "marche" or phase == "regard")
	var rear_bad := rear if held else 0.0
	var score := maxf(maxf(float(m[1]) / DEF_BACK, near / DEF_NEAR), maxf(rear_bad / DEF_REAR, pop / DEF_POP))
	if score > float(_pass_worst.get("score", 0.0)):
		_pass_worst = {"score": score, "state": state, "back": m[1], "near": near, "ads": vm.ads, "rear": rear_bad, "pop": pop}
	_pass_worst["rear_max"] = maxf(float(_pass_worst.get("rear_max", 0.0)), rear_bad)
	var defect := float(m[1]) > DEF_BACK or near > DEF_NEAR or rear_bad > DEF_REAR or pop > DEF_POP
	var key := "%s%s_%d_%s" % [_cur.id, "_pap" if _cur.pap else "", int(_base_fov), _cur.asp]
	# Images : poses fixes au réglage par défaut, et premier défaut de chaque
	# état pour chaque arme et réglage (au plus 6 par passe).
	var skey := key + "|" + state.get_slice(" ", 0)
	if _all_shots:
		print("[vms] %s ads %.3f bend %s model %s rest %s" % [state, vm.ads, ViewModel._bend_val, vm.model.transform.origin, ViewModel.rest_transform(vm.model_id, vm.ads * vm.ads * (3.0 - 2.0 * vm.ads)).origin])
	if force_shot and _cur.asp != "16x9":
		force_shot = false
	if force_shot or _all_shots or (defect and not _saved.has(skey) and int(_saved.get(key, 0)) < 6):
		_saved[skey] = true
		_saved[key] = int(_saved.get(key, 0)) + 1
		var img: Image = await _render(vp_shot)
		var fname := "%s_%s_%s" % [tag, key, state.replace(" ", "_").replace(".", "")]
		img.save_png("%s/%s.png" % [shot_dir, fname])
		(m[7] as Image).save_png("%s/%s_diag.png" % [shot_dir, fname])


func _weapon_pass(id: String, pap: bool, fov: float, asp: Array) -> void:
	_base_fov = fov
	_aspect = asp[1]
	vp_dbg.size = Vector2i(int(round(DBG_H * _aspect)), DBG_H)
	vp_shot.size = Vector2i(int(round(SHOT_H * _aspect)), SHOT_H)
	_cur = {"id": id, "pap": pap, "asp": asp[0]}
	_pass_worst = {}
	_prev_phase = ""
	var s := _equip(id, pap)
	var fixed: bool = fov == 80.0 and asp[0] == "16x9" and not pap
	_step(20)
	await _sample("hanche", fixed)
	# Montée en visée : une image toutes les 2 pas (0,033 s).
	p.aiming = true
	var k := 0
	var mid_shot := false
	while vm.ads < 1.0 and k < 120:
		_step(2)
		k += 1
		var force: bool = fixed and not mid_shot and vm.ads >= 0.5
		mid_shot = mid_shot or force
		await _sample("montee %.2f" % vm.ads, force)
	_step(4)
	await _sample("visee", fixed)
	# Tir en visée (plusieurs coups, recul).
	var interval := WeaponDB.fire_interval(id, pap)
	var next := 0.0
	var t := 0.0
	var shot_i := 0
	var fired := 0
	while t < 0.9 and fired < 10:
		if t >= next:
			vm.fire(s, null, p, false)
			fired += 1
			next += interval
		_step()
		t += DT
		shot_i += 1
		if shot_i % 2 == 0:
			await _sample("tir %.2f" % t, fixed and shot_i == 4)
	_step(30)
	# Visée en marchant / en se décalant.
	p.velocity = Vector3(3.0, 0.0, 2.0)
	for j in 12:
		_step(3, 3.6)
		await _sample("marche %d" % j)
	p.velocity = Vector3.ZERO
	# Regard vers le haut, le bas, les côtés (balancement d'inertie).
	for look in [Vector2(0, -900), Vector2(0, 900), Vector2(900, 0), Vector2(-900, 0)]:
		p.input.look = look
		_step(6)
		await _sample("regard %d,%d" % [look.x, look.y])
	p.input.look = Vector2.ZERO
	_step(20)
	# Rechargement demandé en visée (le jeu abaisse l'arme pendant le rechargement).
	if not s.get("infinite", false):
		p.weapons.weapons[0].mag = 0
		var rt := float(s.reload)
		vm.start_reload(rt)
		t = 0.0
		while t < rt + 0.4:
			_step(4)
			t += DT * 4
			await _sample("rechargement %.2f" % (t / rt))
		p.weapons.weapons[0].mag = int(s.mag)
	_step(30)
	# Actions déclenchées EN VISÉE (le jeu les permet) : couteau, fente,
	# changement d'arme, grenade, plongeon, sprint, puis visée
	# depuis le sprint.
	await _ads_combo("couteau", func(): vm.start_melee(false), ViewModel.MELEE_ANIM + 0.1)
	await _ads_combo("fente", func(): vm.start_melee(true), ViewModel.MELEE_ANIM + 0.1)
	await _ads_combo("changement", func(): vm.start_switch(WeaponController.SWITCH_TIME, func(): pass), WeaponController.SWITCH_TIME + 0.1)
	await _ads_combo("grenade", func(): vm.lowered = 1.0, 0.6)
	vm.lowered = 0.0
	# Plongeon : le jeu lâche la visée (Player._update_stance).
	await _ads_combo("plongeon", func():
		p.aiming = false
		p.diving = true, 0.5)
	p.diving = false
	await _ads_combo("sprint_depuis_visee", func():
		p.aiming = false
		p.sprinting = true
		p.velocity = Vector3(0, 0, -6.5), 0.6, 6.5)
	p.aiming = false
	p.sprinting = true
	_step(30, 6.5)
	p.sprinting = false
	p.velocity = Vector3.ZERO
	p.aiming = true
	for j in 15:
		_step(2)
		await _sample("visee_depuis_sprint %d" % j)
	_step(30)
	# Sortie de visée.
	p.aiming = false
	k = 0
	while vm.ads > 0.0 and k < 120:
		_step(2)
		k += 1
		await _sample("sortie %.2f" % vm.ads)
	# Sprint.
	p.sprinting = true
	p.velocity = Vector3(0, 0, -6.5)
	for j in 8:
		_step(4, 6.5)
		await _sample("sprint %d" % j)
	p.sprinting = false
	p.velocity = Vector3.ZERO
	_step(20)
	await _sample("hanche2")
	report.append([id, pap, int(fov), asp[0], _pass_worst])


## En visée complète, `start` déclenche une action ; une image toutes les
## 2 pas pendant `dur` s, puis retour en visée.
func _ads_combo(label: String, start: Callable, dur: float, walk := 0.0) -> void:
	p.aiming = true
	p.sprinting = false
	p.diving = false
	p.velocity = Vector3.ZERO
	_step(40)
	start.call()
	var t := 0.0
	while t < dur:
		_step(2, walk)
		t += DT * 2
		await _sample("%s %.2f" % [label, t])
	p.aiming = true
	p.sprinting = false
	p.velocity = Vector3.ZERO
	_step(60)


func _summary() -> void:
	var bad := 0
	for r in report:
		var w: Dictionary = r[4]
		var defect := float(w.get("back", 0.0)) > DEF_BACK or float(w.get("near", 0.0)) > DEF_NEAR or float(w.get("rear", 0.0)) > DEF_REAR or float(w.get("pop", 0.0)) > DEF_POP
		if defect:
			bad += 1
			print("[vms] DEFAUT %s%s fov %d %s : %s (ads %.2f) dos %.2f %% proche %.2f %% arriere %.2f %% saut %.2f %%" % [r[0], " PaP" if r[1] else "", r[2], r[3], w.state, w.ads, float(w.back) * 100.0, float(w.near) * 100.0, float(w.get("rear", 0.0)) * 100.0, float(w.get("pop", 0.0)) * 100.0])
		if r[2] == 80 and r[3] == "16x9" and not r[1]:
			print("[vms] %s : carcasse arriere en visee tenue max %.2f %%" % [r[0], float(w.get("rear_max", 0.0)) * 100.0])
	at.check(bad == 0, "crosse / carcasse jamais ouverte ni contre l'œil (%d passes en défaut sur %d)" % [bad, report.size()])


# --------------------------------------------------------------------------
# VMS_GAME=1 : la même revue dans une VRAIE partie (Player, WeaponController,
# rendu temps réel de la fenêtre) : captures de la fenêtre image par image.

func _game_shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := tree().root.get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_png("%s/%s_jeu_%s.png" % [shot_dir, tag, fname])


func _game_pass() -> void:
	var H := AutotestHelpers
	var pl := await H.start_solo_game(self)
	if pl == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var pdata := game.session.local_data()
	var ids: Array = WeaponDB.WEAPONS.keys()
	var only := OS.get_environment("VMS_ONLY")
	if only != "":
		ids = Array(only.split(","))
	for id in ids:
		pdata.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id)]
		pdata.slot = 1
		game.session.sync_inventory(1)
		await until(func(): return pl.weapons.current().get("id", "") == id, 2.0, "arme %s" % id)
		await seconds(WeaponController.SWITCH_TIME + 0.3)
		await _game_shot("%s_hanche" % id)
		pl.input.aim = true
		var t0 := Time.get_ticks_msec()
		var k := 0
		while Time.get_ticks_msec() - t0 < 500:
			k += 1
			await _game_shot("%s_montee_%02d_%.2f" % [id, k, pl.weapons.view.ads])
		await _game_shot("%s_visee" % id)
		pl.input.fire = true
		for j in 6:
			await _game_shot("%s_tir_%d" % [id, j])
		pl.input.fire = false
		pl.input.aim = false
		await seconds(0.5)
