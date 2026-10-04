extends TestCase
## Rendu de la collaboration dans l'éditeur (docs/MAP_COLLAB.md § 6) :
## aperçu en direct limité à 10 envois par seconde, lot de Claude animé mais
## appliqué d'un coup (carte, historique : un seul Ctrl+Z), animation
## terminée par un nouveau changement, clignotement des changements reçus,
## highlight, aperçus reçus validés, pastilles (étage, rôle), panneau
## Historique (contenu, annulation, conflit). Ports 17880+ (décalés par
## AUTOTEST_PORT_OFFSET).

const BASE := 17880
const TMP := "res://tests/_out/test_collab_view"


## Dossier des cartes et réglages (_editeur.cfg) propres au test : jamais ceux
## du joueur (sa disposition des vues changeait les fenêtres attendues).
func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	var cfg := EditorMap.maps_root().path_join("_editeur.cfg")
	if FileAccess.file_exists(cfg):
		DirAccess.remove_absolute(cfg)


func after_each() -> void:
	EditorMap.root_override = ""


func _port(i: int) -> int:
	return BASE + i + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	# Effets avancés à la main (advance) : pas par les images du test.
	ed.collab_view.set_process(false)
	return ed


func _end(ed: MapEditor) -> void:
	ed.collab.leave()
	ed.queue_free()
	await wait_frames(1)


func _room(x: float) -> Dictionary:
	return {"op": "add", "coll": "pieces", "el": {"etage": 0, "contour": [[x, 0], [x + 6, 0], [x + 6, 6], [x, 6]]}}


func _crate(id: String, x: float, k := 0) -> Array:
	return [{"op": "put", "coll": "objets", "el": {"id": id, "type": "caisse", "etage": k, "position": [x, 3.0]}}]


## Liaison agent sans écoute (même branchement que l'éditeur).
func _link(ed: MapEditor) -> MapAgentLink:
	var link := MapAgentLink.new()
	link.collab = ed.collab
	link.editor = ed
	ed.add_child(link)
	link.animate_requested.connect(ed._on_agent_animate)
	return link


