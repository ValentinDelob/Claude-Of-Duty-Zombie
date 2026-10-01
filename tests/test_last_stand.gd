extends TestCase
## Arme du dernier recours (à terre) choisie comme dans BO1
## (last_stand_best_pistol / last_stand_pistol_swap).


func _w(id: String, pap := false, mag := -1, reserve := -1) -> Dictionary:
	var w := WeaponDB.new_instance(id, pap)
	if mag >= 0:
		w.mag = mag
	if reserve >= 0:
		w.reserve = reserve
	return w


func test_no_pistol_gets_fresh_m1911_with_two_mags() -> void:
	var w := DownedSystem.last_stand_weapon([_w("mp40"), _w("m16")])
	assert_eq(w.id, "m1911")
	assert_eq(w.mag, WeaponDB.stats("m1911").mag)
	assert_eq(w.reserve, WeaponDB.stats("m1911").mag * 2, "deux chargeurs de réserve")


func test_empty_m1911_is_topped_up() -> void:
	var w := DownedSystem.last_stand_weapon([_w("m1911", false, 0, 0), _w("mp40")])
	assert_eq(w.id, "m1911")
	assert_eq(w.reserve, WeaponDB.stats("m1911").mag * 2, "M1911 vide : de quoi tirer à terre")
	var full := DownedSystem.last_stand_weapon([_w("m1911", false, 8, 80)])
	assert_eq(full.reserve, 80, "rien n'est retiré")


func test_ray_gun_preferred_and_keeps_its_ammo() -> void:
	var w := DownedSystem.last_stand_weapon([_w("m1911"), _w("ray", false, 5, 20)])
	assert_eq(w.id, "ray", "le CLAUDE-RAY avant le M1911")
	assert_eq(w.mag, 5)
	assert_eq(w.reserve, 20, "ses munitions, sans bonus")


func test_better_pistol_preferred_with_two_extra_mags() -> void:
	var w := DownedSystem.last_stand_weapon([_w("m1911"), _w("python", false, 6, 10)])
	assert_eq(w.id, "python")
	assert_eq(w.reserve, 10 + WeaponDB.stats("python").mag * 2)
	var pap := DownedSystem.last_stand_weapon([_w("m1911", true), _w("cz75")])
	assert_true(pap.id == "m1911" and pap.pap, "M1911 amélioré avant un CZ75 normal (liste de BO1)")


## Soak KINO : CZ75 à réserve pleine (105), mis à terre -> 135 / 105, et la
## réserve trop pleine revenait avec l'arme après la réanimation.
func test_extra_mags_never_exceed_max_reserve() -> void:
	var cz_max := int(WeaponDB.stats("cz75").reserve)
	var w := DownedSystem.last_stand_weapon([_w("cz75", false, 15, cz_max)])
	assert_eq(w.reserve, cz_max, "réserve pleine : reste au maximum")
	var near := DownedSystem.last_stand_weapon([_w("cz75", false, 15, cz_max - 10)])
	assert_eq(near.reserve, cz_max, "presque pleine : complétée jusqu'au maximum seulement")
	var pap_max := int(WeaponDB.stats("python", true).reserve)
	var p := DownedSystem.last_stand_weapon([_w("python", true, 6, pap_max)])
	assert_eq(p.reserve, pap_max, "arme améliorée : plafond de sa version améliorée")


func test_input_not_modified() -> void:
	var saved := [_w("python", false, 6, 10)]
	var _w2 := DownedSystem.last_stand_weapon(saved)
	assert_eq(saved[0].reserve, 10, "copie : les armes mises de côté ne changent pas")
