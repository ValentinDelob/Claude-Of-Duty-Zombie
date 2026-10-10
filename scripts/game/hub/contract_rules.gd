class_name ContractRules
extends RefCounted
## Règles des contrats du scientifique (GAME_CONCEPT §4.2 ; docs/HUB_PLAN.md
## §5.2, §5.3) : éligibilité, rotation du tableau, accepter, abandonner,
## remettre, expiration, progression, objectif atteint en partie. Pur : état
## dans le profil (ContractState, PlayerProfile), catalogue HubData, jour UTC
## fourni par l'appelant (HubData.today()) ; aucune écriture de fichier ici
## (MatchContracts et le hub enregistrent). tests/test_contracts.gd.
##
## Choix (provisoires, docs/HUB_PLAN.md §5.3) :
## * Le tableau n'est REMPLI qu'à la fin d'une partie d'au moins
##   `min_rounds_for_rotation` manche survécue (rotate(..., true)) et la toute
##   première fois (profil neuf ou venu de la version 1 : rotation == 0). Une
##   ouverture du hub ensuite ne fait que la purge : une proposition acceptée
##   laisse sa case vide jusqu'à la partie suivante (§5.2, D7).
## * Seuls les contrats ACTIFS expirés sont signalés au joueur
##   (ContractState.expired_unseen) : une proposition jamais acceptée disparaît
##   sans message.
## * La récompense est créée au niveau du joueur AVANT l'XP du contrat (celui
##   affiché sur la fiche au moment de la remise).

## Raisons de refus (accept / deliver) ; "" : permis.
const UNKNOWN := "unknown"
const NOT_OFFERED := "not_offered"
const NOT_ACTIVE := "not_active"
const ACTIVE_FULL := "active_full"
const EXPIRED := "expired"
const MISSING_SAMPLES := "missing_samples"


# --------------------------------------------------------------------------
# Éligibilité et dates
# --------------------------------------------------------------------------

## Contrat terminé par sa date de fin (dernier jour `ends` fini, 24 h UTC) ?
static func is_expired(c: Dictionary, day: int) -> bool:
	return int(c.get("ends", -1)) >= 0 and day > int(c.ends)


## Dans ses dates (commencé et pas fini) ?
static func in_dates(c: Dictionary, day: int) -> bool:
	return (int(c.get("starts", -1)) < 0 or day >= int(c.starts)) and not is_expired(c, day)


## Jours restants avant la fin d'un contrat daté, jour en cours compris
## (1 : dernier jour) ; -1 : sans date de fin.
static func days_left(c: Dictionary, day: int) -> int:
	if int(c.get("ends", -1)) < 0:
		return -1
	return maxi(int(c.ends) - day + 1, 0)


## Peut-il être tiré au sort (hors absence de doublon) ? Niveau dans
## [min_level, max_level], dans ses dates, contrats `after` remplis, pas un
## contrat non répétable déjà rempli.
static func is_eligible(c: Dictionary, st: ContractState, lvl: int, day: int) -> bool:
	if c.is_empty() or lvl < int(c.min_level) or lvl > int(c.max_level) or not in_dates(c, day):
		return false
	if not c.repeatable and st.done_count(c.id) > 0:
		return false
	for a in c.after:
		if st.done_count(a) <= 0:
			return false
	return true


# --------------------------------------------------------------------------
# Rotation (§5.3)
# --------------------------------------------------------------------------

## Purge : propositions et contrats actifs inconnus du catalogue (avertissement)
## ou expirés retirés ; un contrat actif expiré est noté pour être signalé.
## Rend {"unknown": [...], "expired": [...]}.
static func purge(st: ContractState, data: HubData, day: int) -> Dictionary:
	var out := {"unknown": [], "expired": []}
	for is_active in [false, true]:
		var list: Array[Dictionary] = st.active if is_active else st.offers
		var i := 0
		while i < list.size():
			var id: String = list[i].id
			var c := data.contract(id)
			if c.is_empty():
				push_warning("[Contracts] contrat « %s » absent du catalogue : retiré du profil" % id)
				out.unknown.append(id)
				list.remove_at(i)
			elif is_expired(c, day):
				out.expired.append(id)
				if is_active and not id in st.expired_unseen:
					st.expired_unseen.append(id)
				list.remove_at(i)
			else:
				i += 1
	return out


