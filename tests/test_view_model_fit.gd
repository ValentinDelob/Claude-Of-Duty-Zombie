extends TestCase
## Vue FPS, arme par arme (sans partie : ViewModel seul sous une caméra) :
## 1. rien de l'arme ni des mains ne passe à l'écran plus près de l'œil que
##    le plan proche + une marge — hanche, montée en visée, visée, tir en
##    visée (recul), rechargement, sprint, plongeon, changement d'arme — et
##    aucun bout de manche (bras « coupé » qui flotte) n'est à l'écran ;
## 2. en visée complète, la carcasse derrière le cran (boîtier, crosse, tube)
##    ne remplit pas le bas de l'écran : rien de visible à moins de
##    ADS_MIN_DEPTH de l'œil ;
## 3. la joue de visée (ViewModel.bend) ne déplace ni le cran ni le guidon ;
## 4. les mains tiennent l'arme : chaque main est posée sur une pièce
##    (poignée, garde-main, poignée avant, main droite), la main d'appui n'est
##    pas au-dessus de l'arme, et les avant-bras ne traversent pas l'arme ;
## 5. actions lancées EN VISÉE (couteau, fente, changement d'arme, grenade,
##    boisson, couteau de chasse, plongeon, sprint, visée depuis le sprint,
##    marche, regard), armes normales ET Pack-a-Punch, champ de vision min /
##    défaut / max : rien à moins de NEAR + NEAR_MARGIN de l'œil, la crosse
##    (groupe "rear") n'est jamais masquée d'un coup ;
## 6. la partie courbée par la joue est assez découpée (WeaponMesh.slice_z)
##    pour que la déformation PAR SOMMET du shader suive la courbe : sinon un
##    long flanc de crosse reste plat entre un bout intact et un bout abaissé
##    et traverse les pièces voisines (crosse « ouverte » contre l'œil).
## Toutes les profondeurs sont prises APRÈS la joue, avec la formule même du
## shader (ViewModel.bend) ; le champ de l'arme ne dépend pas du champ de
## vision réglé (vm_fov_scale), l'écran le plus large (21:9) couvre les autres.

## Plan proche de la caméra du joueur (Player : camera.near) + marge.
const NEAR := 0.03
const NEAR_MARGIN := 0.02
## Visée complète : profondeur minimale de ce qui est visible (m). La joue
## courbe la carcasse dès 2 cm derrière le cran : sur une arme dont le cran
## est à 15 cm de l'œil (M16, FN FAL), le début de la courbe est visible
## jusqu'à ~11 cm (la crosse sort de l'écran juste derrière).
const ADS_MIN_DEPTH := 0.10
## Champs de vision du menu des options (min, défaut, max).
const FOVS := [60.0, 80.0, 110.0]
## Écran le plus large pris en compte (21:9), et 16:9 pour la visée.
const WIDE := 21.0 / 9.0
const NORMAL := 16.0 / 9.0
const DT := 1.0 / 60.0

var _cam: Camera3D
var _vm: ViewModel
var _p: Player
## Sommets (repère du maillage) par maillage.
var _verts: Dictionary = {}


func before_each() -> void:
	_cam = Camera3D.new()
	_cam.fov = Settings.fov
	_base_fov = Settings.fov
	_cam.near = NEAR
	host.add_child(_cam)
	_vm = ViewModel.new()
	_cam.add_child(_vm)
	_p = Player.new()
	_p.weapons = WeaponController.new()


func after_each() -> void:
	_cam.queue_free()
	_p.weapons.free()
	_p.free()


## Toutes les armes tenables (arsenal + armes de bonus).
static func weapon_ids() -> Array:
	return WeaponDB.WEAPONS.keys() + WeaponDB.POWERUP_WEAPONS.keys()


static func _scoped(s: Dictionary, ads: float) -> bool:
	return WeaponDB.scope_kind(s) != "" and ads >= ViewModel.SCOPE_ADS


