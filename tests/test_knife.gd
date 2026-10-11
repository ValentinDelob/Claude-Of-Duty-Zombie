extends TestCase
## Règles du couteau (KnifeDB) : dégâts BO1, choix de la cible et de la
## fente. Le couteau de chasse mural est supprimé (lot C) : seul le couteau de
## base reste, attaque rapide séparée (GAME_CONCEPT §5).


func test_damage_values() -> void:
	assert_eq(KnifeDB.damage("knife"), 150, "couteau : 150")
	assert_false(KnifeDB.exists("bowie"), "couteau de chasse supprimé")
	assert_eq(KnifeDB.KNIVES.size(), 1, "seul le couteau de base")
	assert_eq(KnifeDB.damage("inconnu"), 150, "repli sur le couteau de départ")


func test_kills_by_round() -> void:
	# Couteau : un coup à la manche 1, deux à la 2.
	assert_true(KnifeDB.damage("knife") >= RoundRules.zombie_health(1))
	assert_true(KnifeDB.damage("knife") * 2 >= RoundRules.zombie_health(2))
	assert_true(KnifeDB.damage("knife") < RoundRules.zombie_health(2))


func test_pick_target_contact_and_cone() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	# Au contact devant : touché ; derrière : ignoré (sauf collé au joueur).
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 0, -1.2)]), 0)
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 0, 1.2)]), -1)
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 0, 0.4)]), 0)
	# Le plus proche l'emporte.
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 0, -1.8), Vector3(0.3, 0, -1.0)]), 1)
	# Trop haut / trop bas (autre étage) : ignoré.
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 2.5, -1.0)]), -1)


func test_lunge_needs_aim() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	# 2,5 m droit devant : fente.
	var i := KnifeDB.pick_target(o, fwd, [Vector3(0, 0, -2.5)])
	assert_eq(i, 0, "zombie visé à 2,5 m : fente")
	assert_true(KnifeDB.needs_lunge(2.5))
	assert_false(KnifeDB.needs_lunge(1.0), "au contact : pas de fente")
	# 2,5 m mais à 35° du regard : pas de fente.
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(-1.45, 0, -2.05)]), -1, "hors du cône de fente")
	# Au-delà de la portée de fente.
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 0, -3.6)]), -1, "trop loin")
	# Côté serveur (fente interdite) : seule la portée au contact compte.
	assert_eq(KnifeDB.pick_target(o, fwd, [Vector3(0, 0, -2.5)], KnifeDB.RANGE, 0.0), -1)
	# Regard vers le haut : seule la direction horizontale compte.
	assert_eq(KnifeDB.pick_target(o, Vector3(0, 0.8, -0.6), [Vector3(0, 0, -2.5)]), 0)


func test_inventory_carries_knife() -> void:
	var pd := PlayerData.new(1)
	assert_eq(pd.knife, "knife")
	pd.knife = "autre"
	var copy := PlayerData.new(1)
	copy.apply_inventory(pd.inventory_dict())
	assert_eq(copy.knife, "autre", "le couteau voyage avec l'inventaire")


func test_models_defined() -> void:
	for id in KnifeDB.KNIVES:
		assert_true(WeaponModels.SPECS.has(KnifeDB.model(id)), "modèle %s" % id)
		assert_false(WeaponModels.spec(KnifeDB.model(id)).parts.is_empty())


## Batte de baseball : cibles d'un coup (Combat.swing_targets, pure) — la
## plus proche visée, puis les voisines dans l'arc, `count` au plus.
class _Pos:
	extends RefCounted
	var global_position := Vector3.ZERO

	func _init(p: Vector3) -> void:
		global_position = p


func test_bat_swing_targets() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	var a := _Pos.new(Vector3(0, 0, -1.5))
	var b := _Pos.new(Vector3(0.6, 0, -1.6))
	var behind := _Pos.new(Vector3(0, 0, 1.5))
	var far := _Pos.new(Vector3(0, 0, -4.0))
	var got := Combat.swing_targets(o, fwd, [far, b, behind, a], 2.2, 2)
	assert_eq(got.size(), 2, "deux zombies dans l'arc")
	assert_true(got.size() == 2 and got[0] == a and got[1] == b, "le plus proche d'abord, puis son voisin")
	assert_eq(Combat.swing_targets(o, fwd, [far, b, behind, a], 2.2, 1).size(), 1, "un seul si `targets` = 1")
	assert_true(Combat.swing_targets(o, fwd, [far, behind], 2.2, 2).is_empty(), "rien à portée devant")


## Coup de batte : pose miroir pour le revers, retour au repos en fin de coup.
func test_bat_swing_pose() -> void:
	var fore: Array = ViewModel.swing_pose(ViewModel.SWING_HIT, 1.0)
	var back: Array = ViewModel.swing_pose(ViewModel.SWING_HIT, -1.0)
	assert_near((fore[0] as Vector3).x, -(back[0] as Vector3).x, 0.0001, "revers : décalage miroir")
	assert_near((fore[1] as Vector3).y, -(back[1] as Vector3).y, 0.0001, "revers : lacet miroir")
	assert_true((fore[1] as Vector3).y > 0.3, "coup droit : balayage vers la gauche")
	var end: Array = ViewModel.swing_pose(1.0, 1.0)
	assert_eq(end[0], Vector3.ZERO)
	assert_eq(end[1], Vector3.ZERO)
