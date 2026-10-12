class_name CodexDetails
extends RefCounted
## Page DÉTAILS d'une carte du bestiaire (CODEX du hub v2, demande du
## 2026-10-12) : ce que l'ennemi te fait, sa résistance, quand il apparaît,
## ce qu'il rapporte, son butin, son point faible et un conseil. Pour les
## joueurs (phrases simples), pas une fiche technique. Pur, sans interface ;
## tests/test_codex_details.gd.
##
## TOUS les chiffres sont lus dans les règles du jeu (jamais recopiés ici) :
## dégâts (Combat, DogRules, BrancardRules, NurseRules, SurgeonRules), santé
## du joueur (PlayerData), PV (RoundRules et facteurs des règles des
## mini-boss), manches (codex.json, WaveRules : rythme par défaut), XP
## (XpRules), ferraille (PointsRules), échantillons, pièces et armes
## (LootRules). Les textes du point faible et du conseil viennent de
## codex.json (« weak », « tip », sans chiffre).
##
## Carte inconnue : page verrouillée ({locked: true, hint}) : « Rencontre-le
## pour en savoir plus. »
##
## Résultat de of() : {locked, hint, sections: [{id, title, rows: [{id,
## label, value, note, tone, sample}], text}]}. `tone` : "bad" (dégâts),
## "xp", "loot", "" ; `sample` : sorte d'échantillon (ligne avec rendu).

## Identifiants des sections, dans l'ordre d'affichage.
const ATTACKS := "attacks"
const TOUGH := "tough"
const WHEN := "when"
const REWARDS := "rewards"
const LOOT := "loot"
const WEAK := "weak"
const TIP := "tip"

## Carte -> type de vague spéciale (WaveRules.SPECIAL_TYPES) ou de boss
## (WaveRules.BOSS_TYPES) : manches de ses vagues au rythme par défaut.
const SPECIAL_WAVE := {"dog": WaveRules.MEUTE, "brancardier": WaveRules.BRANCARDIER, "nurse": WaveRules.INFIRMIERE}
const BOSS_WAVE := {"surgeon": WaveRules.CHIRURGIEN}
## Manches montrées pour une vague (« 5, 25, 45… »).
const ROUNDS_SHOWN := 3


## Page de la carte `card` (CodexData.cards()) ; `known` : rencontrée ;
## `kills` : éliminations du joueur.
static func of(card: Dictionary, known: bool, kills: int) -> Dictionary:
	if card.is_empty():
		return {"locked": true, "hint": "", "sections": []}
	if not known:
		return {"locked": true, "hint": CodexData.round_hint(int(card.get("round", 1))), "sections": []}
	var kind := kind_of(card)
	var sections: Array = []
	_add(sections, ATTACKS, Lang.t("CE QU’IL TE FAIT", "WHAT IT DOES TO YOU"), attacks(kind))
	_add(sections, TOUGH, Lang.t("RÉSISTANCE", "TOUGHNESS"), toughness(kind, card))
	_add(sections, WHEN, Lang.t("QUAND IL APPARAÎT", "WHEN IT SHOWS UP"), when_rows(kind, card))
	_add(sections, REWARDS, Lang.t("CE QU’IL RAPPORTE", "WHAT IT’S WORTH"), rewards(card, kills))
	_add(sections, LOOT, Lang.t("BUTIN", "LOOT"), loot(kind, card))
	var weak := HubData.text_of(card.get("weak", {})) if not (card.get("weak", {}) as Dictionary).is_empty() else ""
	var weak_rows := weak_points(kind)
	if weak != "" or not weak_rows.is_empty():
		sections.append({"id": WEAK, "title": Lang.t("POINT FAIBLE", "WEAK POINT"), "rows": weak_rows, "text": weak})
	if not (card.get("tip", {}) as Dictionary).is_empty():
		sections.append({"id": TIP, "title": Lang.t("CONSEIL", "TIP"), "rows": [], "text": HubData.text_of(card.tip)})
	return {"locked": false, "hint": "", "sections": sections}


