extends AutotestScenario
## @rendu : captures des effets de l'éditeur (revue humaine, format 10).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec sh tools/scenario.sh map_effects_look.
## Une grande salle (44 × 12 m) : une colonne par sous-onglet (flammes,
## fumées, étincelles, électricité, eau, ambiance), effets au sol, au mur nord
## et au plafond ; partie solo, vue de chaque colonne à hauteur d'yeux.

const MAP_ID := "effets_revue"
const COL := 7.3
const OFF := MapGeom.WORLD_OFFSET
const SW := preload("res://tests/autotest/smallest_window.gd")

var H := AutotestHelpers


## Carte de revue : effets rangés par sous-onglet.
static func review_map() -> EditorMap:
	var doc := EditorMap.blank(MAP_ID, "EFFETS", "EFFECTS")
	var z := String(doc.add_zone("Salle", "Hall").id)
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z, "contour": [[0, 0], [44, 0], [44, 12], [0, 12]]})
	doc.depart = z
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "etage": 0, "position": [22.25, 12.0]})
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [22.0, 10.5]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [30.0, 12.0], "mur": "s", "depart": true})
	var place := {
		"flammes": [["petit_feu", 1.6, 4.0], ["brasier", 4.6, 4.5], ["baril_feu", 1.6, 7.5], ["incendie", 4.6, 8.4], ["torche", 3.2, 0.0]],
		"fumees": [["fumee_legere", 1.5, 4.0], ["fumee_noire", 5.0, 4.5], ["brouillard", 3.4, 8.5], ["vapeur", 3.0, 0.0]],
		"etincelles": [["pluie_etincelles", 1.6, 5.0], ["soudure", 3.0, 0.0], ["court_circuit", 5.4, 0.0]],
		"electricite": [["arc", 2.0, 4.5], ["tesla", 5.0, 5.0], ["cable_nu", 3.6, 8.0]],
		"eau": [["goutte", 1.6, 5.0], ["fuite", 4.0, 0.0], ["flaque", 4.8, 6.5]],
		"ambiance": [["poussiere", 3.6, 4.0], ["braises", 1.8, 7.5], ["cendres", 5.0, 7.5], ["feux_follets", 3.6, 6.0]],
	}
	var subs := MapCatalog.EFFECT_SUBS
	for i in subs.size():
		var x0 := 0.4 + i * COL
		for e in place.get(String(subs[i][0]), []):
			var it := MapCatalog.item("effet:" + String(e[0]))
			var o: Dictionary = it.make.duplicate(true)
			o["id"] = doc.new_id("fx")
			o["etage"] = 0
			o["position"] = [snappedf(x0 + float(e[1]), 0.25), float(e[2])]
			if it.tool == "wall_item":
				o["mur"] = "n"
			doc.objets.append(o)
			if String(e[0]) == "baril_feu":
				doc.objets.append({"id": doc.new_id("x"), "type": "baril", "etage": 0, "position": o.position})
	return doc


func run() -> void:
	timeout_sec = 240
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var dst := EditorMap.map_dir(MAP_ID)
	at.check(dst != "" and dst.begins_with(ProjectSettings.globalize_path("res://tests/_out")), "dossier de test (%s)" % dst)
	if dst == "":
		return
	DirAccess.make_dir_recursive_absolute(dst)
	at.check(review_map().save_dir(dst) == OK, "carte de revue enregistrée")
	var p := await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var n := tree().root.find_children("*", "MapEffect", true, false).size()
	at.check(n == MapCatalog.EFFECTS.size(), "%d effets construits en jeu (%d au catalogue)" % [n, MapCatalog.EFFECTS.size()])
	await seconds(4.0)  # titre de la carte effacé, feux bien pris
	var cam := Camera3D.new()
	cam.fov = 70.0
	game.add_child(cam)
	cam.make_current()
	game.hud.visible = false
	var subs := MapCatalog.EFFECT_SUBS
	for i in subs.size():
		var cx := OFF + 0.4 + i * COL + 3.6
		p.teleport_to(Vector3(cx, 0.1, OFF + 11.2))
		await seconds(0.3)
		cam.look_at_from_position(Vector3(cx, 1.7, OFF + 11.0), Vector3(cx, 1.0, OFF + 3.5))
		await seconds(1.2)
		await at.screenshot(String(subs[i][0]))
		# Mur nord (effets muraux, plafond) vu de plus près.
		cam.look_at_from_position(Vector3(cx, 1.5, OFF + 4.2), Vector3(cx, 1.5, OFF + 0.0))
		await seconds(1.0)
		await at.screenshot(String(subs[i][0]) + "_mur")
	# Gros plan : feu de camp et étincelles.
	cam.look_at_from_position(Vector3(OFF + 5.0, 1.3, OFF + 7.0), Vector3(OFF + 5.0, 0.6, OFF + 4.5))
	await seconds(0.8)
	await at.screenshot("brasier_pres")
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	SW.remove_dir(dst)
