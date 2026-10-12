extends TestCase
## Table d'armes (docs/WEAPONS.md) : champs requis, noms FR / EN originaux
## ou proches du vrai (jamais le nom exact d'un fabricant ni d'un modèle
## réel), niveaux de base répartis de 1 à 50 selon la puissance, batte de
## baseball (arme de base de corps à corps), valeurs « pap » en sommeil,
## modèles cubiques (cubes de 2,5 cm ; armes fines : 1,25 cm).

## Mots interdits dans un nom d'arme : fabricants et désignations exactes
## des modèles réels (GAME_CONCEPT §4.9, §6). Un nom PROCHE du vrai est
## permis (M1912 pour le Colt M1911A1), le vrai jamais.
const REAL_NAMES := ["M1911", "M1911A1", "1911", "CZ75", "CZ", "PYTHON", "COLT", "MP40", "MP5K", "MP5", "PM63", "MPL", "SPECTRE",
	"AK74U", "AK74u", "AK", "AK-74", "M14", "M16", "COMMANDO", "FN", "FAL", "G11", "GALIL", "FAMAS", "AUG", "RPK",
	"HK21", "HK", "OLYMPIA", "STAKEOUT", "SPAS-12", "SPAS", "HS10", "DRAGUNOV", "L96A1", "L96", "CHINA", "LAKE",
	"LAW", "M72", "BERETTA", "GLOCK", "REMINGTON", "WINCHESTER", "BROWNING", "WALTHER", "KALASHNIKOV", "HECKLER",
	"KOCH", "STEYR", "BARRETT", "MOSSBERG", "BENELLI", "SIG", "UZI", "THOMPSON", "RUGER", "TAURUS", "SMITH",
	"WESSON", "LUGER", "MAUSER", "ENFIELD", "SKS", "SVD", "MAC-10", "TEC-9",
	"AK47", "AKS", "AKS74U", "AKM", "MAS", "MP41", "MP44"]

## Armes refaites d'après une arme réelle (refonte du 2026-10-12, fiches
## docs/weapons/<id>.md) : id -> [nom affiché FR = EN, référence réelle].
const REMADE := {
	"m1911": ["M1912", "Colt M1911A1"],
	"mp40": ["MR-40", "MP40"],
	"ak74u": ["KA-74U", "AKS-74U"],
	"ak47": ["KA-47", "AK-47 type 3"],
	"famas": ["FAMAX F1", "FAMAS F1"],
}


func test_every_weapon_has_required_fields() -> void:
	for id in WeaponDB.WEAPONS:
		for pap in [false, true]:
			var s := WeaponDB.stats(id, pap)
			for k in WeaponDB.REQUIRED:
				assert_true(s.has(k), "%s (pap %s) : champ %s" % [id, pap, k])
			if WeaponDB.is_melee(id):
				assert_eq(int(s.mag), 0, "%s : corps à corps sans munitions" % id)
				assert_true(s.get("infinite", false), "%s : pas de compteur de munitions" % id)
			else:
				assert_true(int(s.mag) > 0 and int(s.reserve) >= int(s.mag), "%s : chargeur/réserve" % id)
			assert_true(int(s.damage) > 0 and int(s.rpm) > 0 and float(s.reload) > 0.0, "%s : dégâts/cadence" % id)
			assert_true(WeaponDB.CLASSES.has(s["class"]), "%s : famille connue" % id)
			assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % s.sound), "%s : son %s" % [id, s.sound])
			if s.has("cycle"):
				assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % s.cycle), "%s : son du mécanisme" % id)
		if not WeaponDB.is_melee(id):
			assert_true(WeaponDB.WEAPONS[id].has("pap"), "%s : valeurs Pack-a-Punch (en sommeil)" % id)


