class_name HubContractsView
extends RefCounted
## Lecture seule des contrats du profil pour le LABO (lot B), en attendant les
## panneaux CONTRATS du lot D. Tolérante : les contrats (lot A : section
## `contracts` du profil, version 2, docs/HUB_PLAN.md §5.4) peuvent ne pas
## encore exister ; on lit alors « aucun suivi » (`available()` faux) et le
## LABO affiche un emplacement.
##
## Titres et demandes : fichier de données assets/data/hub/contracts.json, lu
## ici en lecture seule (champs `title`, `samples`, `ends`) ; le lot D pourra
## passer par HubData (chargement validé du lot A) sans changer l'interface.

const DATA := "res://assets/data/hub/contracts.json"

static var _catalog: Dictionary = {}


## Le profil suit-il des contrats (lot A en place) ?
static func available(pr: PlayerProfile) -> bool:
	return _state(pr) != null


## Contrats actifs : [{id, title, samples: {sorte: quantité}, ends: "AAAA-MM-JJ"
## ou "", ready: bool}], dans l'ordre du profil.
static func active(pr: PlayerProfile) -> Array:
	var out := []
	var st: Variant = _state(pr)
	if st == null:
		return out
	var list: Variant = _field(st, "active")
	if not list is Array:
		return out
	var cat := catalog()
	for e in list:
		var id := ""
		if e is Dictionary:
			id = String(e.get("id", ""))
		elif e is String or e is StringName:
			id = String(e)
		elif e is Object and "id" in e:
			id = String(e.get("id"))
		if id == "" or not cat.has(id):
			continue
		var c: Dictionary = cat[id]
		var samples: Dictionary = c.get("samples", {})
		out.append({"id": id, "title": c.get("title", id), "samples": samples, "ends": c.get("ends", ""),
			"ready": pr.has_samples(samples)})
	return out


## Nombre de contrats remplis (section `done`) ; -1 : inconnu.
static func done_count(pr: PlayerProfile) -> int:
	var st: Variant = _state(pr)
	if st == null:
		return -1
	var d: Variant = _field(st, "done")
	if not d is Dictionary:
		return 0
	var n := 0
	for k in d:
		var v: Variant = d[k]
		if v is int or v is float:
			n += maxi(int(v), 0)
	return n


## Contrats actifs prêts à remettre.
static func ready_count(pr: PlayerProfile) -> int:
	var n := 0
	for c in active(pr):
		if c.ready:
			n += 1
	return n


## Jours entiers restants après aujourd'hui (fin le jour `ends` à 24 h UTC ;
## dernier jour : 0, maquette « ENCORE 12 J » le 18 pour le 30) ; -1 : pas de
## date.
static func days_left(ends: String, now_unix := -1.0) -> int:
	if ends == "":
		return -1
	var t := Time.get_unix_time_from_datetime_string(ends + "T00:00:00")
	if t <= 0:
		return -1
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	return maxi(floori((t + 86400.0 - now) / 86400.0), 0)


## Catalogue {id: {title, samples, ends}} (lu une fois).
static func catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		return _catalog
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary or not data.get("contracts") is Array:
		return _catalog
	for c in data.contracts:
		if not c is Dictionary or not c.get("id") is String:
			continue
		var t: Variant = c.get("title", {})
		var title: String = c.id
		if t is Dictionary:
			title = String(t.get("en" if Lang.is_en() else "fr", c.id))
		var s := {}
		var raw: Variant = c.get("samples", {})
		if raw is Dictionary:
			for k in raw:
				if raw[k] is int or raw[k] is float:
					s[String(k)] = clampi(int(raw[k]), 1, 999)
		var ends: Variant = c.get("ends", "")
		_catalog[c.id] = {"title": title, "samples": s, "ends": ends if ends is String else ""}
	return _catalog


## Oublie le catalogue (changement de langue, tests).
static func clear_cache() -> void:
	_catalog.clear()


static func _state(pr: PlayerProfile) -> Variant:
	if pr == null or not "contracts" in pr:
		return null
	var st: Variant = pr.get("contracts")
	if st is Dictionary or st is Object:
		return st
	return null


static func _field(st: Variant, key: String) -> Variant:
	if st is Dictionary:
		return st.get(key)
	if st is Object and key in st:
		return st.get(key)
	return null