func _equip(id: String, pap := false) -> Dictionary:
	var w := WeaponDB.new_instance(id, pap)
	_p.weapons.weapons = [w]
	_p.weapons.slot = 0
	_p.aiming = false
	_p.sprinting = false
	_p.diving = false
	_p.velocity = Vector3.ZERO
	_p.input = PlayerInput.new()
	_vm.set_weapon(id, pap)
	_vm.ads = 0.0
	_vm.scoped = false
	_vm.lowered = 0.0
	return WeaponDB.stats(id, pap)


## Champ de vision réglé (Settings.fov) pendant _step : la caméra suit le
## jeu (zoom de visée, sprint), comme Player._update_camera_effects.
var _base_fov := 80.0


## Un pas de simulation (horloge de jeu comprise : rechargement, changement).
func _step(n := 1) -> void:
	for i in n:
		GameClock._t += DT
		var s := _vm._stats
		var target := _base_fov
		if _p.aiming and not s.is_empty():
			var k := clampf(_vm.ads, 0.0, 1.0)
			target = lerpf(_base_fov, _base_fov * float(s.ads_zoom), k * k * (3.0 - 2.0 * k))
		elif _p.sprinting:
			target = _base_fov * 1.06
		_cam.fov = lerpf(_cam.fov, target, 1.0 - exp(-DT * 14.0))
		_vm.update(DT, _p)
		# Écran de lunette : comme WeaponController (arme masquée).
		_vm.apply_scope(_p.aiming and _scoped(_vm._stats, _vm.ads) and not _vm.is_busy())