## Rotation du tableau (fonction pure, §5.3) :
## 1. purge (inconnus, expirés) ;
## 2. après une partie (`after_match`) : les `replace_per_match` plus
##    anciennes propositions sont retirées ;
## 3. remplissage jusqu'à `offers` propositions (après une partie, ou la
##    première fois : rotation == 0) : d'abord un contrat tutoriel éligible
##    jamais rempli, puis tirage pondéré sans remise parmi les éligibles
##    (sans doublon avec les propositions et les actifs, sans les retirées
##    de l'étape 2) ; générateur initialisé par `graine + rotation` ;
## 4. compteur de rotations + 1 (à chaque remplissage).
## Rend {"unknown", "expired", "removed", "added" (identifiants), "filled" (bool)}.
static func rotate(st: ContractState, data: HubData, lvl: int, day: int, after_match: bool) -> Dictionary:
	var out := purge(st, data, day)
	out.removed = []
	out.added = []
	out.filled = false
	if not after_match and st.rotation > 0:
		return out
	if after_match:
		var n := int(data.rules.replace_per_match)
		while n > 0 and not st.offers.is_empty():
			var oldest := 0
			for i in st.offers.size():
				if int(st.offers[i].since) < int(st.offers[oldest].since):
					oldest = i
			out.removed.append(st.offers[oldest].id)
			st.offers.remove_at(oldest)
			n -= 1
	st.rotation += 1
	out.filled = true
	var rng := RandomNumberGenerator.new()
	rng.seed = st.draw_seed + st.rotation
	var want := int(data.rules.offers)
	# Contrat tutoriel d'abord (jamais tiré au sort ensuite).
	for c in data.contracts:
		if st.offers.size() >= want:
			break
		if c.tutorial and st.done_count(c.id) == 0 and _free(c.id, st, out.removed) and is_eligible(c, st, lvl, day):
			_offer(st, c.id, out)
	var pool: Array[Dictionary] = []
	for c in data.contracts:
		if not c.tutorial and float(c.weight) > 0.0 and _free(c.id, st, out.removed) and is_eligible(c, st, lvl, day):
			pool.append(c)
	while st.offers.size() < want and not pool.is_empty():
		var i := pick_weighted(pool, rng)
		_offer(st, pool[i].id, out)
		pool.remove_at(i)
	return out


