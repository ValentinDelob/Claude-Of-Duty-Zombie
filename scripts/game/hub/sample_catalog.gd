class_name SampleCatalog
extends RefCounted
## Fiches des échantillons pour l'INVENTAIRE et le CODEX du hub v2
## (docs/hub_v2/Inventaire.dc.html, Codex.dc.html). Pur, sans interface :
##   - nom affiché (casse de phrase : « Sangle de cuir ») : le même que
##     LootRules.SAMPLES (vérifié par tests/test_hub2_items.gd), description
##     drôle FR / EN, couleur (liseré de la fiche, maquette) ;
##   - ennemi qui la porte (CodexData : fiche dont « samples » la liste) ;
##   - connue ou non : en réserve, ou son ennemi déjà rencontré (le profil ne
##     garde pas les sortes épuisées : une sorte vue mais remise à zéro reste
##     connue tant que son ennemi l'est) ;
##   - demandes : contrats ACTIFS et échanges du catalogue (dans leurs dates,
##     limite non atteinte) qui la demandent, avec « possédé / demandé » ;
##   - où la trouver et taux de butin : lus dans LootRules (SAMPLE_CHANCE,
##     BOSS_SAMPLE_CHANCE), jamais recopiés.

## Sorte -> {name [fr, en], color, text [fr, en]} (couleurs : maquette).
const INFO := {
	"dog_fang": {"name": ["Croc", "Fang"], "color": "E8E0C8",
		"text": ["Arraché à un chien qui mordait encore après sa mort. Dr Brown jure qu’il ne s’en sert pas comme cure-dent.",
			"Pulled from a dog that kept biting after it died. Dr Brown swears he doesn’t use it as a toothpick."]},
	"dog_fur": {"name": ["Touffe de poils", "Tuft of fur"], "color": "7A6A55",
		"text": ["Une touffe de poils contaminés. Ça gratte, ça sent le chien mouillé, et ça bouge parfois tout seul.",
			"A tuft of contaminated fur. It itches, smells of wet dog, and sometimes moves on its own."]},
	"dog_collar": {"name": ["Collier", "Collar"], "color": "A88038",
		"text": ["La médaille dit « Câlin ». Le chien qui le portait n’était pas d’accord.",
			"The tag says “Cuddles”. The dog wearing it begged to differ."]},
	"brancard_strap": {"name": ["Sangle de cuir", "Leather strap"], "color": "8A5A2B",
		"text": ["Arrachée au brancard d’un colosse qui ne lâchait jamais son patient. Elle sent encore le désinfectant.",
			"Torn from the stretcher of a giant who never let go of his patient. It still smells of disinfectant."]},
	"brancard_bracelet": {"name": ["Bracelet d’identité", "ID bracelet"], "color": "C9C2A8",
		"text": ["Le nom est illisible, la date d’admission aussi. Le patient, lui, est parti sans signer sa sortie.",
			"The name is unreadable, and so is the admission date. The patient left without signing out."]},
	"nurse_vocal_cords": {"name": ["Cordes vocales", "Vocal cords"], "color": "C25A7A",
		"text": ["Elles vibrent encore quand on les regarde de travers. Dr Brown les garde dans un bocal insonorisé.",
			"They still vibrate when you look at them funny. Dr Brown keeps them in a soundproof jar."]},
	"nurse_syringe": {"name": ["Seringue cassée", "Broken syringe"], "color": "9FD0FF",
		"text": ["L’aiguille est tordue, le contenu est vert. Personne ne veut savoir ce qu’il y avait dedans.",
			"The needle is bent, the contents are green. Nobody wants to know what was in it."]},
	"nurse_badge": {"name": ["Badge nominatif", "Name badge"], "color": "5A8FC2",
		"text": ["« Infirmière de nuit, toujours à l’écoute. » Surtout quand elle hurle.",
			"“Night nurse, always there to listen.” Mostly while screaming."]},
	"surgeon_scalpel": {"name": ["Scalpel", "Scalpel"], "color": "C0C4C8",
		"text": ["L’outil préféré du chef du bloc. Toujours aiguisé, jamais stérilisé.",
			"The head surgeon’s favourite tool. Always sharp, never sterilised."]},
	"surgeon_heart": {"name": ["Cœur mutant", "Mutant heart"], "color": "B0203A",
		"text": ["Il bat encore. Lentement, mais il bat. Dr Brown dit que c’est bon signe ; personne ne le croit.",
			"Still beating. Slowly, but beating. Dr Brown says it’s a good sign; nobody believes him."]},
}