func _mesh_verts(mi: MeshInstance3D) -> PackedVector3Array:
	var key := mi.mesh.get_rid().get_id()
	if not _verts.has(key):
		var all := PackedVector3Array()
		for si in mi.mesh.get_surface_count():
			all.append_array(mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
		_verts[key] = all
	return _verts[key]


var _chunks: Dictionary = {}
## tan(demi-champ vertical de l'arme) de l'échantillon en cours (_near_tris).
var _th := 1.0


## Triangles d'un maillage par paquets de CHUNK sommets : [boîte, sommets].
func _mesh_chunks(mi: MeshInstance3D) -> Array:
	var key := mi.mesh.get_rid().get_id()
	if _chunks.has(key):
		return _chunks[key]
	var all := _mesh_verts(mi)
	var out := []
	var chunk := 96
	for s in range(0, all.size(), chunk):
		var v := all.slice(s, mini(s + chunk, all.size()))
		var box := AABB(v[0], Vector3.ZERO)
		for p in v:
			box = box.expand(p)
		out.append([box, v])
	_chunks[key] = out
	return out


## Triangles (repère de la caméra, joue de visée appliquée) des maillages
## affichés de `n` dont une partie est à moins de `limit` m de l'œil.
func _near_tris(n: Node3D, xf: Transform3D, b: Vector3, limit: float, out: PackedVector3Array) -> void:
	if not n.visible:
		return
	var x := xf * n.transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var box := x * mi.mesh.get_aabb()
		if -box.end.z < limit:
			# Par paquets de triangles voisins (boîte englobante propre) : seuls
			# ceux qui passent à moins de `limit` de l'œil sont courbés et
			# découpés (la joue ne change pas la profondeur).
			for ch: Array in _mesh_chunks(mi):
				var cb := x * (ch[0] as AABB)
				# Trop loin, tout entier plus près que le plan proche (ou
				# derrière l'œil), ou tout entier sous le bas de l'écran avant
				# même la joue (qui ne fait que l'abaisser) : invisible.
				if -cb.end.z >= limit or -cb.position.z < NEAR:
					continue
				if cb.end.y < cb.position.z * _th and cb.end.y < cb.end.z * _th:
					continue
				var v := x * (ch[1] as PackedVector3Array)
				if b.z > 0.0:
					for i in v.size():
						if -v[i].z < b.x:
							v[i] = ViewModel.bend(v[i], b)
				out.append_array(v)
	for c in n.get_children():
		if c is Node3D:
			_near_tris(c, x, b, limit, out)


## Découpe d'un polygone par le demi-espace dot(pl.xyz, p) + pl.w >= 0.
static func _clip(poly: Array, pl: Vector4) -> Array:
	var out := []
	var cnt := poly.size()
	for i in cnt:
		var a: Vector3 = poly[i]
		var c: Vector3 = poly[(i + 1) % cnt]
		var da := a.x * pl.x + a.y * pl.y + a.z * pl.z + pl.w
		var dc := c.x * pl.x + c.y * pl.y + c.z * pl.z + pl.w
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (dc >= 0.0):
			out.append(a.lerp(c, da / (da - dc)))
	return out


## Profondeur (m) du point visible le plus proche de l'œil parmi `tris`
## (parties de triangles dans le champ de vision de l'arme `fov`, écran de
## rapport `aspect`), plafonnée à `limit`.
static func nearest_visible(tris: PackedVector3Array, fov: float, aspect: float, limit: float) -> float:
	var th := tan(deg_to_rad(fov) * 0.5)
	var tw := th * aspect
	# Profondeur = -z : devant l'œil, puis les quatre bords du champ.
	var planes := [Vector4(0, 0, -1, -0.001), Vector4(-1, 0, -tw, 0), Vector4(1, 0, -tw, 0), Vector4(0, -1, -th, 0), Vector4(0, 1, -th, 0)]
	var best := limit
	var i := 0
	while i < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		if -a.z >= best and -b.z >= best and -c.z >= best:
			continue
		# Rejet rapide : les trois sommets hors du même bord du champ (sous
		# l'écran, le plus souvent : carcasse courbée par la joue).
		if a.y < a.z * th and b.y < b.z * th and c.y < c.z * th:
			continue
		if a.y > -a.z * th and b.y > -b.z * th and c.y > -c.z * th:
			continue
		if a.x > -a.z * tw and b.x > -b.z * tw and c.x > -c.z * tw:
			continue
		if a.x < a.z * tw and b.x < b.z * tw and c.x < c.z * tw:
			continue
		var poly := [a, b, c]
		for pl in planes:
			poly = _clip(poly, pl)
			if poly.is_empty():
				break
		for q: Vector3 in poly:
			best = minf(best, -q.z)
	return best


## Profondeur du point visible le plus proche dans la pose courante du
## ViewModel (limit si rien de plus proche).
func _nearest_now(aspect: float, limit: float) -> float:
	if _vm.model == null or not _vm.model.visible:
		return limit
	var ak := _vm.ads * _vm.ads * (3.0 - 2.0 * _vm.ads)
	var tris := PackedVector3Array()
	_th = tan(deg_to_rad(_vm.view_fov()) * 0.5)
	_near_tris(_vm.model, _vm.transform, ViewModel.bend_params(_vm.model_id, ak) if not _vm.scoped else Vector3.ZERO, limit, tris)
	return nearest_visible(tris, _vm.view_fov(), aspect, limit)


func _sample(worst: Array, what: String) -> void:
	var d := _nearest_now(WIDE, 0.1)
	if d < worst[0]:
		worst[0] = d
		worst[1] = what
	var cut := _sleeve_end_on_screen()
	if cut != "" and worst.size() < 3:
		worst.append("%s (%s)" % [cut, what])


## Bout de manche (côté coude) visible à l'écran : bras « coupé » qui flotte.
## Retourne le côté ("droit", "gauche") ou "".
func _sleeve_end_on_screen() -> String:
	if _vm.model == null or not _vm.model.visible:
		return ""
	var h := _vm.hands
	var ak := _vm.ads * _vm.ads * (3.0 - 2.0 * _vm.ads)
	var b := ViewModel.bend_params(_vm.model_id, ak)
	var base := _vm.transform * _vm.model.transform * h.transform
	var th := tan(deg_to_rad(_vm.view_fov()) * 0.5)
	var tw := th * NORMAL
	for a in [["droit", h.hand_r.transform * h.hand_r.get_child(h.hand_r.get_child_count() - 1).transform], ["gauche", h.arm_l.transform]]:
		# Bout de la manche, derrière le coude (ViewHands.SLEEVE_BACK), rayon
		# ~5 cm.
		var c := ViewModel.bend(base * (a[1] as Transform3D) * Vector3(0, 0, ViewHands.ARM_LEN * ViewHands.SLEEVE_BACK), b)
		var dd := -c.z
		var r := 0.05
		if dd > NEAR and absf(c.x) - r < dd * tw and absf(c.y) - r < dd * th:
			return a[0]
	return ""


func test_nothing_crosses_near_plane() -> void:
	var limit := NEAR + NEAR_MARGIN
	for id in weapon_ids():
		var s := _equip(id)
		var worst := [0.1, ""]
		_step(20)
		_sample(worst, "hanche")
		# Montée en visée, visée, tir en visée (recul accumulé).
		_p.aiming = true
		for i in 30:
			_step()
			if i % 3 == 0:
				_sample(worst, "montée en visée %.2f" % _vm.ads)
		var interval := WeaponDB.fire_interval(id)
		var next := 0.0
		var t := 0.0
		while t < 1.2:
			if t >= next:
				_vm.fire(s, null, _p, false)
				next += interval
			_step()
			t += DT
			if int(t / DT) % 4 == 0:
				_sample(worst, "tir en visée")
		_p.aiming = false
		_step(30)
		# Rechargement (chargeur vide), à la hanche.
		_p.weapons.weapons[0].mag = 0
		var rt := float(s.reload)
		if not s.get("infinite", false):
			_vm.start_reload(rt)
			t = 0.0
			while t < rt + 0.05:
				_step(5)
				t += DT * 5
				_sample(worst, "rechargement %.2f" % (t / rt))
		# Sprint, plongeon.
		_p.sprinting = true
		_step(30)
		_sample(worst, "sprint")
		_p.sprinting = false
		_p.diving = true
		_step(20)
		_sample(worst, "plongeon")
		_p.diving = false
		# Changement d'arme (rangement puis sortie).
		_vm.start_switch(WeaponController.SWITCH_TIME, func(): pass)
		t = 0.0
		while t < WeaponController.SWITCH_TIME + 0.05:
			_step(3)
			t += DT * 3
			_sample(worst, "changement d'arme")
		assert_true(worst[0] >= limit, "%s : arme ou main à %.3f m de l'œil (%s), sous le plan proche + marge (%.2f m)" % [id, worst[0], worst[1], limit])
		assert_true(worst.size() < 3, "%s : bout de manche du bras %s visible à l'écran (bras coupé)" % [id, worst[2] if worst.size() > 2 else ""])


func test_ads_rear_does_not_fill_screen() -> void:
	for id in weapon_ids():
		var s := _equip(id)
		_vm.ads = 1.0
		_vm.scoped = _scoped(s, 1.0)
		if _vm.scoped or WeaponModels.info(s.model, "no_sights", false):
			continue
		_p.aiming = true
		_step(2)
		var d := _nearest_now(NORMAL, ADS_MIN_DEPTH)
		assert_true(d >= ADS_MIN_DEPTH, "%s : en visée, carcasse visible à %.3f m de l'œil (min %.3f)" % [id, d, ADS_MIN_DEPTH])


func test_bend_keeps_sight_line() -> void:
	for id in WeaponDB.WEAPONS:
		var mid: String = WeaponDB.stats(id).model
		var xf := ViewModel.rest_transform(mid, 1.0)
		var b := ViewModel.bend_params(mid, 1.0)
		for a in ["sight", "front"]:
			var p := xf * WeaponModels.anchor(mid, a)
			assert_true(ViewModel.bend(p, b).distance_to(p) < 0.00001, "%s : joue de visée sans effet sur %s" % [id, a])
			# Sur l'axe de la caméra (celui des balles).
			assert_true(Vector2(p.x, p.y).length() < 0.0005, "%s : %s sur l'axe (%.4f m)" % [id, a, Vector2(p.x, p.y).length()])
	assert_eq(ViewModel.bend_params(PowerupRules.DEATH_MACHINE_WEAPON, 1.0), Vector3.ZERO, "minigun : pas de joue (pas de visée)")
	# Rien à la hanche.
	assert_eq(ViewModel.bend_params("m14", 0.0).z, 0.0)


## En visée complète, `start` lance une action ; échantillons toutes les
## 3 images pendant `dur` s (pire profondeur dans `worst`), puis retour en
## visée. La crosse ne doit jamais être masquée.
func _ads_action(worst: Array, what: String, start: Callable, dur: float) -> void:
	_p.aiming = true
	_p.sprinting = false
	_p.diving = false
	_p.velocity = Vector3.ZERO
	_settle()
	start.call()
	var t := 0.0
	while t < dur:
		_step(3)
		t += DT * 3
		_sample(worst, what)
		if _vm._groups.has("rear") and _vm.model.visible and not (_vm._groups.rear as Node3D).visible and worst.size() < 4:
			worst.append("crosse masquée (%s)" % what)
	_p.aiming = true
	_p.sprinting = false
	_p.diving = false
	_vm.lowered = 0.0
	_p.velocity = Vector3.ZERO


## Pas jusqu'au retour en visée complète, au repos (au plus 1,5 s).
func _settle() -> void:
	for k in 90:
		if _vm.ads >= 1.0 and not _vm.is_busy() and not _vm.is_knife_busy() and not _vm.is_drinking() and _vm._lower <= 0.0 and _vm._sprint <= 0.0 and _vm._dive <= 0.0:
			return
		_step()


func test_ads_actions_keep_the_stock_clear() -> void:
	var limit := NEAR + NEAR_MARGIN
	var i := 0
	for id in weapon_ids():
		for pap in ([false] if WeaponDB.is_powerup_weapon(id) else [false, true]):
			# Champ de vision réglé : min, défaut, max à tour de rôle (le champ
			# de l'arme n'en dépend pas : vm_fov_scale).
			_base_fov = FOVS[i % FOVS.size()]
			i += 1
			var s := _equip(id, pap)
			var worst := [0.1, ""]
			_cam.fov = _base_fov
			_step(10)
			_p.aiming = true
			_settle()
			# Visée en marchant, en regardant en haut, en bas, sur les côtés.
			_p.velocity = Vector3(3.0, 0.0, 2.0)
			for j in 5:
				_vm._bob += DT * 3 * 3.6 * 2.0
				_step(3)
				_sample(worst, "visée en marchant")
			_p.velocity = Vector3.ZERO
			for look in [Vector2(0, -900), Vector2(0, 900), Vector2(900, 0), Vector2(-900, 0)]:
				_p.input.look = look
				_step(6)
				_sample(worst, "visée, regard %s" % look)
			_p.input.look = Vector2.ZERO
			# Animations propres au modèle (identiques après Pack-a-Punch, qui ne
			# change que la cadence, le recul et la durée de mise en joue).
			if not pap:
				_ads_action(worst, "couteau en visée", func(): _vm.start_melee(false), ViewModel.MELEE_ANIM)
				_ads_action(worst, "fente en visée", func(): _vm.start_melee(true), ViewModel.MELEE_ANIM)
				_ads_action(worst, "changement d'arme en visée", func(): _vm.start_switch(WeaponController.SWITCH_TIME, func(): pass), WeaponController.SWITCH_TIME)
				_ads_action(worst, "grenade en visée", func(): _vm.lowered = 1.0, 0.5)
				_ads_action(worst, "boisson en visée", func(): _vm.start_drink(Color.RED, 1.0), 1.0)
				_ads_action(worst, "couteau de chasse en visée", func(): _vm.start_knife_pickup(1.0), 1.0)
			else:
				# Tir en visée : recul de l'arme améliorée.
				_settle()
				var interval := WeaponDB.fire_interval(id, true)
				var next := 0.0
				var t := 0.0
				while t < 0.6:
					if t >= next:
						_vm.fire(s, null, _p, false)
						next += interval
					_step(2)
					t += DT * 2
					_sample(worst, "tir en visée (PaP)")
			# Plongeon et sprint : le jeu lâche la visée (Player._update_stance).
			_ads_action(worst, "plongeon depuis la visée", func():
				_p.aiming = false
				_p.diving = true, 0.4)
			_ads_action(worst, "sprint depuis la visée", func():
				_p.aiming = false
				_p.sprinting = true
				_p.velocity = Vector3(0, 0, -6.5), 0.5)
			# Visée en sortant du sprint.
			_p.aiming = false
			_p.sprinting = true
			_step(30)
			_p.sprinting = false
			_p.velocity = Vector3.ZERO
			_p.aiming = true
			for j in 10:
				_step(2)
				_sample(worst, "visée depuis le sprint")
			_vm.cancel_reload()
			assert_true(worst[0] >= limit, "%s%s (champ %d) : arme ou main à %.3f m de l'œil (%s), sous le plan proche + marge (%.2f m)" % [id, " PaP" if pap else "", int(_base_fov), worst[0], worst[1], limit])
			assert_true(worst.size() < 3, "%s%s : %s" % [id, " PaP" if pap else "", ", ".join(worst.slice(2))])
	_base_fov = Settings.fov


## Plus grand écart en z (repère du modèle) d'une arête de triangle dans la
## partie courbée par la joue de visée.
static func longest_bent_edge(mid: String) -> float:
	var sight_z := WeaponModels.anchor(mid, "sight").z
	# Profondeur du départ de la joue dans le repère du modèle (visée : l'axe
	# de l'arme est celui de la caméra) : tout ce qui est plus en arrière.
	var from := sight_z + WeaponModels.anchor(mid, "ads").z - ViewModel.bend_start(mid)
	var worst := 0.0
	var geo := WeaponModels.geometry(mid, true)
	for g in geo:
		var oz: float = (geo[g].pivot as Vector3).z
		for mk in geo[g].meshes:
			var m: ArrayMesh = geo[g].meshes[mk]
			var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var k := 0
			while k + 2 < v.size():
				for e in 3:
					var a := v[k + e].z + oz
					var b := v[k + (e + 1) % 3].z + oz
					if maxf(a, b) > from:
						worst = maxf(worst, absf(a - b))
				k += 3
	return worst


func test_bent_part_is_finely_sliced() -> void:
	for id in weapon_ids():
		var mid: String = WeaponDB.stats(id).model
		if ViewModel.bend_drop(mid) <= 0.0:
			continue
		var e := longest_bent_edge(mid)
		assert_true(e <= WeaponModels.BEND_SLICE + 0.0005, "%s : arête de %.3f m le long de l'arme dans la partie courbée (max %.3f)" % [id, e, WeaponModels.BEND_SLICE])
	# Découpe sans fissure : deux triangles qui partagent une arête sont
	# coupés aux mêmes points (plans communs).
	var arr := [PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0.1), Vector3(0, 1, 0.1), Vector3(1, 0, 0.1), Vector3(1, 1, 0.0), Vector3(0, 1, 0.1)]),
		PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])]
	var out: Array = WeaponMesh.slice_z(arr, 0.0, 0.03)
	var pts := {}
	for p: Vector3 in out[0]:
		if absf(p.z - 0.03) < 0.0001 or absf(p.z - 0.06) < 0.0001 or absf(p.z - 0.09) < 0.0001:
			pts[Vector3(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001))] = true
	# Arête commune (1,0,0.1)-(0,1,0.1) à z constant : jamais coupée ; les
	# arêtes de chaque côté sont coupées à 0,03 / 0,06 / 0,09.
	assert_true(pts.size() >= 6, "points de découpe (%d)" % pts.size())
	var area_in := 0.0
	var area_out := 0.0
	for k in range(0, 6, 3):
		area_in += (arr[0][k + 1] - arr[0][k]).cross(arr[0][k + 2] - arr[0][k]).length()
	for k in range(0, (out[0] as PackedVector3Array).size(), 3):
		area_out += (out[0][k + 1] - out[0][k]).cross(out[0][k + 2] - out[0][k]).length()
	assert_near(area_out, area_in, 0.0001, "découpe : même surface")


