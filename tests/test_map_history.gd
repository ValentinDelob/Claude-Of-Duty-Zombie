extends TestCase
## Historique par auteur de l'éditeur collaboratif (MapHistory,
## docs/MAP_COLLAB.md § 4) : annuler / rétablir le sien et celui de son
## Claude, conflits avec les changements des autres.


var doc: EditorMap
var h: MapHistory
var n := 0


func before_each() -> void:
	doc = EditorMap.blank()
	h = MapHistory.new()
	n = 0


## Applique et inscrit un changement de `author` (comme l'hôte).
func _do(author: String, ops: Array, extra := {}) -> Dictionary:
	n += 1
	var change := {"cid": "c%d" % n, "author": author, "label": "action %d" % n, "ops": ops}
	change.merge(extra)
	var inv := MapOps.inverse(doc, ops)
	MapOps.apply(doc, ops)
	h.record(change, inv)
	return change


func _put(id: String, v: int) -> Array:
	return [{"op": "put", "coll": "objets", "el": {"id": id, "type": "caisse", "etage": 0, "position": [v, v]}}]


func _val(id: String) -> int:
	var e := doc.find(id)
	return -1 if e.is_empty() else int(e.position[0])


func _undo(who: String, agent_only := false) -> Dictionary:
	var u := h.make_undo(who, agent_only)
	if not u.is_empty():
		_do(who + (":claude" if agent_only else ""), u.ops, {"undo": u.undo})
	return u


func _redo(who: String) -> Dictionary:
	var r := h.make_redo(who)
	if not r.is_empty():
		_do(who, r.ops, {"redo": r.redo})
	return r


func test_solo_undo_redo_in_order() -> void:
	_do("1", _put("a", 1))
	_do("1", _put("a", 2))
	_do("1", _put("b", 5))
	_undo("1")
	assert_eq(_val("b"), -1, "annuler : b retiré")
	_undo("1")
	assert_eq(_val("a"), 1, "annuler : a revient à 1")
	_undo("1")
	assert_eq(_val("a"), -1, "annuler : a retiré")
	assert_true(_undo("1").is_empty(), "plus rien à annuler")
	_redo("1")
	_redo("1")
	assert_eq(_val("a"), 2, "rétablir x2 : a à 2")
	_do("1", _put("c", 3))
	assert_true(h.make_redo("1").is_empty(), "nouvelle action : plus rien à rétablir")
	assert_eq(h.undo_count("1"), 3, "trois entrées annulables")


func test_each_author_undoes_only_his_own() -> void:
	_do("1", _put("a", 1))
	_do("2", _put("b", 2))
	_undo("1")
	assert_eq(_val("a"), -1, "1 annule la sienne")
	assert_eq(_val("b"), 2, "celle de 2 reste")
	assert_true(_undo("1").is_empty(), "1 n'annule jamais celle de 2")
	_undo("2")
	assert_eq(_val("b"), -1, "2 annule la sienne")


func test_person_undoes_his_claude_too() -> void:
	_do("1", _put("a", 1))
	_do("1:claude", _put("k", 7) + _put("q", 8))
	_do("2:claude", _put("z", 9))
	assert_true(h.make_undo("1", true).undo == "c2", "seulement Claude : son dernier lot")
	_undo("1")
	assert_eq([_val("k"), _val("q")], [-1, -1], "Ctrl+Z de 1 : le lot de son Claude entier")
	assert_eq(_val("z"), 9, "le Claude de 2 n'est pas touché")
	_undo("1")
	assert_eq(_val("a"), -1, "puis sa propre action")
	assert_true(h.make_undo("1", true).is_empty(), "plus rien de son Claude")


func test_conflict_leaves_elements_changed_by_others() -> void:
	_do("1", _put("a", 1) + _put("b", 1))
	_do("2", _put("a", 5))
	var u := _undo("1")
	assert_eq(int(u.skipped), 1, "un élément modifié entre-temps")
	assert_eq(u.skipped_by, ["2"], "par 2")
	assert_eq(_val("a"), 5, "a gardé (modifié par 2)")
	assert_eq(_val("b"), -1, "b annulé")
	# 2 annule son changement : a revient à la valeur de 1, que 1 peut rétablir.
	_undo("2")
	assert_eq(_val("a"), 1, "a revient à la valeur de 1")
	var r := _redo("1")
	assert_eq(int(r.skipped), 0, "rétablir sans conflit")
	assert_eq(_val("b"), 1, "b rétabli")


func test_light_export_keeps_key_state() -> void:
	_do("1", _put("a", 1))
	_do("2", _put("a", 2))
	var g := MapHistory.new()
	g.import_light(JSON.parse_string(JSON.stringify(h.export_light())))
	assert_eq(g.entries.size(), 2, "entrées pour l'affichage")
	assert_eq(g.author_of("c2"), "2", "auteurs connus")
	assert_true(g.make_undo("2").is_empty(), "entrées reçues : pas annulables d'ici")
