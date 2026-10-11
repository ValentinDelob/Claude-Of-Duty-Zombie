class_name Hub2LabKit
extends RefCounted
## Outils communs aux écrans du LABO du hub v2 (LABO, CONTRATS, ÉCHANGES ;
## maquettes docs/hub_v2/Main.dc.html, Contrats.dc.html, Echanges.dc.html) :
## mots et couleurs des échantillons, fiches des tuiles de récompense (arme,
## pièce, XP) et de leur infobulle, textes des délais, réplique de Dr Brown
## selon la situation, contrats prêts (histoire + temporaires). Pur (aucun
## nœud) : les écrans s'en servent pour construire leurs contrôles.

## Couleur de chaque sorte d'échantillon (pastille des coûts ; maquettes
## Echanges.dc.html et Inventaire.dc.html).
const SAMPLE_COLORS := {
	"dog_fang": Color("E8E0C8"), "dog_fur": Color("7A6A55"), "dog_collar": Color("A88038"),
	"brancard_strap": Color("8A5A2B"), "brancard_bracelet": Color("C9C2A8"),
	"nurse_vocal_cords": Color("C25A7A"), "nurse_syringe": Color("9FD0FF"), "nurse_badge": Color("5A8FC2"),
	"surgeon_scalpel": Color("C0C4C8"), "surgeon_heart": Color("B0203A"),
}
## Mots courts des échantillons [FR singulier, FR pluriel, EN singulier, EN
## pluriel] (« Crocs 4/6 », « 3 colliers · 4 touffes »).
const WORDS := {
	"dog_fang": ["croc", "crocs", "fang", "fangs"],
	"dog_fur": ["touffe", "touffes", "tuft", "tufts"],
	"dog_collar": ["collier", "colliers", "collar", "collars"],
	"brancard_strap": ["sangle", "sangles", "strap", "straps"],
	"brancard_bracelet": ["bracelet", "bracelets", "bracelet", "bracelets"],
	"nurse_vocal_cords": ["cordes vocales", "cordes vocales", "vocal cords", "vocal cords"],
	"nurse_syringe": ["seringue", "seringues", "syringe", "syringes"],
	"nurse_badge": ["badge", "badges", "badge", "badges"],
	"surgeon_scalpel": ["scalpel", "scalpels", "scalpel", "scalpels"],
	"surgeon_heart": ["cœur", "cœurs", "heart", "hearts"],
}
## Couleur des qualités de pièce (même échelle que les raretés : ordinaire
## = commune, soignée = rare, d'exception = épique).
const QUALITY_RARITY := {"standard": 0, "fine": 1, "superior": 2}
## Nombre de modificateurs d'une pièce de contrat (HubRewards.QUALITY_MODS).
const QUALITY_EFFECTS := {"standard": 1, "fine": 2, "superior": 2}
## Noms des modificateurs dans les fiches du hub v2 [FR, EN].
const MOD_WORDS := {
	"damage": ["dégâts", "damage"], "fire_rate": ["cadence", "fire rate"],
	"reload": ["vitesse de rechargement", "reload speed"], "recoil": ["maîtrise du recul", "recoil control"],
	"accuracy": ["précision", "accuracy"], "mag": ["chargeur", "magazine"], "reserve": ["réserve", "reserve"],
}
## Précision affichée (0 à 100) = 100 − 12 × dispersion à la hanche (°),
## comme la fiche d'arme du hub (HubGear.accuracy).
const ACCURACY_PER_DEG := 12.0


# --- Échantillons -------------------------------------------------------------

static func sample_color(kind: String) -> Color:
	return SAMPLE_COLORS.get(kind, Hub2Style.text_a(0.6))


## Mot court d'une sorte : singulier ou pluriel (FR : 0 et 1 au singulier).
static func word(kind: String, n: int) -> String:
	var w: Array = WORDS.get(kind, [])
	if w.is_empty():
		return LootRules.sample_name(kind).to_lower()
	if Lang.is_en():
		return w[2] if n == 1 else w[3]
	return w[0] if n <= 1 else w[1]


## « Crocs », « Badge » : mot court avec une majuscule.
static func word_cap(kind: String, n: int) -> String:
	return capitalize(word(kind, n))


## Nom complet d'une sorte avec une majuscule (« Sangle de cuir ») ; les
## sigles restent en capitales (« ID bracelet »).
static func full_name(kind: String) -> String:
	var words := LootRules.sample_name(kind).split(" ")
	for i in words.size():
		if words[i] != "ID":
			words[i] = words[i].to_lower()
	return capitalize(" ".join(words))