# --------------------------------------------------------------------------
# Mains

## Boîtes orientées des pièces d'un modèle : [centre, base, demi-tailles].
static func part_boxes(mid: String) -> Array:
	var out := []
	for part in WeaponModels.spec(mid).parts:
		var b := WeaponModels._part_basis(part)
		var lb := WeaponModels._local_box(part)
		out.append([part[2] + b * lb[0], b, lb[1] * 0.5])
	return out


## Distance signée d'un point à une boîte orientée (négative dedans).
static func box_sd(p: Vector3, box: Array) -> float:
	var local: Vector3 = (box[1] as Basis).transposed() * (p - box[0])
	var q: Vector3 = local.abs() - box[2]
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func dist_to_boxes(p: Vector3, boxes: Array) -> float:
	var best := INF
	for box in boxes:
		best = minf(best, box_sd(p, box))
	return best


## Sommets (repère du modèle) des maillages sous `n`.
func _node_verts(n: Node3D, xf: Transform3D, out: PackedVector3Array) -> void:
	var x := xf * n.transform
	if n is MeshInstance3D:
		out.append_array(x * _mesh_verts(n))
	for c in n.get_children():
		if c is Node3D:
			_node_verts(c, x, out)


## Part des sommets de `verts` à moins de `tol` m d'une des boîtes.
static func contact_ratio(verts: PackedVector3Array, boxes: Array, tol: float) -> float:
	var near := 0
	var step := maxi(verts.size() / 400, 1)
	var n := 0
	for i in range(0, verts.size(), step):
		n += 1
		if dist_to_boxes(verts[i], boxes) <= tol:
			near += 1
	return float(near) / maxf(n, 1)