## Vague où tombe une sorte (clé de LootRules.SAMPLES) : [nom FR, nom EN,
## « sur chaque … » FR, EN].
const WAVES := {
	"dogs": ["Vague de la Meute errante", "Stray Pack wave", "chaque chien de la meute", "every dog in the pack"],
	"brancardier": ["Vague du Brancardier", "Stretcher-Bearer wave", "chaque zombie de la vague", "every zombie in the wave"],
	"nurse": ["Vague de l’Infirmière hurlante", "Screaming Nurse wave", "chaque zombie de la vague", "every zombie in the wave"],
	"surgeon": ["Vague du Chirurgien", "Surgeon wave", "son escorte", "his escort"],
}

## Genre du nom français (accords « OÙ LA TROUVER », « DEMANDÉES PAR ») :
## "f" féminin, "fp" féminin pluriel ; absent : masculin.
const GENDER := {"dog_fur": "f", "brancard_strap": "f", "nurse_vocal_cords": "fp", "nurse_syringe": "f"}

const CONTRACT := "contract"
const EXCHANGE := "exchange"


## Sortes du butin, dans l'ordre de LootRules.SAMPLES.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for kind in LootRules.SAMPLES:
		for s in LootRules.SAMPLES[kind]:
			out.append(String(s[0]))
	return out


## Clé de LootRules.SAMPLES de la sorte ("" : inconnue).
static func kind_of(id: String) -> String:
	for kind in LootRules.SAMPLES:
		for s in LootRules.SAMPLES[kind]:
			if s[0] == id:
				return kind
	return ""


## Nom affiché, en casse de phrase (langue du jeu).
static func display_name(id: String) -> String:
	var i: Dictionary = INFO.get(id, {})
	if i.is_empty():
		var n := LootRules.sample_name(id)
		return n.left(1).to_upper() + n.substr(1).to_lower()
	return Lang.t(i.name[0], i.name[1])


static func description(id: String) -> String:
	var i: Dictionary = INFO.get(id, {})
	return Lang.t(i.text[0], i.text[1]) if not i.is_empty() else ""


## Titres de la fiche accordés : « OÙ LA TROUVER » / « OÙ LE TROUVER » /
## « OÙ LES TROUVER ».
static func where_title(id: String) -> String:
	var g := String(GENDER.get(id, "m"))
	var fr := "OÙ LES TROUVER" if g == "fp" else ("OÙ LA TROUVER" if g == "f" else "OÙ LE TROUVER")
	return Lang.t(fr, "WHERE TO FIND THEM" if g == "fp" else "WHERE TO FIND IT")


## « DEMANDÉE PAR » / « DEMANDÉ PAR » / « DEMANDÉES PAR ».
static func asked_title(id: String) -> String:
	var g := String(GENDER.get(id, "m"))
	var fr := "DEMANDÉES PAR" if g == "fp" else ("DEMANDÉE PAR" if g == "f" else "DEMANDÉ PAR")
	return Lang.t(fr, "REQUESTED BY")


## Aucune demande : « Personne ne la demande pour l’instant. »
static func nobody_text(id: String) -> String:
	var g := String(GENDER.get(id, "m"))
	var pron := "les" if g == "fp" else ("la" if g == "f" else "le")
	return Lang.t("Personne ne %s demande pour l’instant." % pron,
			"Nobody is asking for %s right now." % ("them" if g == "fp" else "it"))


static func color(id: String) -> Color:
	return Color(String(INFO.get(id, {}).get("color", "C9C7BE")))


## Fiche du codex de l'ennemi qui porte la sorte ({} : aucune).
static func enemy_of(id: String, codex: CodexData) -> Dictionary:
	return codex.entry_of_sample(id) if codex else {}


## Sorte connue : en réserve, ou ennemi qui la porte déjà rencontré.
static func is_known(pr: PlayerProfile, id: String, codex: CodexData) -> bool:
	if pr == null:
		return false
	if pr.sample_count(id) > 0:
		return true
	var e := enemy_of(id, codex)
	return not e.is_empty() and pr.codex.is_known(String(e.id))


## Échantillons en réserve, toutes sortes du butin.
static func total(pr: PlayerProfile) -> int:
	var n := 0
	for id in ids():
		n += pr.sample_count(id) if pr else 0
	return n