## Indice tiré dans `pool` selon les poids (`weight`).
static func pick_weighted(pool: Array[Dictionary], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for c in pool:
		total += float(c.weight)
	var x := rng.randf() * total
	for i in pool.size():
		x -= float(pool[i].weight)
		if x < 0.0:
			return i
	return pool.size() - 1


static func _free(id: String, st: ContractState, removed: Array) -> bool:
	return not st.is_offered(id) and not st.is_active(id) and not id in removed


static func _offer(st: ContractState, id: String, out: Dictionary) -> void:
	st.offers.append({"id": id, "since": st.rotation})
	out.added.append(id)


# --------------------------------------------------------------------------
# Accepter, abandonner, remettre (§5.2)
# --------------------------------------------------------------------------

## Raison du refus d'accepter la proposition `id` ("" : permis).
static func accept_refusal(st: ContractState, data: HubData, id: String, day: int) -> String:
	var c := data.contract(id)
	if c.is_empty():
		return UNKNOWN
	if not st.is_offered(id):
		return NOT_OFFERED
	if is_expired(c, day):
		return EXPIRED
	if st.active.size() >= int(data.rules.active_max):
		return ACTIVE_FULL
	return ""


## Accepte la proposition `id` : elle devient active, sa case reste vide
## jusqu'à la prochaine rotation. Rend la raison du refus ("" : fait).
static func accept(st: ContractState, data: HubData, id: String, day: int) -> String:
	var why := accept_refusal(st, data, id, day)
	if why == "":
		st.remove_offer(id)
		st.active.append({"id": id, "accepted": st.rotation})
	return why


## Abandonne le contrat actif `id` : supprimé, rien n'est consommé, aucune
## pénalité (il pourra revenir par le tirage). Faux s'il n'est pas actif.
static func abandon(st: ContractState, id: String) -> bool:
	return st.remove_active(id)


## Progression : sorte -> [possédés (au plus demandés), demandés].
## Calculée, jamais enregistrée.
static func progress(c: Dictionary, samples: Dictionary) -> Dictionary:
	var out := {}
	for k in c.get("samples", {}):
		var need := int(c.samples[k])
		out[k] = [mini(int(samples.get(k, 0)), need), need]
	return out


## Toutes les quantités demandées sont-elles dans `samples` ?
static func covered(c: Dictionary, samples: Dictionary) -> bool:
	if c.is_empty():
		return false
	for k in c.samples:
		if int(samples.get(k, 0)) < int(c.samples[k]):
			return false
	return true


## Raison du refus de remettre le contrat actif `id` ("" : permis).
static func deliver_refusal(pr: PlayerProfile, data: HubData, id: String, day: int) -> String:
	var c := data.contract(id)
	if c.is_empty():
		return UNKNOWN
	if not pr.contracts.is_active(id):
		return NOT_ACTIVE
	if is_expired(c, day):
		return EXPIRED
	if not pr.has_samples(c.samples):
		return MISSING_SAMPLES
	return ""


## Remet le contrat actif `id` (profil en mémoire ; l'appelant enregistre
## une fois) : consomme EXACTEMENT les quantités demandées, ajoute l'XP
## (HubRewards.contract_xp au niveau actuel), crée l'objet au niveau du joueur
## (arsenal ou onglet des pièces), compte la remise et libère la case.
## `rng` : générateur de la récompense (null : graine du profil, reproductible).
## Rend {ok, reason, xp, level_before, level_after, levels, item (OwnedWeapon,
## WeaponPart ou null), weapon_uid, part_uid, thanks ({fr, en} ou {})}.
static func deliver(pr: PlayerProfile, data: HubData, id: String, day: int,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var out := {"ok": false, "reason": deliver_refusal(pr, data, id, day), "xp": 0, "level_before": pr.level(),
		"level_after": pr.level(), "levels": 0, "item": null, "weapon_uid": "", "part_uid": "", "thanks": {}}
	if out.reason != "":
		return out
	var c := data.contract(id)
	var st := pr.contracts
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash([st.draw_seed, id, st.done_total(), pr.next_uid])
	var lvl := pr.level()
	pr.consume_samples(c.samples)
	var item := HubRewards.make_item(c.reward, lvl, rng)
	var got := HubRewards.give(pr, item)
	out.xp = HubRewards.contract_xp(int(c.xp), lvl, float(data.rules.xp_level_factor))
	out.levels = pr.add_xp(out.xp)
	out.level_after = pr.level()
	out.item = item
	out.weapon_uid = got.weapon_uid
	out.part_uid = got.part_uid
	out.thanks = c.thanks
	st.done[id] = st.done_count(id) + 1
	st.remove_active(id)
	out.ok = true
	return out


## XP qu'un contrat rapporterait au niveau `lvl`.
static func xp_for(data: HubData, c: Dictionary, lvl: int) -> int:
	return HubRewards.contract_xp(int(c.get("xp", 0)), lvl, float(data.rules.xp_level_factor))


## Autres contrats actifs qui demandent une même sorte d'échantillon que `id`
## (remettre l'un peut faire reculer l'autre).
static func shared_with(st: ContractState, data: HubData, id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var c := data.contract(id)
	if c.is_empty():
		return out
	for other in st.active_ids():
		if other == id:
			continue
		var o := data.contract(other)
		for k in c.samples:
			if o.get("samples", {}).has(k):
				out.append(other)
				break
	return out


# --------------------------------------------------------------------------
# Objectif atteint en partie (D13, ContractWatch du lot E)
# --------------------------------------------------------------------------

## Le contrat `c` est-il couvert par les échantillons du profil plus ceux
## de la partie en cours (pas encore rapportés) ?
static func goal_met(c: Dictionary, profile_samples: Dictionary, match_samples: Dictionary) -> bool:
	if c.is_empty():
		return false
	for k in c.samples:
		if int(profile_samples.get(k, 0)) + int(match_samples.get(k, 0)) < int(c.samples[k]):
			return false
	return true


## Contrats actifs (non expirés) couverts par profil + partie, dans l'ordre
## d'acceptation. Pour un message unique par contrat, l'appelant garde ceux
## déjà annoncés (et ceux déjà couverts au début de la partie : appel avec
## `match_samples` vide).
static func goals_met(pr: PlayerProfile, data: HubData, match_samples: Dictionary, day: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in pr.contracts.active_ids():
		var c := data.contract(id)
		if not c.is_empty() and not is_expired(c, day) and goal_met(c, pr.samples, match_samples):
			out.append(id)
	return out


## Message en partie : « CONTRAT « … » : OBJECTIF ATTEINT — évacuez pour
## garder vos échantillons ».
static func goal_message(c: Dictionary) -> String:
	return Lang.t("CONTRAT « %s » : OBJECTIF ATTEINT — évacuez pour garder vos échantillons",
			"CONTRACT \"%s\": GOAL REACHED — evacuate to keep your samples") % HubData.text_of(c.get("title"))


## Texte d'une raison de refus (interface du hub) ; `active_max` : règle
## du tableau (HubData.rules.active_max).
static func refusal_text(reason: String, active_max := 3) -> String:
	match reason:
		ACTIVE_FULL:
			return Lang.t("%d CONTRATS ACTIFS AU MAXIMUM", "%d ACTIVE CONTRACTS AT MOST") % active_max
		MISSING_SAMPLES:
			return Lang.t("ÉCHANTILLONS MANQUANTS", "MISSING SAMPLES")
		EXPIRED:
			return Lang.t("CONTRAT EXPIRÉ", "CONTRACT EXPIRED")
		NOT_OFFERED, NOT_ACTIVE, UNKNOWN:
			return Lang.t("CONTRAT INDISPONIBLE", "CONTRACT UNAVAILABLE")
	return ""