func test_starting_weapon() -> void:
	var s := WeaponDB.stats(WeaponDB.STARTING_WEAPON)
	assert_eq(WeaponDB.STARTING_WEAPON, "m1911")
	# M1912 (Colt M1911A1 réel, docs/weapons/m1911.md) : 7 coups, 10 chargeurs.
	assert_eq(int(s.mag), 7)
	assert_eq(int(s.reserve), 70)
	assert_eq(int(s.damage), 30)
	assert_eq(int(s.rpm), 360)
	assert_false(bool(s.auto), "semi-automatique")
	assert_near(float(s.reload), 1.7, 0.001)
	assert_near(float(s.range), 22.0, 0.001)
	# Pistolet de départ peu efficace (manche 1, 150 PV) : 5 à 8 balles.
	var shots := ceili(150.0 / float(s.damage))
	assert_true(shots >= 5 and shots <= 8, "pistolet de départ : %d balles au corps en manche 1" % shots)
	assert_true(WeaponDB.MELEE_DAMAGE >= 150, "couteau : un coup en manche 1")


## Armes refaites (fiches validées le 2026-10-12) : nom proche du vrai, le
## même en anglais, référence réelle dans la fiche DÉTAILS, modèle fin.
func test_remade_weapons() -> void:
	for id in REMADE:
		var fr: String = REMADE[id][0]
		assert_eq(String(WeaponDB.stats(id).name), fr, "%s : nom affiché" % id)
		assert_eq(String(WeaponDB.EN_NAMES.get(fr, "")), fr, "%s : même nom en anglais" % id)
		assert_eq(WeaponDB.real_ref(id), REMADE[id][1], "%s : référence réelle" % id)
		assert_false(fr in REAL_NAMES or fr.replace("-", "") in REAL_NAMES, "%s : jamais le nom exact" % id)
		assert_true(WeaponModels.is_fine(id), "%s : arme fine (1,25 cm)" % id)
	# Olympia : fiche et modèle prêts, pas encore validée (ni nom, ni référence).
	assert_eq(WeaponDB.real_ref("olympia"), "")
	assert_false(WeaponModels.is_fine("olympia"), "olympia : pas encore intégrée")


## Largeurs paires (weapons_fine.py, `even=True` : MR-40) : l'axe du canon
## passe ENTRE deux colonnes de cubes (x = 0), pavés sans décalage d'un
## demi-cube, arêtes sur la grille de 1,25 cm ; largeurs impaires (KA-74U) :
## colonne centrale sur l'axe, arêtes décalées d'un demi-cube.
func test_even_width_fine_model() -> void:
	var c := WeaponModels.CUBE_FINE
	for row in [["mp40", 0.0], ["ak74u", 0.5]]:
		var id: String = row[0]
		for part in WeaponModels.spec(id).parts:
			var ctr: Vector3 = part[2]
			var sz: Vector3 = part[1]
			for e in [ctr.x - sz.x * 0.5, ctr.x + sz.x * 0.5]:
				var n: float = e / c - float(row[1])
				assert_near(n, roundf(n), 0.001, "%s : arête x = %.5f m sur la grille" % [id, e])
	for a in ["sight", "front", "muzzle"]:
		assert_near(WeaponModels.anchor("mp40", a).x, 0.0, 0.00001, "MR-40 : %s sur l'axe" % a)
	# Le canon (pavé qui porte la bouche) fait 2 colonnes, centrées sur x = 0.
	var m := WeaponModels.anchor("mp40", "muzzle") + Vector3(0, 0, 0.003)
	var found := 0
	for part in WeaponModels.spec("mp40").parts:
		if AABB(part[2] - part[1] * 0.5, part[1]).has_point(m):
			found += 1
			assert_near(part[2].x, 0.0, 0.00001, "MR-40 : canon centré sur l'axe")
			assert_near(part[1].x, 2.0 * c, 0.00001, "MR-40 : canon de 2 cubes de large")
	assert_eq(found, 1, "MR-40 : un pavé à la bouche du canon")