func test_hands_hold_the_weapon() -> void:
	for id in weapon_ids():
		var s := _equip(id)
		var mid: String = s.model
		var boxes := part_boxes(mid)
		var h := _vm.hands
		# Main (poing ou berceau, sans l'avant-bras) de chaque côté.
		var right := PackedVector3Array()
		_node_verts(h.hand_r.get_child(0), h.transform * h.hand_r.transform, right)
		var left := PackedVector3Array()
		_node_verts(h.hand_l.get_child(0), h.transform * h.hand_l.transform, left)
		var rr := contact_ratio(right, boxes, 0.02)
		# Main gauche sur un pistolet : sur la main droite (sa boîte englobante).
		var lboxes := boxes.duplicate()
		var raabb := AABB(right[0], Vector3.ZERO)
		for v in right:
			raabb = raabb.expand(v)
		lboxes.append([raabb.get_center(), Basis.IDENTITY, raabb.size * 0.5])
		var lr := contact_ratio(left, lboxes, 0.02)
		assert_true(rr >= 0.8, "%s : main droite posée sur la poignée (%.0f %% des sommets à moins de 2 cm)" % [id, rr * 100.0])
		assert_true(lr >= 0.8, "%s : main gauche posée sur l'arme (%.0f %% des sommets à moins de 2 cm)" % [id, lr * 100.0])
		# La main d'appui n'est pas au-dessus de l'arme : son centre est sous
		# la ligne de mire (et sous l'axe du canon, sauf poignée pistolet).
		var lc := AABB(left[0], Vector3.ZERO)
		for v in left:
			lc = lc.expand(v)
		var line := WeaponModels.anchor(mid, "sight").y
		assert_true(lc.get_center().y < line and lc.end.y < line + 0.03, "%s : main gauche sous la ligne de mire (centre %.3f, haut %.3f, ligne %.3f)" % [id, lc.get_center().y, lc.end.y, line])


func test_forearms_do_not_cross_the_weapon() -> void:
	for id in weapon_ids():
		var s := _equip(id)
		var boxes := part_boxes(s.model)
		var h := _vm.hands
		var arms := [["droit", h.transform * h.hand_r.transform * h.hand_r.get_child(1).transform],
			["gauche", h.transform * h.arm_l.transform]]
		for a in arms:
			var xf: Transform3D = a[1]
			var worst := INF
			# Axe de l'avant-bras, du coude au poignet (le poignet, dans la main,
			# touche forcément l'arme : 75 % de la longueur).
			for k in 16:
				var p := xf * Vector3(0, 0, -ViewHands.ARM_LEN * 0.75 * k / 15.0)
				worst = minf(worst, dist_to_boxes(p, boxes))
			assert_true(worst > 0.0, "%s : avant-bras %s qui traverse l'arme (axe à %.3f m dans une pièce)" % [id, a[0], -worst])