static func capitalize(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


## « 3 colliers · 4 touffes » (demande d'une proposition).
static func cost_line(cost: Dictionary) -> String:
	var out := PackedStringArray()
	for k in cost:
		out.append("%d %s" % [int(cost[k]), word(String(k), int(cost[k]))])
	return " · ".join(out)


# --- Récompenses --------------------------------------------------------------

## Récompense en quelques mots (« arme rare », « pièce soignée »), "" : rien.
static func reward_words(reward: Dictionary) -> String:
	match reward.get("kind"):
		"weapon":
			var r := maxi(OwnedWeapon.rarity_from_key(reward.get("rarity", "common")), 0)
			var rn := GameWeapon.rarity_name(r).to_lower()
			return Lang.t("arme %s" % rn, "%s weapon" % rn)
		"part":
			var q := String(reward.get("quality", quality_of_mods(reward.get("mods", {}))))
			var qn := HubData.quality_name(q).to_lower()
			return Lang.t("pièce %s" % qn, "%s part" % qn)
	return ""


## Qualité d'une pièce aux modificateurs exacts (catalogue d'échanges,
## provisoire) : deux bonus d'au moins 10 % -> d'exception ; un bonus d'au
## moins 10 % -> soignée ; sinon ordinaire.
static func quality_of_mods(mods: Variant) -> String:
	if not mods is Dictionary or mods.is_empty():
		return "standard"
	var big := 0
	for k in mods:
		if float(mods[k]) >= 0.1 - 1e-6:
			big += 1
	if big >= 2:
		return "superior"
	return "fine" if big >= 1 else "standard"


## Modificateurs en clair : « +20 % précision · +5 % dégâts ».
static func mods_line(mods: Dictionary) -> String:
	var out := PackedStringArray()
	for k in mods:
		var v := float(mods[k])
		var n: Array = MOD_WORDS.get(String(k), [String(k), String(k)])
		out.append("%s%d %% %s" % ["+" if v >= 0.0 else "−", roundi(absf(v) * 100.0), Lang.t(n[0], n[1])])
	return " · ".join(out)


## Précision affichée d'après les statistiques d'une arme.
static func accuracy(s: Dictionary) -> int:
	return clampi(roundi(100.0 - ACCURACY_PER_DEG * float(s.get("spread_hip", 0.0))), 0, 100)


## Nombre décimal à la langue (« 1,7 » / « 1.7 »).
static func decimal(v: float) -> String:
	var t := "%.1f" % v
	return t.replace(".", ",") if not Lang.is_en() else t


## Statistiques de l'infobulle d'une arme : [[libellé, valeur]] (maquette :
## Dégâts, Cadence, Précision, Portée, Chargeur, Recharge).
static func weapon_stats(w: OwnedWeapon) -> Array:
	var s := GameWeapon.stats(GameWeapon.from_owned(w))
	if WeaponDB.is_melee(w.weapon_id):
		return [[Lang.t("Dégâts", "Damage"), Hub2Style.num(int(s.get("damage", 0)))],
			[Lang.t("Coups / s", "Hits / s"), decimal(float(s.get("rpm", 60)) / 60.0)]]
	return [
		[Lang.t("Dégâts", "Damage"), Hub2Style.num(int(s.get("damage", 0)))],
		[Lang.t("Cadence", "Fire rate"), "%s/min" % Hub2Style.num(int(s.get("rpm", 0)))],
		[Lang.t("Précision", "Accuracy"), "%d %%" % accuracy(s)],
		[Lang.t("Portée", "Range"), "%d m" % roundi(float(s.get("range", 0.0)))],
		[Lang.t("Chargeur", "Magazine"), str(int(s.get("mag", 0)))],
		[Lang.t("Recharge", "Reload"), "%s s" % decimal(float(s.get("reload", 0.0)))],
	]


## Fiche d'une tuile d'ARME (et de son infobulle) pour l'arme `w`.
static func weapon_tile(w: OwnedWeapon) -> Dictionary:
	var r := int(w.rarity)
	var col := Hub2Style.rarity_color(r)
	var rn := GameWeapon.rarity_name(r)
	var fam := WeaponDB.family_name(w.weapon_id)
	var lvl := Lang.t("NIV. %d", "LVL %d") % w.level
	var kind := Lang.t("ARME %s · %s · %s" % [rn, fam, lvl], "%s WEAPON · %s · %s" % [rn, fam, lvl])
	var nm := WeaponDB.display_name(w.weapon_id)
	return {"img": HubRenders.weapon(w.weapon_id), "big": "", "color": col, "cap": lvl, "cap_color": Hub2Style.TEXT,
		"alt": Lang.t("Arme %s niveau %d : %s" % [rn.to_lower(), w.level, nm],
			"%s weapon level %d: %s" % [capitalize(rn.to_lower()), w.level, nm]),
		"kind": kind, "name": nm, "stats": weapon_stats(w),
		"note": Lang.t("%d emplacement%s de pièce · score %s", "%d part slot%s · score %s") % [w.slot_count(),
			"s" if w.slot_count() > 1 else "", Hub2Style.num(w.score())]}


## Fiche d'une tuile de PIÈCE de qualité `quality` au niveau `lvl` (pièce
## tirée au hasard à la remise).
static func part_tile(quality: String, lvl: int) -> Dictionary:
	var col := Hub2Style.rarity_color(int(QUALITY_RARITY.get(quality, 0)))
	var qn := HubData.quality_name(quality)
	var l := Lang.t("NIV. %d", "LVL %d") % lvl
	return {"img": null, "big": Lang.t("PIÈCE", "PART"), "color": col, "cap": l, "cap_color": Hub2Style.TEXT,
		"alt": Lang.t("Pièce %s", "%s part") % qn.to_lower(),
		"kind": Lang.t("PIÈCE %s" % qn, "%s PART" % qn),
		"name": Lang.t("Pièce %s au hasard" % qn.to_lower(), "Random %s part" % qn.to_lower()),
		"stats": [[Lang.t("Niveau", "Level"), str(lvl)], [Lang.t("Effets", "Effects"), str(int(QUALITY_EFFECTS.get(quality, 1)))]],
		"note": Lang.t("Se monte sur une arme de niveau %d ou plus", "Fits a weapon of level %d or higher") % lvl}


## Fiche d'une tuile d'XP : `xp` gagnée par le profil `pr` ; `detail` :
## niveau avant → après et progression (histoire), sinon le niveau seul.
static func xp_tile(pr: PlayerProfile, xp: int, detail: bool) -> Dictionary:
	var lvl := pr.level()
	var stats := [[Lang.t("Niveau", "Level"), str(lvl)]]
	if detail:
		var after := PlayerProfile.level_for_xp(pr.xp + xp)
		stats = [[Lang.t("Niveau", "Level"), "%d → %d" % [lvl, after]],
			[Lang.t("Progression", "Progress"), "%d → %d %%" % [roundi(progress(pr.xp) * 100.0), roundi(progress(pr.xp + xp) * 100.0)]]]
	var n := Hub2Style.num(xp)
	return {"img": null, "big": "XP", "color": Hub2Style.YELLOW, "cap": "+" + n, "cap_color": Hub2Style.YELLOW,
		"alt": Lang.t("%s points d’expérience", "%s experience points") % n,
		"kind": Lang.t("EXPÉRIENCE", "EXPERIENCE"), "name": "+%s XP" % n, "stats": stats,
		"note": Lang.t("XP calculée à ton niveau actuel", "XP worked out at your current level")}


## Part du niveau atteinte avec `total_xp` (0..1).
static func progress(total_xp: int) -> float:
	var l := PlayerProfile.level_for_xp(total_xp)
	if l >= PlayerProfile.MAX_LEVEL:
		return 1.0
	return clampf(float(total_xp - PlayerProfile.xp_for_level(l)) / float(PlayerProfile.xp_to_next(l)), 0.0, 1.0)


## Tuiles d'une récompense : l'objet (aperçu exact : `item`, sinon d'après
## `reward`) puis l'XP (si `xp` > 0).
static func reward_tiles(pr: PlayerProfile, reward: Dictionary, item: RefCounted, xp: int, xp_detail: bool) -> Array:
	var out := []
	if item is OwnedWeapon:
		out.append(weapon_tile(item))
	elif reward.get("kind") == "part":
		out.append(part_tile(String(reward.get("quality", quality_of_mods(reward.get("mods", {})))), pr.level()))
	if xp > 0:
		out.append(xp_tile(pr, xp, xp_detail))
	return out


# --- Délais -------------------------------------------------------------------

## Contrat en cours : « encore 2 j », « dernier jour » ; "" : sans fin.
static func time_left(days: int) -> String:
	if days < 0:
		return ""
	if days == 0:
		return Lang.t("dernier jour", "last day")
	return Lang.t("encore %d j", "%d d left") % days


## Proposition : « 4 j », « < 1 j » ; "" : sans fin.
static func offer_time(days: int) -> String:
	if days < 0:
		return ""
	if days == 0:
		return Lang.t("< 1 j", "< 1 d")
	return Lang.t("%d j", "%d d") % days


# --- Contrats prêts, histoire ----------------------------------------------------

## Contrats prêts à remettre : étape d'histoire (0 ou 1) + temporaires.
static func ready_total(pr: PlayerProfile) -> int:
	if pr == null:
		return 0
	return (1 if StoryRules.is_ready(pr) else 0) + HubContractsView.ready_count(pr)


## « Histoire · chapitre 2, étape 3 sur 5 » ; histoire finie : « Histoire
## terminée · la suite bientôt ».
static func story_line(pr: PlayerProfile) -> String:
	var s := StoryRules.current(pr)
	if s.is_empty():
		return Lang.t("Histoire terminée · la suite bientôt", "Story complete · more soon")
	var loc := StoryRules.data().locate(s.id)
	return Lang.t("Histoire · chapitre %d, étape %d sur %d", "Story · chapter %d, step %d of %d") % [
		int(loc.chapter_index) + 1, int(loc.step_index) + 1, int(loc.count)]


## Réplique de Dr Brown au LABO selon la situation (sans guillemets) :
## contrat expiré, étape d'histoire prête, contrat temporaire prêt, retour
## de partie, nouveau venu, étape en cours (niveau requis, réplique de
## l'étape), histoire finie, sinon une réplique d'accueil.
static func lab_line(pr: PlayerProfile, expired: PackedStringArray, last_match: Dictionary) -> String:
	if not expired.is_empty():
		return Lang.t("Trop tard pour « %s » : le contrat a expiré. La science n’attend pas, elle pourrit." % expired[0],
				"Too late for “%s”: the contract has expired. Science doesn't wait, it rots." % expired[0])
	var s := StoryRules.current(pr)
	if not s.is_empty() and StoryRules.is_ready(pr):
		var r := HubData.text_of(s.get("ready", {}))
		return r if r != "" else Lang.t("L’étape est terminée ? Passez au bureau des contrats, j’ai de quoi vous remercier.",
				"Step done? Come by the contracts desk, I have something to thank you with.")
	if HubContractsView.ready_count(pr) > 0:
		return Lang.t("Un contrat est prêt, je le sens d’ici. Posez vos échantillons sur la paillasse… doucement.",
				"A contract is ready, I can smell it from here. Put your samples on the bench… gently.")
	if not last_match.is_empty() and last_match.get("result") is MatchResult:
		if (last_match.result as MatchResult).evacuated:
			return Lang.t("Évacuation réussie ! Montrez-moi ce que vous avez ramené. Non, pas la boue.",
					"Extraction successful! Show me what you brought back. No, not the mud.")
		return Lang.t("Le butin est resté là-bas, mais vous êtes revenu. Enfin, presque entier.",
				"The loot stayed down there, but you came back. Well, almost in one piece.")
	if pr.xp == 0 and pr.weapons.is_empty():
		return Lang.t("Ah, un volontaire ! Ne touchez à rien, surtout pas au bocal qui bouge.",
				"Ah, a volunteer! Don't touch anything, especially the jar that moves.")
	if s.is_empty():
		return Lang.t("L’antidote marche sur les rats. Pour la suite, je réfléchis. Revenez me voir.",
				"The antidote works on rats. I'm thinking about what comes next. Come back and see me.")
	if pr.level() < int(s.min_level):
		return Lang.t("La suite est trop dangereuse pour vous. Revenez au niveau %d, avec tous vos membres." % int(s.min_level),
				"What comes next is too dangerous for you. Come back at level %d, with all your limbs." % int(s.min_level))
	var lab := HubData.text_of(s.get("lab", {}))
	return lab if lab != "" else Lang.t("Vous revoilà, entier en plus. Je note ça dans le registre des miracles.",
			"You're back, in one piece too. I'm writing that down in the book of miracles.")


## Réplique entre guillemets (« … » en français, “…” en anglais).
static func quoted(t: String) -> String:
	return Lang.t("« %s »" % t, "“%s”" % t)