static func _add(sections: Array, id: String, title: String, rows: Array) -> void:
	if not rows.is_empty():
		sections.append({"id": id, "title": title, "rows": rows, "text": ""})


## Sorte de la carte : "zombies" (ennemis ordinaires, catégorie COMMON), sinon
## son identifiant (dog, brancardier, nurse, surgeon ; un ennemi sans règles
## ici n'a que ses récompenses et son butin).
static func kind_of(card: Dictionary) -> String:
	if String(card.get("category", "")) == XpRules.COMMON:
		return "zombies"
	return String(card.get("id", ""))


static func row(id: String, label: String, value: String, note := "", tone := "") -> Dictionary:
	return {"id": id, "label": label, "value": value, "note": note, "tone": tone, "sample": ""}


# --------------------------------------------------------------------------
# Ce qu'il te fait
# --------------------------------------------------------------------------

## Lignes des attaques : dégâts par coup, effets.
static func attacks(kind: String) -> Array:
	match kind:
		"zombies":
			return [row("claw", Lang.t("Coup de griffes", "Claw swipe"), damage(Combat.ZOMBIE_DAMAGE), hits_note(Combat.ZOMBIE_DAMAGE), "bad")]
		"dog":
			return [row("bite", Lang.t("Morsure", "Bite"), damage(DogRules.BITE_DAMAGE), hits_note(DogRules.BITE_DAMAGE), "bad"),
				row("burst", Lang.t("Sang contaminé à sa mort", "Infected blood when it dies"), damage(DogRules.EXPLODE_DAMAGE),
					Lang.t("si tu es tout près de lui", "if you’re right next to it"), "bad")]
		"brancardier":
			return [row("charge", Lang.t("Charge", "Charge"), damage(BrancardRules.CHARGE_DAMAGE),
					Lang.t("et il te projette", "and he sends you flying"), "bad"),
				row("smash", Lang.t("Coup des deux poings", "Double-fist smash"), damage(BrancardRules.SMASH_DAMAGE),
					hits_note(BrancardRules.SMASH_DAMAGE), "bad")]
		"nurse":
			return [row("scream", Lang.t("Cri", "Scream"), damage(NurseRules.SCREAM_DAMAGE),
					Lang.t("t’étourdit jusqu’à %s et ameute les zombies alentour", "dazes you for up to %s and calls nearby zombies")
					% secs(NurseRules.DAZE_TIME_MAX), "bad"),
				row("stab", Lang.t("Coup de seringue", "Syringe stab"), damage(NurseRules.STAB_DAMAGE),
					Lang.t("seulement quand elle est acculée", "only when she’s cornered"), "bad")]
		"surgeon":
			return [row("slash", Lang.t("Combo au scalpel", "Scalpel combo"),
					"%d × %s" % [SurgeonRules.SLASH_HITS, damage(SurgeonRules.SLASH_DAMAGE)],
					Lang.t("%d coups une fois enragé", "%d hits once enraged") % SurgeonRules.RAGE_SLASH_HITS, "bad"),
				row("throw", Lang.t("Scalpels lancés", "Thrown scalpels"),
					Lang.t("%s chacun", "%s each") % damage(SurgeonRules.THROW_DAMAGE),
					Lang.t("%d par salve, %d une fois enragé", "%d per volley, %d once enraged")
					% [SurgeonRules.THROW_COUNT, SurgeonRules.RAGE_THROW_COUNT], "bad"),
				row("shock", Lang.t("Onde de choc", "Shockwave"), damage(SurgeonRules.SHOCK_DAMAGE),
					Lang.t("quand il s’enrage, à %s de sa vie : elle te projette", "when he enrages, at %s health: it knocks you back")
					% pct(SurgeonRules.ENRAGE_AT), "bad")]
	return []


