class_name MapHistory
extends RefCounted
## HISTORIQUE À BASE DE DIFFS, PAR AUTEUR (docs/MAP_COLLAB.md § 4). Remplace
## la pile de copies complètes de l'éditeur : chaque changement confirmé (dans
## l'ordre de l'hôte, donc le même sur tous les éditeurs) est inscrit avec ses
## opérations et leur inverse.
##   entrée = {cid, author, label, ops, inverse, time, active, prev, undone}
## Ctrl+Z d'une personne annule SA dernière entrée encore active ou celle de
## son Claude (auteur « <id>:claude »), la plus récente des deux ; Ctrl+Y
## rétablit la dernière annulée. Une annulation est un changement normal
## (diffusé) qui porte `undo: <cid>` (`redo: <cid>` pour rétablir).
## Conflit : un élément modifié par quelqu'un d'autre depuis l'entrée n'est
## pas touché. Pour le savoir, chaque clé (MapOps.op_key) retient le dernier
## changement qui l'a écrite (`_touch`) ; une entrée retient la valeur
## d'avant (`prev`), remise quand elle est annulée : annuler deux entrées
## successives sur le même élément marche donc dans l'ordre inverse.

## Entrées gardées au plus (les plus anciennes partent).
const MAX_ENTRIES := 1000

var entries: Array = []
var _by_cid: Dictionary = {}
## Clé -> cid du dernier changement (normal ou rétabli) qui l'a écrite.
var _touch: Dictionary = {}
## Cid -> auteur (aussi pour les entrées sorties de l'historique).
var _authors: Dictionary = {}
## Personne -> cids annulés, à rétablir (le dernier en fin).
var _redo: Dictionary = {}


## Personne d'un auteur : « 2:claude » -> « 2 ».
static func root_of(author: String) -> String:
	return author.get_slice(":", 0)


static func is_agent(author: String) -> bool:
	return author.ends_with(":claude")


func clear() -> void:
	entries.clear()
	_by_cid.clear()
	_touch.clear()
	_authors.clear()
	_redo.clear()


func entry(cid: String) -> Dictionary:
	return _by_cid.get(cid, {})


func author_of(cid: String) -> String:
	return String(_authors.get(cid, ""))


## Inscrit un changement confirmé : `change` = {cid, author, label, ops,
## undo?, redo?} ; `inverse` = MapOps.inverse(document avant, ops).
func record(change: Dictionary, inverse: Array) -> void:
	var cid := String(change.get("cid", ""))
	var author := String(change.get("author", ""))
	var ops: Array = change.get("ops", [])
	_authors[cid] = author
	var who := root_of(author)
	var target := String(change.get("undo", change.get("redo", "")))
	if change.has("undo") or change.has("redo"):
		var e: Dictionary = _by_cid.get(target, {})
		if e.is_empty():
			return
		var keys := MapOps.touched(ops)
		if change.has("undo"):
			e.active = false
			e.undone = keys
			for k in keys:
				if (e.prev as Dictionary).has(k):
					_touch[k] = e.prev[k]
			var stack: Array = _redo.get_or_add(who, [])
			stack.erase(target)
			stack.append(target)
		else:
			e.active = true
			e.undone = []
			for k in keys:
				_touch[k] = target
			(_redo.get(who, []) as Array).erase(target)
		return
	if ops.is_empty():
		return
	var prev := {}
	for k in MapOps.touched(ops):
		prev[k] = String(_touch.get(k, ""))
		_touch[k] = cid
	var e := {"cid": cid, "author": author, "label": String(change.get("label", "")), "ops": ops, "inverse": inverse,
		"time": int(Time.get_unix_time_from_system()), "active": true, "prev": prev, "undone": []}
	entries.append(e)
	_by_cid[cid] = e
	_redo[who] = []
	while entries.size() > MAX_ENTRIES:
		var old: Dictionary = entries.pop_front()
		_by_cid.erase(old.cid)
		for st in _redo.values():
			(st as Array).erase(old.cid)


## Dernière entrée active que `who` peut annuler (la sienne ou celle de son
## Claude ; `agent_only` : seulement celle de son Claude) ; {} sinon.
func last_active(who: String, agent_only := false) -> Dictionary:
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if not e.active:
			continue
		var a := String(e.author)
		if (agent_only and a == who + ":claude") or (not agent_only and root_of(a) == who):
			return e
	return {}


func can_undo(who: String, agent_only := false) -> bool:
	return not last_active(who, agent_only).is_empty()


