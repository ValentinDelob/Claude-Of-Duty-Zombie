class_name HubContractsView
extends RefCounted
## Lecture des contrats du profil pour l'interface du hub (LABO, CONTRATS,
## pastille de l'onglet) : contrats actifs et propositions enrichis de leur
## fiche (HubData, chargement validé du lot A), prêts ou non, jours restants,
## propositions nouvelles. Plus l'opération faite à l'OUVERTURE du hub
## (open_hub : purge, premier remplissage, contrats expirés à signaler).
##
## Jour et catalogue : HubData.today() et HubData.default(), remplaçables par
## `day_override` / `data_override` (tests, scénarios : la date de la
## maquette, 18 novembre 2026).

## Jour UTC imposé (-1 : aujourd'hui).
static var day_override := -1
## Catalogue imposé (null : fichiers livrés).
static var data_override: HubData = null


## Catalogue des contrats et des échanges.
static func data() -> HubData:
	return data_override if data_override != null else HubData.default()


## Jour UTC courant (jours depuis le 1/1/1970).
static func today() -> int:
	return day_override if day_override >= 0 else HubData.today()


## Le profil suit-il des contrats ? (Toujours, depuis le lot A ; gardé pour
## les appelants du lot B.)
static func available(pr: PlayerProfile) -> bool:
	return pr != null and pr.contracts != null


## Contrats actifs, dans l'ordre d'acceptation : [{id, title, text, samples,
## ends (jour UTC, -1 : sans date), days (jours pleins restants après
## aujourd'hui, -1 : sans date), ready, contract (fiche HubData)}]. Les
## contrats inconnus du catalogue sont ignorés (la purge les retire).
static func active(pr: PlayerProfile, day := -1) -> Array:
	var out := []
	if not available(pr):
		return out
	var d := data()
	var today_ := day if day >= 0 else today()
	for id in pr.contracts.active_ids():
		var c := d.contract(id)
		if c.is_empty():
			continue
		# Fin effective : date du catalogue ou durée de vie du contrat
		# temporaire (ContractRules.deadline).
		var eff := ContractRules.effective(c, pr.contracts.active_entry(id))
		out.append({"id": id, "title": HubData.text_of(c.title), "text": HubData.text_of(c.text), "samples": c.samples,
			"ends": int(eff.ends), "days": days_after_today(eff, today_),
			"ready": pr.has_samples(c.samples) and not ContractRules.is_expired(eff, today_), "contract": c})
	return out


## Propositions du scientifique, dans l'ordre d'arrivée : [{id, title,
## contract, since, new, days}]. `new` : arrivée au dernier remplissage du
## tableau (« nouvelle proposition depuis la dernière partie ») ; `days` :
## jours pleins restants après aujourd'hui (-1 : sans fin).
static func offers(pr: PlayerProfile, day := -1) -> Array:
	var out := []
	if not available(pr):
		return out
	var d := data()
	var today_ := day if day >= 0 else today()
	for o in pr.contracts.offers:
		var c := d.contract(String(o.id))
		if c.is_empty():
			continue
		out.append({"id": String(o.id), "title": HubData.text_of(c.title), "contract": c, "since": int(o.since),
			"new": is_new_offer(pr, o), "days": days_after_today(ContractRules.effective(c, o), today_)})
	return out


## Proposition arrivée au dernier remplissage du tableau ?
static func is_new_offer(pr: PlayerProfile, o: Dictionary) -> bool:
	return pr.contracts.rotation > 0 and int(o.get("since", -1)) >= pr.contracts.rotation


## Nombre de propositions nouvelles (LABO : « 1 nouvelle proposition »).
static func new_offer_count(pr: PlayerProfile) -> int:
	var n := 0
	for o in offers(pr):
		if o.new:
			n += 1
	return n


## Nombre de contrats remplis (dossier de combat, PROFIL du LABO).
static func done_count(pr: PlayerProfile) -> int:
	return pr.contracts.done_total() if available(pr) else -1


## Contrats actifs prêts à remettre (pastille de l'onglet CONTRATS).
static func ready_count(pr: PlayerProfile) -> int:
	var n := 0
	for c in active(pr):
		if c.ready:
			n += 1
	return n


## Jours pleins restants APRÈS aujourd'hui pour un contrat daté (maquette :
## « ENCORE 12 J » le 18 pour une fin le 30 ; dernier jour : 0) ; -1 : sans
## date de fin.
static func days_after_today(c: Dictionary, day: int) -> int:
	var n := ContractRules.days_left(c, day)
	return maxi(n - 1, 0) if n >= 0 else -1


## Même calcul depuis une date « AAAA-MM-JJ » et une heure Unix (tests).
static func days_left(ends: String, now_unix := -1.0) -> int:
	var e := HubData.parse_day(ends)
	if e < 0:
		return -1
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	return days_after_today({"ends": e}, floori(now / 86400.0))


## Ouverture du hub (HUB_PLAN §5.2, §5.3) : purge des contrats inconnus ou
## expirés (et remplissage du tableau la toute première fois), puis contrats
## ACTIFS expirés à signaler une fois (ContractState.take_expired). Profil en
## mémoire ; rend {"changed": bool (à enregistrer, une fois), "expired":
## titres des contrats expirés à signaler}.
static func open_hub(pr: PlayerProfile, day := -1) -> Dictionary:
	var out := {"changed": false, "expired": PackedStringArray()}
	if not available(pr):
		return out
	var d := data()
	var before := JSON.stringify(pr.contracts.to_dict())
	ContractRules.rotate(pr.contracts, d, pr.level(), day if day >= 0 else today(), false)
	for id in pr.contracts.take_expired():
		var c := d.contract(id)
		out.expired.append(HubData.text_of(c.title) if not c.is_empty() else id)
	out.changed = JSON.stringify(pr.contracts.to_dict()) != before
	return out


## Rien à oublier : le catalogue vient de HubData (gardé pour HubScreen).
static func clear_cache() -> void:
	pass