## « 50 dégâts ».
static func damage(n: int) -> String:
	return Lang.t("%s dégâts", "%s damage") % num(n)


## Coups avant d'être à terre, santé de base du joueur (PlayerData).
static func hits_to_down(dmg: int) -> int:
	return ceili(float(PlayerData.BASE_HEALTH) / float(maxi(dmg, 1)))


static func hits_note(dmg: int) -> String:
	var n := hits_to_down(dmg)
	if n <= 1:
		return Lang.t("un seul coup et tu es à terre", "one hit and you’re down")
	return Lang.t("%d coups et tu es à terre", "%d hits and you’re down") % n


# --------------------------------------------------------------------------
# Résistance
# --------------------------------------------------------------------------

## « Encaisse comme 10 zombies » : facteur de PV face à un zombie de la même
## manche (règles des mini-boss et du boss ; meute : PV de la première meute
## face à un zombie de sa manche).
static func toughness(kind: String, card: Dictionary) -> Array:
	match kind:
		"zombies":
			var first := RoundRules.zombie_health(1)
			return [row("hp", Lang.t("À la première manche", "In the first round"), Lang.t("%s PV", "%s HP") % num(first),
					Lang.t("la référence : les autres se comparent à lui", "the yardstick: everything else is compared to it")),
				row("growth", Lang.t("À chaque manche", "Every round"),
					Lang.t("+%s PV", "+%s HP") % num(RoundRules.zombie_health(2) - first),
					Lang.t("sans limite : vise la tête", "no cap: aim for the head"))]
		"dog":
			var f := float(DogRules.dog_health(1)) / float(RoundRules.zombie_health(int(card.get("round", 1))))
			return [row("hp", Lang.t("Encaisse", "Takes"), as_zombies(f),
					Lang.t("plus solides à chaque nouvelle meute", "tougher with every new pack"))]
		"brancardier":
			return [row("hp", Lang.t("Encaisse", "Takes"), as_zombies(BrancardRules.HP_FACTOR), growth_note(BrancardRules.HP_GROWTH))]
		"nurse":
			return [row("hp", Lang.t("Encaisse", "Takes"), as_zombies(NurseRules.HP_FACTOR), growth_note(NurseRules.HP_GROWTH))]
		"surgeon":
			return [row("hp", Lang.t("Encaisse", "Takes"), as_zombies(SurgeonRules.HP_FACTOR), growth_note(SurgeonRules.HP_GROWTH)),
				row("players", Lang.t("Par joueur en plus", "Per extra player"), "+" + pct(SurgeonRules.PLAYER_HP),
					Lang.t("de vie : il est seul contre toute l’équipe", "health: he takes on the whole team alone"))]
	return []


## « comme 10 zombies » ; moins d'un : « moins qu'un zombie ».
static func as_zombies(f: float) -> String:
	if f < 0.95:
		return Lang.t("moins qu’un zombie", "less than a zombie")
	var n := roundi(f)
	if n <= 1:
		return Lang.t("comme un zombie", "like one zombie")
	return Lang.t("comme %d zombies", "like %d zombies") % n


static func growth_note(g: float) -> String:
	return Lang.t("de sa manche ; +%s à chaque retour", "of its round; +%s every time it returns") % pct(g)


# --------------------------------------------------------------------------
# Quand il apparaît
# --------------------------------------------------------------------------

