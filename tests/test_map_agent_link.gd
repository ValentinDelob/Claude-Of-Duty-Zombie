extends TestCase
## Liaison agent de l'éditeur (MapAgentLink, docs/MAP_COLLAB.md § 5.2) : les
## commandes que le serveur MCP du jeu (McpServer, docs/MCP.md) lui passe par
## handle(cmd, args). get_map, apply avec ids provisoires « $1 », undo,
## validate, capture refusée sans affichage, commande inconnue ; inscription
## auprès du serveur et événements poussés. Le transport HTTP est vérifié par
## tests/test_mcp_server.gd.


func test_agent_link_commands() -> void:
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var srv := MapAgentLink.server()
	assert_true(srv != null and srv.editor() == link, "liaison inscrite auprès du serveur MCP du jeu")
	var r: Dictionary = await link.handle("hello", {})
	assert_eq(String(r.role), "solo")
	assert_eq(String(r.you), "1:claude")
	r = await link.handle("get_map", {})
	assert_true(r.has("pieces"), "get_map : carte complète")
	# apply : pièce + porte + arme avec ids provisoires, et un élément refusé.
	var n0: int = srv.events.size()
	r = await link.handle("apply", {"label": "deux pièces", "ops": [
		{"op": "add", "coll": "pieces", "el": {"id": "$1", "nom": "Hall", "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}},
		{"op": "add", "coll": "pieces", "el": {"id": "$2", "contour": [[10, 2], [16, 2], [16, 8], [10, 8]]}},
		{"op": "add", "coll": "ouvertures", "el": {"id": "$3", "type": "porte", "position": [10, 5], "largeur": 2}},
		{"op": "add", "coll": "objets", "el": {"id": "$4", "type": "fusee", "position": [4, 4]}},
	]})
	assert_false(r.has("error"), "apply accepté : %s" % str(r))
	assert_eq(r.get("ids", {}).get("$1", ""), "p1", "$1 -> p1")
	assert_true((r.get("invalid", {}) as Dictionary).has(String(r.ids.get("$4", ""))), "type inconnu listé dans invalid")
	assert_eq(m.pieces.size(), 2, "deux pièces posées")
	assert_eq(m.zones.size(), 2, "une zone par pièce")
	assert_eq(collab.history.entries.size(), 1, "un lot = une entrée d'historique")
	assert_eq(String(collab.history.entries[0].author), "1:claude", "auteur : le Claude de l'éditeur")
	assert_true(srv.events.size() > n0 and String(srv.events[-1].event) == "change", "événement « change » gardé par le serveur")
	r = await link.handle("validate", {})
	assert_true(r.has("text"), "validate : rapport")
	r = await link.handle("screenshot", {"floor": 0})
	assert_true(r.has("error"), "capture refusée sans affichage")
	r = await link.handle("catalog", {})
	assert_true((r.kinds as Dictionary).has("porte"), "catalogue")
	assert_true(r.get("prefabs_carte") is Array, "catalogue : prefabs de la carte (MapAgentPrefabs)")
	# Commandes des prefabs déléguées à MapAgentPrefabs (ici sans éditeur : erreur expliquée).
	r = await link.handle("prefab_list", {})
	assert_true(r.has("error"), "prefab_list sans éditeur : refusé")
	assert_true(String(r.get("error", "")).contains("éditeur") or String(r.get("error", "")).contains("editor"), "message : %s" % r.get("error", ""))
	# undo : le lot de Claude entier.
	r = await link.handle("undo", {})
	assert_false(r.has("error"), "undo accepté : %s" % str(r))
	assert_true(m.pieces.is_empty() and m.ouvertures.is_empty() and m.zones.is_empty(), "lot annulé d'un coup")
	r = await link.handle("undo", {})
	assert_true(r.has("error"), "plus rien à annuler")
	r = await link.handle("frobnicate", {})
	assert_true(r.size() == 1 and String(r.error).contains("frobnicate"), "commande inconnue")
	link.notify_selection(["p9"])
	assert_eq(srv.events[-1].ids, ["p9"], "sélection poussée")
	link.queue_free()
	await host.get_tree().process_frame
	assert_true(srv.editor() == null, "liaison retirée à la sortie de l'éditeur")
	collab.queue_free()


## Vues multiples (docs/EDITOR_VIEWS.md § 6.4) : get_elements rend les
## hauteurs (boîte, altitude de pose, type de glissement) ; une vue inconnue
## est refusée pour la capture.
func test_elements_with_heights_and_views() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.objets.append({"id": "fx1", "type": "effet", "effet": "torche", "etage": 0, "position": [9.5, 4.5], "mur": "n", "hauteur": 2.4})
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var r := link.cmd_get_elements({"ids": ["p3", "p5", "fx1", "o5", "zz"]})
	assert_near(float(r.elements.p3.z_max), 6.8, 0.001, "entrepôt en double hauteur : jusqu'à 6,80 m")
	assert_near(float(r.elements.p5.z_monde), 3.5, 0.001, "passerelle : sol de l'étage 1")
	assert_eq(String(r.elements.p5.glissement_vertical), "niveau")
	assert_near(float(r.elements.fx1.hauteur_pose), 2.4, 0.001, "torche : hauteur de pose")
	assert_near(float(r.elements.fx1.z_monde), 2.4, 0.001)
	assert_eq(String(r.elements.o5.glissement_vertical), "fixe")
	assert_near(float(r.elements.o5.z_min), MapValidator.SILL, 0.001, "fenêtre : de l'allège")
	assert_eq(r.absents, ["zz"])
	var s: Dictionary = await link.cmd_screenshot({"view": "biais"})
	assert_true(s.has("error") and String(s.error).contains("biais"), "vue inconnue refusée : %s" % s)
	link.queue_free()
	collab.queue_free()


## Format 14 (docs/EDITOR_SCALE_ROTATE.md § 6) : dimensions et possibilités
## d'échelle des éléments, « put » d'une échelle (arrondie au pas), refus qui
## nomme l'objet de jeu d'un prefab bloqué, catalogue.
func test_scale_through_the_agent_link() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.objets.append({"id": "d90", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [12.0, 7.5]})
	m.prefabs["coin_pap"] = preload("res://tests/test_map_scale.gd").PAP_DEF.duplicate(true)
	m.objets.append({"id": "d93", "type": "prefab", "prefab": "map:coin_pap", "etage": 0, "position": [5.0, 26.0]})
	m.activate_prefabs()
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var r := link.cmd_get_elements({"ids": ["d90", "d93", "b1"]})
	assert_eq(r.elements.d90.dimensions, [2.5, 2.0, 1.5], "dimensions finales")
	assert_true(bool(r.elements.d90.echelle_possible) and bool(r.elements.d90.inclinaison_possible), "décor : échelle et inclinaison")
	assert_false(bool(r.elements.d93.echelle_possible), "prefab avec un Pack-a-Punch : bloqué")
	assert_true(String(r.elements.d93.get("raison", "")).contains("Pack-a-Punch"), "raison qui nomme l'objet : %s" % r.elements.d93.get("raison", ""))
	var el: Dictionary = m.find("d90").duplicate(true)
	el["echelle"] = [1.234, 1.234, 1.234]
	var a := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": el}], "label": "Pile agrandie", "animate": false})
	assert_false(a.has("error"), str(a))
	assert_true(MapScale.scale_of(collab.doc.find("d90")).is_equal_approx(Vector3.ONE * 1.23), "arrondie au pas de 0,01 (%s)" % str(collab.doc.find("d90").get("echelle")))
	var k: Dictionary = m.find("d93").duplicate(true)
	k["echelle"] = [2, 2, 2]
	var b := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": k}], "label": "Coin agrandi", "animate": false})
	assert_true((b.invalid as Dictionary).has("d93") and String(b.invalid.d93).contains("Pack-a-Punch"), "refus nommé : %s" % str(b.invalid))
	assert_false(collab.doc.find("d93").has("echelle"), "prefab bloqué : inchangé")
	var cat := MapAgentLink.catalog()
	var pap: Array = (cat.items as Array).filter(func(it): return String(it.id) == "pap")
	assert_true(not pap.is_empty() and pap[0].get("echelle", true) == false, "catalogue : le Pack-a-Punch garde sa taille")
	assert_true(bool(cat.prefabs.poutre.inclinaison) and not bool(cat.prefabs.torche_murale.inclinaison), "catalogue : inclinaison au sol seulement")
	link.queue_free()
	collab.queue_free()


## Revue : Claude (MCP) passe par les mêmes règles que l'éditeur (plafond,
## décor posé dessus).
func test_mcp_scale_follows_editor_rules() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.objets.append({"id": "d80", "type": "prefab", "prefab": "etagere", "etage": 0, "position": [20.0, 9.0]})
	m.objets.append({"id": "d81", "type": "prefab", "prefab": "sacs_sable", "etage": 0, "position": [19.0, 14.5]})
	m.objets.append({"id": "d82", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [19.0, 14.5], "z": 0.9})
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var tall: Dictionary = m.find("d80").duplicate(true)
	tall["echelle"] = [4, 4, 4]
	var a := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": tall}], "label": "Étagère géante", "animate": false})
	assert_true((a.invalid as Dictionary).has("d80"), "étagère × 4 sous le plafond : refusée (%s)" % str(a))
	assert_false(collab.doc.find("d80").has("echelle"), "carte inchangée")
	var tilt: Dictionary = m.find("d81").duplicate(true)
	tilt["incl"] = [0, 20]
	var b := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": tilt}], "label": "Sacs inclinés", "animate": false})
	assert_true((b.invalid as Dictionary).has("d81") and String(b.invalid.d81).contains("posé dessus"), "porteur incliné : refusé (%s)" % str(b))
	link.queue_free()
	collab.queue_free()
