class_name ExchangeRules
extends RefCounted
## Catalogue d'échanges du scientifique (GAME_CONCEPT §4.2 ter ;
## docs/HUB_PLAN.md §6) : des échantillons contre un objet PRÉCIS, connu
## d'avance, au niveau du joueur. Pas d'XP (D10), illimité sauf `limit`.
## Pur : profil en mémoire (l'appelant enregistre une fois), jour UTC fourni
## (HubData.today()). tests/test_exchanges.gd.

## Raisons de refus ; "" : permis.
const UNKNOWN := "unknown"
const LEVEL := "level"
const NOT_STARTED := "not_started"
const ENDED := "ended"
const LIMIT := "limit"
const MISSING_SAMPLES := "missing_samples"


## Échanges affichés (dans leurs dates), dans l'ordre du fichier ; ceux d'un
## niveau trop haut en font partie (grisés au hub : ils donnent un objectif).
## `only_tradable` : seulement ceux échangeables maintenant (filtre
## « ÉCHANGEABLES MAINTENANT »).
static func listed(pr: PlayerProfile, data: HubData, day: int, only_tradable := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for x in data.exchanges:
		if not ContractRules.in_dates(x, day):
			continue
		if only_tradable and refusal(pr, data, x.id, day) != "":
			continue
		out.append(x)
	return out


## Nombre d'échanges `id` déjà faits par ce profil.
static func count(pr: PlayerProfile, id: String) -> int:
	return int(pr.exchanges_done.get(id, 0))


## Raison du refus de l'échange `id` ("" : permis).
static func refusal(pr: PlayerProfile, data: HubData, id: String, day: int) -> String:
	var x := data.exchange(id)
	if x.is_empty():
		return UNKNOWN
	if int(x.starts) >= 0 and day < int(x.starts):
		return NOT_STARTED
	if ContractRules.is_expired(x, day):
		return ENDED
	if pr.level() < int(x.min_level):
		return LEVEL
	if int(x.limit) > 0 and count(pr, id) >= int(x.limit):
		return LIMIT
	if not pr.has_samples(x.samples):
		return MISSING_SAMPLES
	return ""


## Échange `id` : vérifications (refusal), consomme EXACTEMENT le coût, crée
## l'objet au niveau du joueur (arsenal ou onglet des pièces), compte
## l'échange. Pas d'XP. `rng` : inutile pour un objet précis, gardé pour une
## arme « any » éventuelle (null : graine du profil).
## Rend {ok, reason, item, weapon_uid, part_uid}.
static func trade(pr: PlayerProfile, data: HubData, id: String, day: int,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var out := {"ok": false, "reason": refusal(pr, data, id, day), "item": null, "weapon_uid": "", "part_uid": ""}
	if out.reason != "":
		return out
	var x := data.exchange(id)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash([pr.contracts.draw_seed, id, count(pr, id), pr.next_uid])
	var item := HubRewards.make_item(x.reward, pr.level(), rng)
	if item == null:
		out.reason = UNKNOWN
		return out
	pr.consume_samples(x.samples)
	var got := HubRewards.give(pr, item)
	pr.exchanges_done[id] = count(pr, id) + 1
	out.item = item
	out.weapon_uid = got.weapon_uid
	out.part_uid = got.part_uid
	out.ok = true
	return out


## Texte d'une raison de refus (interface du hub) ; `x` : l'échange.
static func refusal_text(reason: String, x := {}) -> String:
	match reason:
		LEVEL:
			return Lang.t("NIV. %d REQUIS", "LVL %d REQUIRED") % int(x.get("min_level", 1))
		LIMIT:
			return Lang.t("LIMITE ATTEINTE", "LIMIT REACHED")
		MISSING_SAMPLES:
			return Lang.t("ÉCHANTILLONS MANQUANTS", "MISSING SAMPLES")
		ENDED, NOT_STARTED, UNKNOWN:
			return Lang.t("ÉCHANGE INDISPONIBLE", "EXCHANGE UNAVAILABLE")
	return ""