static func when_rows(kind: String, card: Dictionary) -> Array:
	var first := int(card.get("round", 1))
	if kind == "zombies":
		return [row("rounds", Lang.t("Manches normales", "Normal rounds"), Lang.t("toutes", "all of them"),
				Lang.t("plus nombreux à chaque manche", "more of them every round")),
			row("runners", Lang.t("Coureurs", "Runners"), Lang.t("dès la manche %d", "from round %d") % RoundRules.RUNNERS_FROM_ROUND,
				Lang.t("avant, ils ne font que marcher", "before that, they only walk"))]
	var sched := WaveRules.default_schedule()
	var boss := WaveRules.has_boss(sched)
	var rounds := PackedInt32Array()
	if SPECIAL_WAVE.has(kind):
		var r := 0
		for i in ROUNDS_SHOWN:
			r = WaveRules.next_special_of(sched, String(SPECIAL_WAVE[kind]), r, boss)
			if r <= 0:
				break
			rounds.append(r)
	elif BOSS_WAVE.has(kind):
		var r := 0
		for i in ROUNDS_SHOWN:
			r = WaveRules.next_boss_of(sched, String(BOSS_WAVE[kind]), r)
			if r <= 0:
				break
			rounds.append(r)
	var out: Array = []
	var wave := Lang.t("Vague de boss", "Boss wave") if String(card.get("category", "")) == XpRules.BOSS \
			else Lang.t("Vague spéciale", "Special wave")
	if rounds.is_empty():
		out.append(row("wave", wave, Lang.t("dès la manche %d", "from round %d") % first))
	else:
		var parts := PackedStringArray()
		for r in rounds:
			parts.append(str(r))
		out.append(row("wave", wave, Lang.t("manches %s…", "rounds %s…") % ", ".join(parts),
				Lang.t("rythme habituel ; chaque carte peut avoir le sien", "usual rhythm; each map may have its own")))
	match kind:
		"dog":
			out.append(row("pack", Lang.t("Taille de la meute", "Pack size"),
					Lang.t("%d chiens par joueur", "%d dogs per player") % DogRules.PER_PLAYER_EARLY,
					Lang.t("puis %d à partir de la troisième meute", "then %d from the third pack on") % DogRules.PER_PLAYER_LATE))
		"brancardier":
			out.append(row("escort", Lang.t("Escorte", "Escort"), Lang.t("%d zombies par joueur", "%d zombies per player") % BrancardRules.ESCORT_PER_PLAYER))
		"nurse":
			out.append(row("escort", Lang.t("Escorte", "Escort"), Lang.t("%d zombies par joueur", "%d zombies per player") % NurseRules.ESCORT_PER_PLAYER))
		"surgeon":
			out.append(row("escort", Lang.t("Escorte", "Escort"), Lang.t("%d zombies par joueur", "%d zombies per player") % SurgeonRules.ESCORT_PER_PLAYER,
					Lang.t("et il relève %d patients par joueur en opérant", "and he raises %d patients per player when operating") % SurgeonRules.SUMMON_PER_PLAYER))
	return out


# --------------------------------------------------------------------------
# Ce qu'il rapporte
# --------------------------------------------------------------------------

static func rewards(card: Dictionary, kills: int) -> Array:
	var xp := xp_text(card)
	return [row("xp", Lang.t("XP par élimination", "XP per kill"), xp,
			Lang.t("+%s par manche passée, jusqu’à ×%s", "+%s per round survived, up to ×%s")
			% [pct(XpRules.ROUND_BONUS), str(roundi(XpRules.ROUND_BONUS_CAP))], "xp"),
		row("scrap_kill", Lang.t("Ferraille par élimination", "Scrap per kill"), num(PointsRules.KILL)),
		row("scrap_hit", Lang.t("Ferraille par touche", "Scrap per hit"), num(PointsRules.HIT),
			Lang.t("pour les %d premières touches", "for the first %d hits") % PointsRules.HIT_CAP),
		row("kills", Lang.t("Tes éliminations", "Your kills"), num(kills))]


# --------------------------------------------------------------------------
# Butin
# --------------------------------------------------------------------------