## Statistiques des fiches validées (docs/weapons/<id>.md).
func test_remade_weapon_stats() -> void:
	var want := {
		"mp40": {"class": "smg", "base_level": 1, "damage": 90, "rpm": 540, "mag": 32, "reserve": 192, "reload": 2.4,
			"spread_hip": 3.0, "bloom": 0.25, "recoil": 0.8, "recoil_side": 0.4, "recoil_recover": 0.6, "range": 18.0,
			"penetration": 1, "ads_time": 0.18},
		"ak74u": {"class": "smg", "base_level": 19, "damage": 100, "rpm": 700, "mag": 30, "reserve": 180, "reload": 2.4,
			"spread_hip": 2.8, "bloom": 0.35, "recoil": 1.3, "recoil_side": 0.55, "recoil_recover": 0.55, "range": 28.0,
			"penetration": 2, "ads_time": 0.2},
		"ak47": {"class": "rifle", "base_level": 23, "damage": 140, "head_mult": 2.5, "rpm": 600, "mag": 30, "reserve": 210,
			"reload": 2.6, "spread_hip": 2.8, "bloom": 0.4, "recoil": 1.6, "recoil_side": 0.6, "recoil_recover": 0.5,
			"range": 40.0, "penetration": 3, "move_mult": 0.95, "ads_time": 0.24, "ads_zoom": 0.75, "sound": "rifle_fire"},
		"famas": {"class": "rifle", "base_level": 26, "damage": 100, "rpm": 950, "mag": 25, "reserve": 175, "reload": 2.8,
			"spread_hip": 2.4, "bloom": 0.35, "recoil": 1.0, "recoil_side": 0.4, "recoil_recover": 0.6, "range": 38.0,
			"penetration": 2, "ads_time": 0.22, "ads_zoom": 0.75},
	}
	for id in want:
		var s := WeaponDB.stats(id)
		assert_true(bool(s.auto), "%s : automatique" % id)
		for k in want[id]:
			var v: Variant = want[id][k]
			if k == "base_level":
				assert_eq(WeaponDB.base_level(id), v, "%s : niveau de base" % id)
			elif v is float:
				assert_near(float(s[k]), v, 0.0001, "%s : %s" % [id, k])
			else:
				assert_eq(s[k], v, "%s : %s" % [id, k])


func test_removed_weapons() -> void:
	for id in ["ray", "thunder", "death_machine"]:
		assert_false(WeaponDB.exists(id), "%s supprimée" % id)
	assert_false(WeaponDB.CLASSES.has("wonder"), "plus de famille « arme merveille »")
	for id in WeaponDB.WEAPONS:
		assert_false(WeaponDB.WEAPONS[id].has("wall_cost") or WeaponDB.WEAPONS[id].has("box"), "%s : ni mur ni boîte" % id)


## Noms : uniques, en français et en anglais, originaux ou PROCHES du vrai
## (refonte du 2026-10-12 : armes refaites d'après une arme réelle, comme
## M1912 pour le Colt M1911A1), mais jamais un nom exact de fabricant ni de
## modèle réel (mot à mot : M1911 reste interdit, M1912 est permis).
func test_original_names() -> void:
	# Le nom proche du vrai n'est pas le vrai.
	assert_eq(String(WeaponDB.stats("m1911").name), "M1912")
	assert_false("M1912" in REAL_NAMES)
	var seen_fr := {}
	var seen_en := {}
	for id in WeaponDB.WEAPONS:
		var fr: String = WeaponDB.stats(id).name
		assert_true(WeaponDB.EN_NAMES.has(fr), "%s : nom anglais de « %s »" % [id, fr])
		var en: String = WeaponDB.EN_NAMES.get(fr, "")
		assert_false(seen_fr.has(fr), "%s : nom unique (%s)" % [id, fr])
		assert_false(seen_en.has(en), "%s : nom anglais unique (%s)" % [id, en])
		seen_fr[fr] = true
		seen_en[en] = true
		assert_eq(String(WeaponDB.stats(id, true).name), fr, "%s : pas d'autre nom (amélioration en sommeil)" % id)
		for n in [fr, en]:
			for word in n.replace("-", " ").replace("'", " ").split(" ", false):
				assert_false(word.to_upper() in REAL_NAMES, "%s : « %s » contient un nom d'arme réelle (%s)" % [id, n, word])
		assert_false(WeaponDB.family_name(id).is_empty(), "%s : famille affichable" % id)