static func known_count(pr: PlayerProfile, codex: CodexData) -> int:
	var n := 0
	for id in ids():
		if is_known(pr, id, codex):
			n += 1
	return n


## Demandes de la sorte : contrats actifs (ordre d'acceptation) puis échanges
## du catalogue affichés (dans leurs dates, limite non atteinte) :
## [{kind (CONTRACT / EXCHANGE), id, title, have, need}].
static func uses(pr: PlayerProfile, id: String, data: HubData, day: int) -> Array:
	var out := []
	if pr == null or data == null:
		return out
	if pr.contracts:
		for cid in pr.contracts.active_ids():
			var c := data.contract(cid)
			if not c.is_empty() and c.samples.has(id):
				out.append({"kind": CONTRACT, "id": cid, "title": HubData.text_of(c.title),
					"have": pr.sample_count(id), "need": int(c.samples[id])})
	for x in ExchangeRules.listed(pr, data, day):
		if not x.samples.has(id) or ExchangeRules.refusal(pr, data, x.id, day) == ExchangeRules.LIMIT:
			continue
		out.append({"kind": EXCHANGE, "id": String(x.id), "title": HubData.text_of(x.title),
			"have": pr.sample_count(id), "need": int(x.samples[id])})
	return out


## Ligne d'usage de la carte : « 2 contrats · 1 échange », « 1 contrat »,
## « Aucune demande ».
static func use_line(list: Array) -> String:
	var nc := 0
	var nx := 0
	for u in list:
		if u.kind == CONTRACT:
			nc += 1
		else:
			nx += 1
	var parts := PackedStringArray()
	if nc > 0:
		parts.append(Lang.t("%d contrat" if nc == 1 else "%d contrats", "%d contract" if nc == 1 else "%d contracts") % nc)
	if nx > 0:
		parts.append(Lang.t("%d échange" if nx == 1 else "%d échanges", "%d exchange" if nx == 1 else "%d exchanges") % nx)
	if parts.is_empty():
		return Lang.t("Aucune demande", "Not requested")
	return " · ".join(parts)


## Taux en pourcentage : « 20 % » (espace insécable) en français, « 20% » en
## anglais.
static func percent(chance: float) -> String:
	var n := roundi(clampf(chance, 0.0, 1.0) * 100.0)
	return ("%d%%" % n) if Lang.is_en() else ("%d" + String.chr(0xA0) + "%%") % n


## La sorte vient d'un boss (catégorie BOSS de XpRules : taux du boss lui-même
## BOSS_SAMPLE_CHANCE, son escorte SAMPLE_CHANCE).
static func from_boss(id: String, codex: CodexData) -> bool:
	var e := enemy_of(id, codex)
	return not e.is_empty() and CodexData.category(e) == XpRules.BOSS


## « OÙ LA TROUVER » : « Vague du Brancardier, dès la manche 10 : 20 % sur
## chaque zombie de la vague. »
static func where_text(id: String, codex: CodexData) -> String:
	var w: Array = WAVES.get(kind_of(id), [])
	var e := enemy_of(id, codex)
	var wave := Lang.t(w[0], w[1]) if not w.is_empty() else Lang.t("Vague spéciale", "Special wave")
	var on := Lang.t(w[2], w[3]) if not w.is_empty() else Lang.t("chaque zombie de la vague", "every zombie in the wave")
	var r := int(e.get("round", 1)) if not e.is_empty() else 1
	var rate := percent(LootRules.SAMPLE_CHANCE)
	if from_boss(id, codex):
		return Lang.t("%s, dès la manche %d : %s sur le boss, %s sur %s.", "%s, from round %d: %s on the boss, %s on %s.") \
				% [wave, r, percent(LootRules.BOSS_SAMPLE_CHANCE), rate, on]
	return Lang.t("%s, dès la manche %d : %s sur %s.", "%s, from round %d: %s on %s.") % [wave, r, rate, on]


## Taux de butin d'une sorte pour le CODEX : {rate, note}.
static func loot_rate(id: String, codex: CodexData) -> Dictionary:
	if from_boss(id, codex):
		return {"rate": percent(LootRules.BOSS_SAMPLE_CHANCE),
			"note": Lang.t("sur le boss · %s sur son escorte", "on the boss · %s on his escort") % percent(LootRules.SAMPLE_CHANCE)}
	return {"rate": percent(LootRules.SAMPLE_CHANCE),
		"note": Lang.t("par zombie tué pendant sa vague", "per zombie killed during its wave")}