func test_live_preview_is_throttled() -> void:
	var ed := await _editor()
	var room := ed.add_object({"contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}, 0)
	var rid := String(room.id)
	assert_false(ed.send_live(rid, 1000), "seul : rien à envoyer")
	assert_eq(ed.collab.host(_port(0), "Alice"), OK)
	var sent := 0
	for ms in [1000, 1030, 1060, 1099, 1100, 1150, 1199, 1200, 1250, 1300]:
		if ed.send_live(rid, ms):
			sent += 1
	assert_eq(sent, 4, "10 envois par seconde au plus (1000, 1100, 1200, 1300)")
	var p: Dictionary = ed.collab._presence_out
	assert_true(p.has("live") and String(p.live.coll) == "pieces" and String(p.live.el.id) == rid, "présence : aperçu de la pièce %s" % str(p.get("live", {})))
	# Le mouvement de la souris garde l'aperçu.
	ed.show_cursor(Vector2(5, 5))
	assert_true(ed.collab._presence_out.has("live"), "curseur : aperçu gardé")
	assert_true(ed.send_live(""), "relâché : aperçu retiré")
	assert_false(ed.collab._presence_out.has("live"), "présence sans aperçu")
	assert_false(ed.send_live(""), "déjà retiré")
	assert_true(ed.send_live(rid, 1310), "nouveau glissement : envoyé tout de suite")
	await _end(ed)


func test_received_live_preview_is_validated() -> void:
	var ed := await _editor()
	var v := ed.collab_view
	ed.collab.peers["2"] = {"id": "2", "name": "Bob", "color": "#4aa8e8", "kind": "human", "presence": {}}
	ed.collab.peers["2"].presence = {"cursor": [3.0, 4.0], "floor": 0, "selection": [], "tool": "",
		"live": {"coll": "objets", "el": {"id": "c1", "type": "caisse", "etage": 0, "position": [3.0, 4.0]}}}
	v.on_presence("2")
	assert_true(v.live.has("2"), "aperçu valide gardé")
	assert_eq(v.cursors["2"].pos, Vector2(3, 4), "premier curseur : placé tout de suite")
	ed.collab.peers["2"].presence = {"cursor": [9.0, 4.0], "floor": 0, "selection": [], "tool": "",
		"live": {"coll": "objets", "el": {"id": "c1", "type": "ovni", "etage": 0, "position": [3.0, 4.0]}}}
	v.on_presence("2")
	assert_false(v.live.has("2"), "aperçu illisible (type inconnu) : pas dessiné")
	assert_eq(v.cursors["2"].pos, Vector2(3, 4), "curseur pas encore arrivé")
	v.advance(0.05)
	var x := float(v.cursors["2"].pos.x)
	assert_true(x > 3.0 and x < 9.0, "curseur glissé en douceur (%.2f)" % x)
	for i in 60:
		v.advance(1.0 / 60.0)
	assert_true((v.cursors["2"].pos as Vector2).distance_to(Vector2(9, 4)) < 0.01, "curseur arrivé")
	await _end(ed)


func test_claude_batch_is_applied_at_once() -> void:
	var ed := await _editor()
	var v := ed.collab_view
	var link := _link(ed)
	var n0 := ed.collab.history.entries.size()
	var r := link.cmd_apply({"label": "trois salles", "ops": [_room(0), _room(10), _room(20)]})
	var ids: Array = (r.ids as Dictionary).values()
	assert_eq(ids.size(), 3, "trois pièces posées : %s" % str(r))
	for id in ids:
		assert_false(ed.doc.find(String(id)).is_empty(), "%s déjà sur la carte" % id)
	assert_eq(ed.collab.history.entries.size(), n0 + 1, "une seule entrée d'historique")
	assert_eq(v.hidden.size(), 2, "apparition : le premier montré, deux à venir")
	assert_true(String(v.bubble.text).contains("trois salles"), "bulle : %s" % v.bubble.get("text", ""))
	assert_true(ed.status.text.contains("trois salles"), "ligne d'état")
	v.advance(0.13)
	assert_eq(v.hidden.size(), 1, "un de plus après 0,12 s")
	v.advance(0.13)
	assert_true(v.hidden.is_empty() and v.anim.is_empty(), "tout apparu")
	assert_false(v.pulse.is_empty(), "contour pulsé encore là")
	v.advance(3.0)
	assert_true(v.bubble.is_empty() and v.pulse.is_empty(), "bulle effacée après ~3 s")
	# Un seul Ctrl+Z (celui de Claude, depuis l'éditeur) retire les trois.
	ed.undo()
	for id in ids:
		assert_true(ed.doc.find(String(id)).is_empty(), "%s retiré par un seul Ctrl+Z" % id)
	link.queue_free()
	await _end(ed)


func test_big_batch_lasts_at_most_1_5_s() -> void:
	var ed := await _editor()
	var v := ed.collab_view
	var link := _link(ed)
	var ops := []
	for i in 300:
		ops.append({"op": "add", "coll": "objets", "el": {"type": "caisse", "etage": 0, "position": [1.0 + (i % 30), 1.0 + floorf(i / 30.0)]}})
	link.cmd_apply({"label": "caisses", "ops": ops})
	assert_eq(v.hidden.size(), 299, "300 caisses à faire apparaître")
	var frames := 0
	var left := v.hidden.size()
	while not v.anim.is_empty() and frames < 200:
		v.advance(1.0 / 60.0)
		frames += 1
		assert_true(v.hidden.size() < left, "au moins un élément par image")
		left = v.hidden.size()
	assert_true(frames <= 91, "fini en 1,5 s au plus (%d images)" % frames)
	link.queue_free()
	await _end(ed)


func test_new_change_ends_the_animation_and_flashes() -> void:
	var ed := await _editor()
	var v := ed.collab_view
	ed.collab.peers["2"] = {"id": "2", "name": "Bob", "color": "#4aa8e8", "kind": "human", "presence": {}}
	var link := _link(ed)
	link.cmd_apply({"label": "salles", "ops": [_room(0), _room(10), _room(20)]})
	assert_false(v.anim.is_empty(), "animation en cours")
	# Changement de Bob pendant l'animation : elle se termine d'un coup.
	# (comme reçu de l'invité Bob par l'hôte)
	ed.collab._commit({"cid": "2-1", "author": "2", "label": "Caisse posée", "ops": _crate("c7", 3.0)}, false)
	assert_true(v.anim.is_empty() and v.hidden.is_empty(), "animation terminée tout de suite")
	assert_true(v.flashes.has("c7"), "élément de Bob qui clignote")
	assert_eq(v.flashes.c7.color, Color.html("#4aa8e8"), "dans la couleur de Bob")
	assert_eq(ed.status.text, "Bob : Caisse posée", "ligne d'état")
	v.advance(0.5)
	assert_true(v.flashes.has("c7"), "clignote encore à 0,5 s")
	v.advance(0.35)
	assert_false(v.flashes.has("c7"), "fini après ~0,8 s")
	# Mes propres changements ne clignotent pas.
	ed.collab.submit_ops(_crate("c8", 5.0), "Caisse posée")
	assert_false(v.flashes.has("c8"), "mon changement : pas de clignotement")
	link.queue_free()
	await _end(ed)


func test_highlight_brings_the_elements_into_view() -> void:
	var ed := await _editor()
	var v := ed.collab_view
	ed.add_floor()
	ed.set_floor(0)
	ed.collab.submit_ops(_crate("c1", 40.0, 1), "x")
	var link := _link(ed)
	link.cmd_highlight({"ids": ["c1", "absent"], "message": "regarde ici"})
	assert_eq(ed.floor_k, 1, "étage de l'élément affiché")
	assert_true(String(v.bubble.text).contains("regarde ici"), "bulle avec le message")
	assert_eq(v.pulse.ids, ["c1"], "contour pulsé sur l'élément existant")
	var px := ed.canvas.to_px(Vector2(40, 3))
	assert_true(Rect2(Vector2.ZERO, ed.canvas.size).grow(1.0).has_point(px), "élément dans la vue (%s)" % px)
	v.advance(3.5)
	assert_false(v.bubble.is_empty(), "encore là à 3,5 s")
	v.advance(0.6)
	assert_true(v.bubble.is_empty() and v.pulse.is_empty(), "effacé après ~4 s")
	link.queue_free()
	await _end(ed)


## Sélection demandée par Claude (highlight « select ») pendant un geste de
## l'utilisateur : le geste n'est pas annulé, la sélection reste, Claude est
## prévenu ; une fois le geste fini, la sélection passe.
func test_agent_select_waits_for_the_user_gesture() -> void:
	var ed := await _editor()
	ed.collab.submit_ops(_crate("c1", 4.0) + _crate("c2", 9.0), "x")
	var link := _link(ed)
	ed.select("c1")
	var orig := ed.doc.find("c1").duplicate(true)
	ed.canvas.drag = {"kind": "move", "start": Vector2(4, 3), "raw": Vector2(4, 3), "snap": ed.doc.snapshot(), "orig": orig, "moved": true}
	ed.doc.find("c1")["position"] = [6.0, 3.0]
	var out := link.cmd_highlight({"ids": ["c2"], "select": true})
	assert_true(out.has("busy"), "Claude prévenu du geste en cours (%s)" % str(out))
	assert_eq(out.get("selected"), ["c1"], "sélection inchangée")
	assert_eq(ed.selected, "c1", "toujours c1 choisi")
	assert_false(ed.canvas.drag.is_empty(), "geste de l'utilisateur gardé")
	assert_eq(ed.doc.find("c1").position, [6.0, 3.0], "carte du geste gardée (pas remise)")
	# Geste fini : la sélection de Claude passe.
	ed.canvas.drag = {}
	out = link.cmd_highlight({"ids": ["c2"], "select": true})
	assert_false(out.has("busy"), "plus de geste")
	assert_eq(ed.selected, "c2", "c2 choisi")
	# Reclic local pendant un geste : annulé comme avant (carte remise).
	ed.select("c1")
	ed.canvas.drag = {"kind": "move", "start": Vector2(6, 3), "raw": Vector2(6, 3), "snap": ed.doc.snapshot(), "orig": ed.doc.find("c1").duplicate(true), "moved": true}
	ed.doc.find("c1")["position"] = [7.0, 3.0]
	ed.select("c2")
	assert_true(ed.canvas.drag.is_empty(), "sélection locale : geste annulé")
	link.queue_free()
	await _end(ed)


func test_pills_show_role_and_floor() -> void:
	var ed := await _editor()
	var ui := ed.collab_ui
	assert_true(ui.pills.is_empty(), "seul : pas de pastille")
	assert_eq(ed.collab.host(_port(1), "Alice"), OK)
	ed.collab.peers["2"] = {"id": "2", "name": "Bob", "color": "#4aa8e8", "kind": "human", "presence": {"cursor": [1.0, 1.0], "floor": 1}}
	ed.collab.peers["1:claude"] = {"id": "1:claude", "name": "Claude", "color": MapCollab.AGENT_COLOR, "kind": "agent", "presence": {}}
	ui.refresh()
	assert_eq(ui.pills.size(), 3, "trois pastilles")
	for pill in ui.pills:
		assert_true(pill.get_parent() == ed.top_bar, "pastille dans la barre du haut (passe à la ligne)")
	var bob: Control = ui.pills.filter(func(p): return p.peer_id == "2")[0]
	assert_eq(String(bob.floor_text), "Étage 1" if not Lang.is_en() else "Floor 1", "Bob sur un autre étage")
	assert_true(bob.tooltip_text.contains(Lang.t("invité", "guest")), "rôle dans l'info-bulle : %s" % bob.tooltip_text)
	var claude: Control = ui.pills.filter(func(p): return p.peer_id == "1:claude")[0]
	assert_true(claude.agent and claude.tooltip_text.contains("Claude"), "pastille de Claude")
	var me: Control = ui.pills.filter(func(p): return p.peer_id == "1")[0]
	assert_true(me.tooltip_text.contains(Lang.t("hôte", "host")), "hôte : %s" % me.tooltip_text)
	ed.add_floor()
	ed.set_floor(1)
	ui.update_pills()
	assert_eq(String(bob.floor_text), "", "même étage : pas d'indicateur")
	await _end(ed)


func test_history_panel() -> void:
	var ed := await _editor()
	ed.collab.peers["2"] = {"id": "2", "name": "Bob", "color": "#4aa8e8", "kind": "human", "presence": {}}
	var link := _link(ed)
	ed.collab.submit_ops(_crate("c1", 2.0), "Première caisse")
	ed.collab.submit_ops(_crate("c2", 4.0), "Caisse de Bob", "2")
	link.cmd_apply({"label": "une salle", "ops": [_room(10)], "animate": false})
	ed.collab.submit_ops(_crate("c3", 6.0), "Troisième caisse")
	ed.panels.show_tab("history")
	await wait_frames(2)
	var hp := ed.panels.history
	var view := hp.entries_view()
	assert_eq(view.size(), 4, "quatre actions")
	assert_eq(String(view[0].label), "Troisième caisse", "la plus récente en haut")
	assert_eq(view.map(func(x): return x.can_undo), [true, true, false, true], "annulables : les miennes et celles de mon Claude")
	assert_eq(view[2].color, Color.html("#4aa8e8"), "couleur de Bob")
	assert_eq(view[1].color, CollabView.CLAUDE_COLOR, "couleur de Claude")
	assert_eq(hp._list.get_child_count(), 4, "quatre lignes")
	assert_eq(hp._list.get_child(0).find_children("Undo", "Button", true, false).size(), 1, "bouton sur ma ligne")
	assert_eq(hp._list.get_child(2).find_children("Undo", "Button", true, false).size(), 0, "pas de bouton sur la ligne de Bob")
	# Survol : éléments touchés surlignés.
	(hp._list.get_child(0) as Control).mouse_entered.emit()
	assert_eq(ed.collab_view.hover_ids, ["c3"], "survol : élément de l'action")
	# Annuler une action plus ancienne (pas la dernière) : seulement elle.
	var r := hp.undo(String(view[3].cid))
	assert_false(r.is_empty(), "première caisse annulée")
	assert_true(ed.doc.find("c1").is_empty() and not ed.doc.find("c3").is_empty(), "seulement la première caisse retirée")
	await wait_frames(2)
	view = hp.entries_view()
	assert_false(view[3].active, "entrée annulée")
	assert_true(hp._list.get_child(3).modulate.a < 0.9, "ligne grisée")
	# Conflit : Bob a modifié la troisième caisse entre-temps.
	ed.collab.submit_ops(_crate("c3", 8.0), "Caisse déplacée", "2")
	await wait_frames(2)
	view = hp.entries_view()
	r = hp.undo(String(view[1].cid))
	assert_true(ed.collab.conflict_text(r) != "", "conflit signalé")
	assert_true(hp._conflict.visible and hp._conflict.text.contains("Bob"), "message de conflit : %s" % hp._conflict.text)
	assert_false(ed.doc.find("c3").is_empty(), "la caisse de Bob reste")
	link.queue_free()
	await _end(ed)


func test_guest_batch_echo_keeps_the_animation() -> void:
	var h := MapCollab.new(EditorMap.blank("essai", "ESSAI", "TEST"))
	host.add_child(h)
	assert_eq(h.host(_port(2), "Alice"), OK)
	var ed := await _editor()
	ed.collab.join("127.0.0.1", _port(2), h.session_code, "Bob")
	var t0 := Time.get_ticks_msec()
	while (ed.collab.role != MapCollab.Role.GUEST or ed.collab._joining) and Time.get_ticks_msec() - t0 < 5000:
		await wait_frames(1)
	assert_eq(ed.collab.role, MapCollab.Role.GUEST, "invité accueilli")
	var link := _link(ed)
	link.cmd_apply({"label": "salles", "ops": [_room(0), _room(10), _room(20)]})
	assert_eq(ed.collab_view.hidden.size(), 2, "animation chez l'invité")
	t0 = Time.get_ticks_msec()
	while not ed.collab.pending.is_empty() and Time.get_ticks_msec() - t0 < 5000:
		await wait_frames(1)
	assert_true(ed.collab.pending.is_empty(), "écho de l'hôte reçu")
	assert_eq(ed.collab_view.hidden.size(), 2, "l'écho du lot ne termine pas son animation")
	assert_eq(h.doc.pieces.size(), 3, "lot entier chez l'hôte")
	link.queue_free()
	h.leave()
	h.queue_free()
	await _end(ed)


## Vues multiples (docs/EDITOR_VIEWS.md § 6.4) : la présence porte le plan de
## la vue survolée et la hauteur du curseur (gardés au tri, ignorés s'ils
## sont illisibles) ; les élévations dessinent les curseurs et sélections des
## autres à travers leur projection (sans erreur).
func test_presence_in_elevations() -> void:
	var p := MapCollab.clean_presence({"cursor": [3.0, 4.0], "floor": 0, "vue": "avant", "z": 2.5})
	assert_eq(String(p.vue), "avant")
	assert_near(float(p.z), 2.5, 0.001)
	p = MapCollab.clean_presence({"cursor": [3.0, 4.0], "floor": 0, "vue": "biais", "z": "haut"})
	assert_false(p.has("vue") or p.has("z"), "plan ou hauteur illisible : ignorés")
	var ed := await _editor()
	ed._reset(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	await wait_frames(2)
	assert_eq(ed.collab.host(_port(5), "Alice"), OK)
	var av: MapElevation = ed.views.panes[1].view
	# Mon curseur dans la vue Avant : la présence dit « avant » et la hauteur.
	ed.show_cursor_view(av, Vector2(9.0, -2.0))
	assert_eq(String(ed.collab._presence_out.get("vue", "")), "avant")
	assert_near(float(ed.collab._presence_out.get("z", -1.0)), 2.0, 0.01, "hauteur du curseur")
	ed.show_cursor(Vector2(5, 5))
	assert_false(ed.collab._presence_out.has("vue"), "vue Dessus : pas de clé « vue »")
	# Un autre participant dans la vue Avant, et sa sélection.
	ed.collab.peers["2"] = {"id": "2", "name": "Bob", "color": "#4aa8e8", "kind": "human",
		"presence": {"cursor": [9.0, 4.5], "floor": 0, "vue": "avant", "z": 2.0, "selection": ["p3"], "tool": ""}}
	ed.collab_view.on_presence("2")
	av.redraw_overlay()
	await wait_frames(2)
	assert_true(ed.collab_view.cursors.has("2"), "curseur de Bob suivi")
	assert_near(av.project(Vector3(9.0, 4.5, 2.0)).y, av.to_px(Vector2(0, -2.0)).y, 0.01, "à sa hauteur dans l'élévation")
	await _end(ed)