## Niveaux de base (§4.9) : armes de base au niveau 1, toutes de 1 à 50,
## au moins une arme de butin trouvable au niveau 1, et plus une arme est
## puissante (dégâts par seconde), plus son niveau de base est haut en
## moyenne : la moitié forte a un niveau moyen plus haut que la moitié faible.
func test_base_levels() -> void:
	var rows := []
	var lvl50 := false
	for id in WeaponDB.WEAPONS:
		var lvl := WeaponDB.base_level(id)
		assert_true(lvl >= 1 and lvl <= 50, "%s : niveau de base %d" % [id, lvl])
		if BaseWeapons.is_base(id):
			assert_eq(lvl, 1, "%s : arme de base au niveau 1" % id)
			continue
		lvl50 = lvl50 or lvl >= 45
		var s := WeaponDB.stats(id)
		var dps := float(s.damage) * float(s.pellets) * float(s.rpm) / 60.0 + float(s.get("splash_damage", 0.0)) * float(s.rpm) / 60.0
		rows.append([dps, lvl])
	assert_true(lvl50, "une arme de haut niveau (45 à 50)")
	assert_false(LootRules.weapon_pool(1).is_empty(), "une arme de butin dès le niveau 1")
	rows.sort()
	@warning_ignore("integer_division")
	var half := rows.size() / 2
	var weak := 0.0
	var strong := 0.0
	for i in rows.size():
		if i < half:
			weak += float(rows[i][1])
		else:
			strong += float(rows[i][1])
	assert_true(strong / float(rows.size() - half) > weak / float(half), "armes puissantes plus haut (%.1f / %.1f)" % [strong / float(rows.size() - half), weak / float(half)])


## Batte de baseball (§4.3, §4.8 bis, §4.10, §4.14) : arme de base de corps à
## corps tenue en main, plus coûteuse en énergie que le couteau, au moins
## aussi forte, portée et fente au moins celles du couteau.
func test_bat() -> void:
	assert_true(WeaponDB.exists("bat") and WeaponDB.is_melee("bat"))
	assert_eq(WeaponDB.BASE_MELEE, "bat")
	assert_true(BaseWeapons.is_base("bat"), "arme de base")
	assert_false(BaseWeapons.is_base("knife"), "le couteau n'est plus une arme de base")
	var s := WeaponDB.stats("bat")
	assert_true(float(s.energy) > KnifeDB.energy_cost(KnifeDB.DEFAULT), "plus d'énergie par coup que le couteau")
	assert_true(int(s.damage) >= KnifeDB.damage(KnifeDB.DEFAULT), "au moins les dégâts du couteau")
	assert_true(float(s.reach) >= KnifeDB.RANGE and float(s.lunge_range) >= KnifeDB.LUNGE_RANGE - 0.5, "portée et fente")
	assert_near(float(s.rpm) / 60.0, 1.25, 0.001, "1,25 coup par seconde")
	assert_eq(WeaponDB.display_name("bat"), "BATTE" if not Lang.is_en() else "BAT")
	# Arme de partie : niveau et pièces, sans munitions.
	var w := GameWeapon.make("bat", 11)
	assert_eq(int(w.mag), 0, "niveau 11 : toujours sans chargeur")
	assert_eq(int(GameWeapon.stats(w).damage), 500, "niveau 11 : dégâts doublés")
	assert_true(BuildRules.ammo_full(w), "pas de recharge de munitions à la station")