func can_redo(who: String) -> bool:
	return not (_redo.get(who, []) as Array).is_empty()


## Nombre d'entrées encore annulables par `who`.
func undo_count(who: String) -> int:
	return entries.filter(func(e): return e.active and root_of(String(e.author)) == who).size()


## Changement qui annule la dernière entrée de `who` (voir last_active) :
## {undo: cid, label, ops, skipped, skipped_by: [auteurs]} ; {} si rien.
## Les éléments modifiés entre-temps par un autre sont laissés (skipped).
func make_undo(who: String, agent_only := false) -> Dictionary:
	var e := last_active(who, agent_only)
	if e.is_empty():
		return {}
	return _undo_of(e)


## Annulation de l'entrée `cid` (bouton « Annuler cette action » d'un
## historique, ou demande d'un invité vérifiée par l'hôte).
func make_undo_of(cid: String) -> Dictionary:
	var e: Dictionary = _by_cid.get(cid, {})
	return _undo_of(e) if not e.is_empty() and e.active else {}


func _undo_of(e: Dictionary) -> Dictionary:
	var keep := []
	var by := {}
	var skipped := 0
	for k in MapOps.touched(e.inverse):
		var t := String(_touch.get(k, ""))
		if t == String(e.cid):
			keep.append(k)
		else:
			skipped += 1
			by[author_of(t)] = true
	return {"undo": e.cid, "label": Lang.t("Annuler : %s", "Undo: %s") % e.label, "ops": MapOps.only(e.inverse, keep),
		"skipped": skipped, "skipped_by": by.keys()}


## Changement qui rétablit la dernière entrée annulée par `who` :
## {redo: cid, label, ops, skipped, skipped_by} ; {} si rien.
func make_redo(who: String) -> Dictionary:
	var stack: Array = _redo.get(who, [])
	if stack.is_empty():
		return {}
	return make_redo_of(String(stack.back()))


func make_redo_of(cid: String) -> Dictionary:
	var e: Dictionary = _by_cid.get(cid, {})
	if e.is_empty() or e.active:
		return {}
	var keep := []
	var by := {}
	var skipped := 0
	for k in e.undone:
		var t := String(_touch.get(k, ""))
		if t == String(e.prev.get(k, "")):
			keep.append(k)
		else:
			skipped += 1
			by[author_of(t)] = true
	return {"redo": e.cid, "label": Lang.t("Rétablir : %s", "Redo: %s") % e.label, "ops": MapOps.only(e.ops, keep),
		"skipped": skipped, "skipped_by": by.keys()}


## L'entrée `cid` peut-elle être annulée par la personne `who` ?
func owned_by(cid: String, who: String) -> bool:
	var e: Dictionary = _by_cid.get(cid, {})
	return not e.is_empty() and root_of(String(e.author)) == who


## Résumé léger envoyé à un invité qui arrive (welcome) : les dernières
## entrées pour l'affichage (sans opérations) et l'état des clés, pour que
## ses propres entrées suivantes aient le même « avant » que chez l'hôte.
func export_light(max_n := 100) -> Dictionary:
	var list := []
	for e in entries.slice(maxi(0, entries.size() - max_n)):
		list.append({"cid": e.cid, "author": e.author, "label": e.label, "time": e.time, "active": e.active})
	var authors := {}
	for k in _touch:
		authors[_touch[k]] = author_of(String(_touch[k]))
	return {"entries": list, "touch": _touch.duplicate(), "authors": authors}


## Reprend un résumé reçu (export_light). Les entrées reçues ne s'annulent
## pas d'ici (sans opérations) : elles ne servent qu'à l'affichage.
func import_light(d: Dictionary) -> void:
	clear()
	var t: Variant = d.get("touch", {})
	if t is Dictionary:
		for k in t:
			if k is String and t[k] is String:
				_touch[k] = t[k]
	var a: Variant = d.get("authors", {})
	if a is Dictionary:
		for k in a:
			if k is String and a[k] is String:
				_authors[k] = a[k]
	var l: Variant = d.get("entries", [])
	if l is Array:
		for x in (l as Array).slice(0, MAX_ENTRIES):
			if x is Dictionary and x.get("cid") is String:
				var e := {"cid": String(x.cid), "author": String(x.get("author", "")), "label": String(x.get("label", "")).left(200),
					"time": int(x.get("time", 0)) if (x.get("time") is float or x.get("time") is int) else 0,
					"active": false, "ops": [], "inverse": [], "prev": {}, "undone": [], "remote": true}
				entries.append(e)
				_authors[e.cid] = e.author