static func loot(kind: String, card: Dictionary) -> Array:
	var out: Array = []
	var codex := CodexData.default()
	for s in card.get("samples", PackedStringArray()):
		var lr := SampleCatalog.loot_rate(String(s), codex)
		var r := row("sample_" + String(s), SampleCatalog.display_name(String(s)), String(lr.rate), String(lr.note), "loot")
		r.sample = String(s)
		out.append(r)
	var cat := String(card.get("category", ""))
	if cat == XpRules.COMMON:
		out.append(row("none", Lang.t("Échantillons, pièces, armes", "Samples, parts, weapons"), Lang.t("aucun", "none"),
				Lang.t("seulement pendant les vagues spéciales et de boss", "only during special and boss waves")))
		return out
	var boss := cat == XpRules.BOSS
	out.append(row("part", Lang.t("Pièce d’arme", "Weapon part"), pct(LootRules.PART_CHANCE),
			Lang.t("par ennemi tué pendant sa vague", "per enemy killed during its wave"), "loot"))
	var wave := WaveRules.BOSS if boss else WaveRules.SPECIAL
	var n := LootRules.weapons_for_wave(wave)
	var w := LootRules.rarity_weights(wave)
	var top := 0.0
	for i in range(3, w.size()):
		top += float(w[i])
	out.append(row("weapon", Lang.t("Armes", "Weapons"),
			Lang.t("%d par joueur", "%d per player") % n,
			Lang.t("à la fin de la vague ; légendaire ou mieux : %s", "when the wave ends; legendary or better: %s") % pct(top / 100.0), "loot"))
	return out


# --------------------------------------------------------------------------
# Point faible
# --------------------------------------------------------------------------

## Lignes chiffrées du point faible (le texte vient de codex.json).
static func weak_points(kind: String) -> Array:
	match kind:
		"brancardier":
			return [row("stun", Lang.t("Percute un mur en chargeant", "Rams a wall while charging"),
					Lang.t("sonné %s", "dazed %s") % secs(BrancardRules.STUN_TIME))]
		"nurse":
			return [row("choke", Lang.t("Touchée à la gorge pendant l’inspiration", "Hit in the throat mid-breath"),
					Lang.t("cri annulé, %s immobile", "scream cancelled, %s frozen") % secs(NurseRules.CHOKE_TIME))]
		"surgeon":
			return [row("rage", Lang.t("Enragé", "Enraged"), Lang.t("à %s de sa vie", "at %s health") % pct(SurgeonRules.ENRAGE_AT),
					Lang.t("plus rapide et plus de coups : garde des munitions", "faster, more hits: keep some ammo"))]
	return []


# --------------------------------------------------------------------------
# Nombres
# --------------------------------------------------------------------------

## Entier avec séparateur de milliers (espace insécable ; anglais : virgule),
## comme les nombres du hub (Hub2Style.num).
static func num(n: int) -> String:
	var s := str(absi(n))
	var sep := "," if Lang.is_en() else String.chr(0xA0)
	var out := ""
	while s.length() > 3:
		out = sep + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## XP de base d'une élimination (XpRules) : « 4 » ou « 1 à 3 ».
static func xp_text(card: Dictionary) -> String:
	var lo := int(card.get("xp_min", 0))
	var hi := int(card.get("xp_max", 0))
	if lo == hi:
		return num(hi)
	return Lang.t("%s à %s", "%s to %s") % [num(lo), num(hi)]


## Pourcentage d'une fraction, une décimale au plus : « 5 % », « 7,5 % »
## (anglais : « 7.5% »).
static func pct(f: float) -> String:
	var v := snappedf(f * 100.0, 0.1)
	var s := str(roundi(v)) if is_equal_approx(v, roundf(v)) else String.num(v, 1)
	if Lang.is_en():
		return s + "%"
	return s.replace(".", ",") + String.chr(0xA0) + "%"


## Durée en secondes : « 3 s », « 1,2 s ».
static func secs(f: float) -> String:
	var s := str(roundi(f)) if is_equal_approx(f, roundf(f)) else String.num(f, 1)
	if Lang.is_en():
		return s + " s"
	return s.replace(".", ",") + String.chr(0xA0) + "s"