func test_special_mechanics() -> void:
	assert_eq(int(WeaponDB.stats("m16").get("burst", 0)), 3, "TRIPLETTE : rafale de 3")
	assert_eq(int(WeaponDB.stats("g11").get("burst", 0)), 3, "STROBOSCOPE : rafale de 3")
	for id in ["china_lake", "law"]:
		var s := WeaponDB.stats(id)
		assert_true(s.has("splash_radius") and s.has("projectile_speed") and s.has("self_damage"), "%s : projectile explosif" % id)
		@warning_ignore("integer_division")
		assert_true(int(s.self_damage) < int(s.splash_damage) / 5, "%s : dégâts à soi réduits" % id)
	assert_near(WeaponDB.projectile_delay("law", false, Vector3.ZERO, Vector3(0, 0, -45)), 1.0, 0.001, "roquette à 45 m/s")
	assert_eq(WeaponDB.projectile_delay("m14", false, Vector3.ZERO, Vector3(0, 0, -45)), 0.0, "balle instantanée")
	# Vitesse de déplacement : pistolets/PM rapides, mitrailleuses lentes.
	assert_true(WeaponDB.stats("m1911").move_mult > WeaponDB.stats("m16").move_mult)
	assert_true(WeaponDB.stats("mp5k").move_mult > WeaponDB.stats("hk21").move_mult)
	assert_true(WeaponDB.stats("rpk").move_mult < 0.9)
	assert_eq(String(WeaponDB.stats("olympia").reload_kind), "break")
	assert_eq(String(WeaponDB.stats("stakeout").reload_kind), "shells")
	# Rechargement cartouche par cartouche : un son par cartouche + la pompe.
	var steps := WeaponController.reload_sounds(WeaponDB.stats("stakeout"), {"mag": 3, "reserve": 30})
	assert_eq(steps.size(), 4, "3 cartouches + pompe")


## Budget de triangles d'un modèle d'arme cubique (docs/WEAPONS.md) ; armes
## fines (cubes de 1,25 cm, weapons_fine.py) : TRI_BUDGET_FINE.
const TRI_BUDGET := 1500
const TRI_BUDGET_FINE := 5000


func test_models_and_anchors() -> void:
	for id in WeaponDB.WEAPONS:
		var mid: String = WeaponDB.stats(id).model
		assert_true(WeaponModels.SPECS.has(mid), "%s : modèle défini" % id)
		assert_true(ResourceLoader.exists(WeaponModels.DIR + mid + ".glb"), "%s : modèle cubique" % id)
		var sp := WeaponModels.spec(mid)
		assert_true(sp.parts.size() >= 5, "%s : au moins 5 pavés" % id)
		for a in ["muzzle", "sight", "grip", "support"]:
			assert_true(sp.anchors.has(a), "%s : point %s" % [id, a])
		# Arme fine : taille réelle (M1912 : bouche à 13,75 cm de la détente).
		var front_min := -0.12 if WeaponModels.is_fine(mid) else -0.15
		assert_true(sp.anchors.muzzle.z < front_min, "%s : bouche du canon devant (%.3f m)" % [id, sp.anchors.muzzle.z])
		var tris := WeaponModels.triangles(mid)
		var budget := TRI_BUDGET_FINE if WeaponModels.is_fine(mid) else TRI_BUDGET
		assert_true(tris > 0 and tris <= budget, "%s : %d triangles (budget %d)" % [id, tris, budget])
		# Un maillage par matière (quelques appels de dessin).
		var mats := {}
		for g in WeaponModels.raw(mid):
			for mk in WeaponModels.raw(mid)[g]:
				mats[mk] = true
		var m := WeaponModels.build(mid, false)
		assert_eq(m.get_child_count(), mats.size(), "%s : un maillage par matériau" % id)
		m.free()
		# Vue FPS : un nœud par pièce mobile, chargeur amovible s'il existe.
		var vm := WeaponModels.build(mid, true)
		assert_true(vm.get_node_or_null("body") != null, "%s : carcasse FPS" % id)
		for part in sp.parts:
			assert_true(vm.get_node_or_null(String(part[5])) != null, "%s : groupe %s" % [id, part[5]])
		for g in sp.groups:
			if g != "body":
				assert_true(sp.anchors.has("pivot_" + g), "%s : pivot de la pièce mobile %s" % [id, g])
		vm.free()
	# Silhouettes distinctes : les armes longues sont plus longues que les pistolets.
	assert_true(WeaponModels.anchor("m1911", "muzzle").z > WeaponModels.anchor("m14", "muzzle").z)
	assert_true(WeaponModels.anchor("mp5k", "muzzle").z > WeaponModels.anchor("l96a1", "muzzle").z)


