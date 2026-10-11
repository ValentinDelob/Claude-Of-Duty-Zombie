class_name StoryRules
extends RefCounted
## Règles des contrats d'HISTOIRE (GAME_CONCEPT §4.2 quater, 💡 provisoire ;
## docs/HUB_PLAN.md §5.7) : une ligne de chapitres et d'étapes remplies
## DANS L'ORDRE, une seule étape active à la fois, toujours active (rien à
## accepter, rien à abandonner, jamais d'expiration). Elle pilote la
## progression ; les contrats TEMPORAIRES (ContractRules, tableau qui tourne)
## donnent un bonus en attendant. Les échantillons sont en commun.
##
## * Étape en cours : la première étape du fichier (StoryData) non remise.
## * Remise : niveau du joueur ≥ `min_level` de l'étape et échantillons
##   demandés en réserve -> consomme EXACTEMENT les quantités, crée l'objet au
##   niveau du joueur (HubRewards, avant l'XP comme un contrat), ajoute l'XP
##   (base × (1 + xp_level_factor × (niveau − 1)), arrondie à 10), note
##   l'étape remise : l'étape suivante est débloquée. Une écriture du profil
##   (par l'appelant).
## * Objet tiré avec un générateur dont la graine dépend du profil
##   (graine des contrats, étape, prochain identifiant) : l'aperçu montré au
##   hub (preview_item) est EXACTEMENT l'objet remis.
## Pur : profil en mémoire, histoire fournie (défaut : fichier livré, ou
## `data_override` pour les tests et scénarios). tests/test_story.gd.

const COMPLETE := "complete"
const LEVEL := "level"
const MISSING_SAMPLES := "missing_samples"

## États d'une étape (frise du chapitre).
const DONE := "done"
const CURRENT := "current"
const LOCKED := "locked"

## Histoire imposée (null : fichier livré).
static var data_override: StoryData = null


static func data() -> StoryData:
	return data_override if data_override != null else StoryData.shipped()


static func _d(d: StoryData) -> StoryData:
	return d if d != null else data()


## Étape en cours ({} : histoire terminée, ou vide).
static func current(pr: PlayerProfile, d: StoryData = null) -> Dictionary:
	for s in _d(d).steps:
		if not pr.story.is_done(s.id):
			return s
	return {}


static func is_complete(pr: PlayerProfile, d: StoryData = null) -> bool:
	return current(pr, d).is_empty()


## Raison du refus de remettre l'étape en cours ("" : permis).
static func refusal(pr: PlayerProfile, d: StoryData = null) -> String:
	var s := current(pr, d)
	if s.is_empty():
		return COMPLETE
	if pr.level() < int(s.min_level):
		return LEVEL
	if not pr.has_samples(s.samples):
		return MISSING_SAMPLES
	return ""


## L'étape en cours est-elle prête à remettre ?
static func is_ready(pr: PlayerProfile, d: StoryData = null) -> bool:
	return refusal(pr, d) == ""


## État d'une étape pour la frise : remise, en cours, ou verrouillée.
static func step_state(pr: PlayerProfile, step: Dictionary, d: StoryData = null) -> String:
	if pr.story.is_done(step.id):
		return DONE
	return CURRENT if current(pr, d).get("id", "") == step.id else LOCKED


## Étape qui suit `id` dans l'histoire ({} : dernière).
static func next_step(id: String, d: StoryData = null) -> Dictionary:
	var dd := _d(d)
	var i := dd.step_index(id)
	return dd.steps[i + 1] if i >= 0 and i + 1 < dd.steps.size() else {}


## XP de l'étape au niveau `lvl`.
static func xp_for(step: Dictionary, lvl: int, d: StoryData = null) -> int:
	return HubRewards.contract_xp(int(step.get("xp", 0)), lvl, float(_d(d).rules.xp_level_factor))


## Générateur de la récompense de l'étape `id` (même graine pour l'aperçu
## et la remise, tant que le profil ne change pas).
static func reward_rng(pr: PlayerProfile, id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([pr.contracts.draw_seed, "story", id, pr.next_uid])
	return rng


## Objet que l'étape donnerait maintenant (OwnedWeapon, WeaponPart ou null),
## sans rien changer au profil.
static func preview_item(pr: PlayerProfile, step: Dictionary) -> RefCounted:
	if step.is_empty():
		return null
	return HubRewards.make_item(step.reward, pr.level(), reward_rng(pr, step.id))


## Remet l'étape en cours (profil en mémoire ; l'appelant enregistre une
## fois). `rng` : générateur de la récompense (null : reward_rng).
## Rend {ok, reason, step, next ({} : histoire finie), chapter_done (bool),
## xp, level_before, level_after, levels, item, weapon_uid, part_uid,
## thanks ({fr, en} ou {})}.
static func deliver(pr: PlayerProfile, d: StoryData = null, rng: RandomNumberGenerator = null) -> Dictionary:
	var dd := _d(d)
	var s := current(pr, dd)
	var out := {"ok": false, "reason": refusal(pr, dd), "step": s, "next": {}, "chapter_done": false, "xp": 0,
		"level_before": pr.level(), "level_after": pr.level(), "levels": 0, "item": null, "weapon_uid": "",
		"part_uid": "", "thanks": {}}
	if out.reason != "":
		return out
	if rng == null:
		rng = reward_rng(pr, s.id)
	var lvl := pr.level()
	pr.consume_samples(s.samples)
	var item := HubRewards.make_item(s.reward, lvl, rng)
	var got := HubRewards.give(pr, item)
	out.xp = xp_for(s, lvl, dd)
	out.levels = pr.add_xp(out.xp)
	out.level_after = pr.level()
	out.item = item
	out.weapon_uid = got.weapon_uid
	out.part_uid = got.part_uid
	out.thanks = s.thanks
	pr.story.mark_done(s.id)
	out.next = current(pr, dd)
	out.chapter_done = out.next.is_empty() or String(out.next.chapter) != String(s.chapter)
	out.ok = true
	return out


## Texte d'une raison de refus (interface du hub) ; `step` : l'étape.
static func refusal_text(reason: String, step := {}) -> String:
	match reason:
		LEVEL:
			return Lang.t("NIV. %d REQUIS", "LVL %d REQUIRED") % int(step.get("min_level", 1))
		MISSING_SAMPLES:
			return Lang.t("ÉCHANTILLONS MANQUANTS", "MISSING SAMPLES")
		COMPLETE:
			return Lang.t("HISTOIRE TERMINÉE", "STORY COMPLETE")
	return ""
