class_name ContractState
extends RefCounted
## État des contrats d'un profil (docs/HUB_PLAN.md §5.4), sérialisable :
## graine du tirage, compteur de rotations, propositions du scientifique,
## contrats actifs, remises comptées par contrat et contrats actifs expirés
## pas encore signalés au joueur. Données seulement : les règles sont dans
## ContractRules (le catalogue, HubData, n'est jamais lu ici).
##
## Format (section « contracts » du profil, ProfileStore version 2) :
##   {"seed": 918273, "rotation": 12,
##    "offers": [{"id": "dog_fur_coat", "since": 11}, …],
##    "active": [{"id": "dog_fangs_small", "accepted": 9}, …],
##    "done": {"first_sample": 1, "dog_fangs_small": 2},
##    "expired_unseen": ["lab_emergency"]}
## `since` / `accepted` : rotation à laquelle la proposition est arrivée / le
## contrat a été accepté. `expired_unseen` : contrats ACTIFS supprimés par leur
## date de fin, à signaler une fois au LABO (take_expired) puis oubliés.

## Plafond des listes lues depuis un fichier (garde-fou).
const MAX_ENTRIES := 64

## Graine du tirage (tirée à la création du profil) : le tirage d'une rotation
## utilise `seed + rotation` (recharger le jeu ne change rien).
var draw_seed := 0
## Nombre de remplissages du tableau faits depuis la création du profil.
var rotation := 0
## Propositions : [{id, since}], dans l'ordre d'arrivée.
var offers: Array[Dictionary] = []
## Contrats actifs : [{id, accepted}], dans l'ordre d'acceptation.
var active: Array[Dictionary] = []
## Remises : identifiant -> nombre (> 0).
var done: Dictionary = {}
## Contrats actifs expirés à signaler.
var expired_unseen: PackedStringArray = []


func _init() -> void:
	draw_seed = new_seed()


## Graine neuve, positive (générateur global : rejouable en autotest).
static func new_seed() -> int:
	return randi() & 0x7fffffff


func is_offered(id: String) -> bool:
	return _index(offers, id) >= 0


func is_active(id: String) -> bool:
	return _index(active, id) >= 0


func offered_ids() -> PackedStringArray:
	return _ids(offers)


func active_ids() -> PackedStringArray:
	return _ids(active)


func done_count(id: String) -> int:
	return int(done.get(id, 0))


## Nombre total de contrats remis (dossier de combat).
func done_total() -> int:
	var n := 0
	for k in done:
		n += int(done[k])
	return n


## Retire la proposition `id` ; faux si absente.
func remove_offer(id: String) -> bool:
	var i := _index(offers, id)
	if i < 0:
		return false
	offers.remove_at(i)
	return true


## Retire le contrat actif `id` ; faux si absent.
func remove_active(id: String) -> bool:
	var i := _index(active, id)
	if i < 0:
		return false
	active.remove_at(i)
	return true


## Contrats actifs expirés à signaler, puis oubliés (l'appelant enregistre
## le profil).
func take_expired() -> PackedStringArray:
	var out := expired_unseen.duplicate()
	expired_unseen.clear()
	return out


func to_dict() -> Dictionary:
	var os := []
	for o in offers:
		os.append({"id": o.id, "since": o.since})
	var acs := []
	for a in active:
		acs.append({"id": a.id, "accepted": a.accepted})
	return {"seed": draw_seed, "rotation": rotation, "offers": os, "active": acs,
		"done": done.duplicate(), "expired_unseen": Array(expired_unseen)}


## État lu depuis un fichier. Entrées illisibles écartées et comptées dans
## `dropped` (tableau d'un entier). Section absente : état neuf (graine
## tirée), sans compter d'entrée écartée.
static func from_dict(d: Variant, dropped := [0]) -> ContractState:
	var st := ContractState.new()
	if d == null:
		return st
	if not d is Dictionary:
		dropped[0] += 1
		return st
	var s := ProfileValues.to_int(d.get("seed"), -1, 0, 0x7fffffff)
	if s >= 0:
		st.draw_seed = s
	else:
		dropped[0] += 1
	st.rotation = ProfileValues.to_int(d.get("rotation"), 0, 0, PlayerProfile.VALUE_CAP)
	var seen := {}
	st.active = _entries(d.get("active"), "accepted", st.rotation, seen, dropped)
	st.offers = _entries(d.get("offers"), "since", st.rotation, seen, dropped)
	var dn: Variant = d.get("done", {})
	if dn is Dictionary:
		for k in dn:
			var n := ProfileValues.to_int(dn[k], -1, -1, PlayerProfile.VALUE_CAP)
			if (k is String or k is StringName) and ProfileValues.id_ok(String(k)) and n >= 0:
				if n > 0:
					st.done[String(k)] = n
			else:
				dropped[0] += 1
	else:
		dropped[0] += 1
	var ex: Variant = d.get("expired_unseen", [])
	if ex is Array:
		for v in ex:
			var id := ProfileValues.clean_id(v)
			if id != "" and not id in st.expired_unseen and st.expired_unseen.size() < MAX_ENTRIES:
				st.expired_unseen.append(id)
			else:
				dropped[0] += 1
	else:
		dropped[0] += 1
	return st


## Liste [{id, <key>}] lue depuis un fichier : identifiants valides, sans
## doublon (ni avec `seen` : un contrat actif n'est pas aussi proposé).
static func _entries(v: Variant, key: String, max_rot: int, seen: Dictionary, dropped: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v == null:
		return out
	if not v is Array:
		dropped[0] += 1
		return out
	for e in v:
		var id := ProfileValues.clean_id(e.get("id") if e is Dictionary else null)
		if id == "" or seen.has(id) or out.size() >= MAX_ENTRIES:
			dropped[0] += 1
			continue
		seen[id] = true
		out.append({"id": id, key: ProfileValues.to_int(e.get(key), max_rot, 0, max_rot)})
	return out


static func _index(list: Array[Dictionary], id: String) -> int:
	for i in list.size():
		if list[i].id == id:
			return i
	return -1


static func _ids(list: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in list:
		out.append(e.id)
	return out