## Organes de visée : cran et guidon sur la même ligne, centrés (x = 0),
## guidon devant ; bouche du canon sous la ligne de mire (armes à visée).
func test_sight_line() -> void:
	for id in WeaponDB.WEAPONS:
		var mid: String = WeaponDB.stats(id).model
		if WeaponModels.info(mid, "no_sights", false):
			continue
		var rear := WeaponModels.anchor(mid, "sight")
		var front := WeaponModels.anchor(mid, "front")
		assert_near(rear.y, front.y, 0.0001, "%s : cran et guidon à la même hauteur" % id)
		assert_near(rear.x, 0.0, 0.0001, "%s : cran centré" % id)
		assert_near(front.x, 0.0, 0.0001, "%s : guidon centré" % id)
		assert_true(front.z < rear.z, "%s : guidon devant le cran" % id)
		assert_true(WeaponModels.anchor(mid, "muzzle").y < rear.y, "%s : bouche sous la ligne de mire" % id)


## Tous les objets tenus sont cubiques (VoxelCheck) : cubes de 2,5 cm, sauf
## les armes fines (1,25 cm, exception validée le 2026-10-12, info « cube »
## de leur modèle) ; armes d'un bloc, objets à pièces indépendantes (mains,
## grenade, peluche, cartouches) pièce par pièce. Seules des ARMES à feu et
## les MAINS de la vue FPS (taille réelle, validées le 2026-10-12) peuvent
## être fines : batte, couteau et objets lancés restent en 2,5 cm.
func test_held_models_are_cubic() -> void:
	var ids: Array = WeaponModels.SPECS.keys()
	ids.append_array([WeaponModels.HANDS, WeaponModels.FRAG, WeaponModels.TEDDY])
	var fine := 0
	for mid in ids:
		var articulated: bool = mid in [WeaponModels.HANDS, WeaponModels.FRAG, WeaponModels.TEDDY] or WeaponModels.SPECS.get(mid, "") == "round"
		var cube := WeaponModels.cube(mid)
		if WeaponModels.is_fine(mid):
			fine += 1
			var firearm: bool = WeaponDB.exists(mid) and not WeaponDB.is_melee(mid) and not articulated
			assert_true(firearm or mid == WeaponModels.HANDS, "%s : seules les armes à feu et les mains sont fines" % mid)
		else:
			assert_near(cube, WeaponModels.CUBE, 0.00001, "%s : cubes de 2,5 cm" % mid)
		var rep := VoxelCheck.check_file(ProjectSettings.globalize_path(WeaponModels.DIR + mid + ".glb"), 1 if articulated else 0, 1.0, cube)
		assert_true(bool(rep.get("ok", false)), "%s : modèle cubique en cubes de %.2f cm (%s)" % [mid, cube * 100.0, rep.get("fr", rep.get("error", ""))])
	assert_true(WeaponModels.is_fine("m1911"), "M1912 : arme fine (1,25 cm)")
	assert_true(WeaponModels.is_fine(WeaponModels.HANDS), "mains FPS en cubes de 1,25 cm")
	assert_true(fine >= 2, "au moins une arme fine et les mains")


## Budget des mains FPS (cubes de 1,25 cm, toutes les pièces) : < HANDS_BUDGET.
const HANDS_BUDGET := 6000


func test_hands_budget() -> void:
	var tris := WeaponModels.triangles(WeaponModels.HANDS)
	assert_true(tris > 0 and tris < HANDS_BUDGET, "mains : %d triangles (budget %d)" % [tris, HANDS_BUDGET])
	for piece_name in ViewHands.PIECES:
		assert_true(WeaponModels.raw(WeaponModels.HANDS).has(piece_name), "mains : pièce %s" % piece_name)
