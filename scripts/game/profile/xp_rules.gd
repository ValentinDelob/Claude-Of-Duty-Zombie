class_name XpRules
extends RefCounted
## Barème de l'XP (GAME_CONCEPT §4.15 ; référence : docs/XP_RULES.md).
## Fonctions pures, testées par tests/test_xp_rules.gd ; calibrage :
## XpCalibration.
##
## Sources d'XP d'une partie :
## * élimination : barème du TYPE d'ennemi (ENEMIES), au seul joueur qui
##   porte le coup fatal (comme la ferraille, rien pour les assistances) ;
## * manche survécue : à chaque joueur non mort à la fin de la manche ;
## * vague spéciale ou de boss vaincue : à chaque joueur non mort ;
## * évacuation réussie : bonus en pourcentage de l'XP de la partie du joueur.
## L'XP d'élimination et de vague est multipliée par le BONUS DE MANCHE
## (+15 % par manche après la première, plafonné à ×5) : survivre plus
## longtemps rapporte plus (§1, pilier 1). Les contrats (§4.2) viendront plus
## tard (XP du contrat ajoutée au profil au hub, hors partie).
##
## L'XP est comptée PENDANT la partie, par joueur, par le serveur (XpSystem),
## dans un « relevé » (ledger, Dictionary sérialisable) envoyé au joueur ; elle
## est ajoutée UNE fois au profil à la fin de la partie, quelle que soit
## l'issue (MatchXp.apply, §4.6 : l'XP est toujours gardée).

# --------------------------------------------------------------------------
# Catégories et types d'ennemis
# --------------------------------------------------------------------------

## Catégories d'ennemis (méthode pour un nouveau mob : docs/XP_RULES.md §5).
const COMMON := "common"      # zombies des manches normales
const SPECIAL := "special"    # ennemis en groupe des vagues spéciales (meute)
const MINIBOSS := "miniboss"  # ennemi seul et fort d'une vague spéciale
const BOSS := "boss"          # ennemi des vagues de boss

## Fourchette d'XP de base autorisée par catégorie [min, max] : tout nouveau
## mob doit y tomber (vérifié par test_xp_rules.gd).
const CATEGORY_RANGE := {
	COMMON: [2, 8],
	SPECIAL: [8, 30],
	MINIBOSS: [40, 120],
	BOSS: [150, 600],
}

## Types d'ennemis connus.
const WALKER := "walker"
const RUNNER := "runner"
const SPRINTER := "sprinter"
const CRAWLER := "crawler"
const DOG := "dog"
## Valeurs de référence des catégories sans ennemi réel aujourd'hui (aucun
## mini-boss ni boss n'existe encore) : un vrai mini-boss ou boss aura son
## propre identifiant, avec cette valeur comme point de départ.
const MINIBOSS_GENERIC := "miniboss"
const BOSS_GENERIC := "boss"

## Barème : type -> {category, xp (XP de base, manche 1), fr, en (nom au
## pluriel de l'écran de fin)}. Ordre = ordre d'affichage.
const ENEMIES := {
	WALKER: {"category": COMMON, "xp": 4, "fr": "Marcheurs", "en": "Walkers"},
	RUNNER: {"category": COMMON, "xp": 4, "fr": "Coureurs", "en": "Runners"},
	SPRINTER: {"category": COMMON, "xp": 4, "fr": "Sprinteurs", "en": "Sprinters"},
	CRAWLER: {"category": COMMON, "xp": 4, "fr": "Rampants", "en": "Crawlers"},
	DOG: {"category": SPECIAL, "xp": 12, "fr": "Chiens", "en": "Dogs"},
	MINIBOSS_GENERIC: {"category": MINIBOSS, "xp": 60, "fr": "Mini-boss", "en": "Mini-bosses"},
	BOSS_GENERIC: {"category": BOSS, "xp": 240, "fr": "Boss", "en": "Bosses"},
}

# --------------------------------------------------------------------------
# Autres sources et bonus
# --------------------------------------------------------------------------

## Bonus de manche : +15 % de l'XP d'élimination et de vague par manche après
## la première, plafonné à ×5 (atteint à la manche 28) : un marcheur rapporte
## 4 XP à la manche 1, 9 à la 10, 15 à la 20, 20 à partir de la 28.
const ROUND_BONUS := 0.15
const ROUND_BONUS_CAP := 5.0
## Manche survécue : XP_PER_ROUND × numéro de la manche (manche 10 : 30 XP).
const XP_PER_ROUND := 3
## Vague vaincue (avant bonus de manche) : WaveRules.SPECIAL / BOSS.
const WAVE_XP := {WaveRules.SPECIAL: 60, WaveRules.BOSS: 240}
## Bonus d'évacuation réussie : +25 % de l'XP de la partie du joueur.
const EVAC_BONUS := 0.25
## Plafond d'un relevé (borne les valeurs reçues du réseau).
const LEDGER_CAP := 1 << 40


## Multiplicateur du bonus de manche (1 à la manche 1, ROUND_BONUS_CAP au plus).
static func round_factor(round_n: int) -> float:
	return minf(1.0 + ROUND_BONUS * float(maxi(round_n, 1) - 1), ROUND_BONUS_CAP)


static func is_enemy(type: String) -> bool:
	return ENEMIES.has(type)


static func category_of(type: String) -> String:
	return String(ENEMIES[type].category) if ENEMIES.has(type) else ""


## XP de base d'un type (0 s'il est inconnu).
static func base_xp(type: String) -> int:
	return int(ENEMIES[type].xp) if ENEMIES.has(type) else 0


## XP d'une élimination d'un ennemi `type` à la manche `round_n`.
static func kill_xp(type: String, round_n: int) -> int:
	return roundi(base_xp(type) * round_factor(round_n))


## XP d'une manche survécue (la manche `round_n`).
static func round_xp(round_n: int) -> int:
	return XP_PER_ROUND * maxi(round_n, 0)


## XP d'une vague spéciale ou de boss vaincue (`kind` : WaveRules.SPECIAL / BOSS).
static func wave_xp(kind: String, round_n: int) -> int:
	return roundi(int(WAVE_XP.get(kind, 0)) * round_factor(round_n))


## Bonus d'évacuation pour une partie qui a rapporté `subtotal` XP.
static func evac_bonus(subtotal: int) -> int:
	return roundi(maxi(subtotal, 0) * EVAC_BONUS)


## Type d'un ennemi d'après l'entité : chien, rampant, sinon classe de
## vitesse du zombie (RoundRules.WALK / RUN / SPRINT ; 1, trot, compté
## « coureur »).
static func enemy_type(is_dog: bool, is_crawler: bool, speed_class: int) -> String:
	if is_dog:
		return DOG
	if is_crawler:
		return CRAWLER
	if speed_class >= RoundRules.SPRINT:
		return SPRINTER
	if speed_class > RoundRules.WALK:
		return RUNNER
	return WALKER


# --------------------------------------------------------------------------
# Relevé d'XP d'un joueur pour une partie (Dictionary sérialisable)
# --------------------------------------------------------------------------
# {"kills": {type: nombre}, "kill_xp": {type: XP}, "rounds": n, "round_xp": XP,
#  "waves": {kind: nombre}, "wave_xp": XP, "evac_bonus": XP, "closed": bool}

static func new_ledger() -> Dictionary:
	return {"kills": {}, "kill_xp": {}, "rounds": 0, "round_xp": 0, "waves": {}, "wave_xp": 0,
		"evac_bonus": 0, "closed": false}


## Compte une élimination ; rend l'XP gagnée (0 : type inconnu ou relevé clos).
static func add_kill(l: Dictionary, type: String, round_n: int) -> int:
	if l.get("closed", false) or not is_enemy(type):
		return 0
	var xp := kill_xp(type, round_n)
	l.kills[type] = int(l.kills.get(type, 0)) + 1
	l.kill_xp[type] = int(l.kill_xp.get(type, 0)) + xp
	return xp


## Compte une manche survécue ; rend l'XP gagnée.
static func add_round(l: Dictionary, round_n: int) -> int:
	if l.get("closed", false):
		return 0
	var xp := round_xp(round_n)
	l.rounds = int(l.rounds) + 1
	l.round_xp = int(l.round_xp) + xp
	return xp


## Compte une vague spéciale ou de boss vaincue ; rend l'XP gagnée.
static func add_wave(l: Dictionary, kind: String, round_n: int) -> int:
	if l.get("closed", false) or not WAVE_XP.has(kind):
		return 0
	var xp := wave_xp(kind, round_n)
	l.waves[kind] = int(l.waves.get(kind, 0)) + 1
	l.wave_xp = int(l.wave_xp) + xp
	return xp


## Clôt le relevé à la fin de la partie (une seule fois) : bonus d'évacuation
## si `evacuated`. Rend le bonus ajouté.
static func close(l: Dictionary, evacuated: bool) -> int:
	if l.get("closed", false):
		return 0
	l.closed = true
	l.evac_bonus = evac_bonus(subtotal(l)) if evacuated else 0
	return int(l.evac_bonus)


## XP des éliminations (tous types).
static func kills_xp(l: Dictionary) -> int:
	var t := 0
	for k in l.get("kill_xp", {}):
		t += int(l.kill_xp[k])
	return t


## Nombre d'éliminations (tous types).
static func kill_count(l: Dictionary) -> int:
	var t := 0
	for k in l.get("kills", {}):
		t += int(l.kills[k])
	return t


## XP avant le bonus d'évacuation.
static func subtotal(l: Dictionary) -> int:
	return kills_xp(l) + int(l.get("round_xp", 0)) + int(l.get("wave_xp", 0))


## XP totale du relevé.
static func total(l: Dictionary) -> int:
	return subtotal(l) + int(l.get("evac_bonus", 0))


## Relevé lu depuis le réseau (types vérifiés, valeurs bornées, types
## d'ennemis et de vagues inconnus écartés).
static func clean_ledger(v: Variant) -> Dictionary:
	var l := new_ledger()
	if not v is Dictionary:
		return l
	var d: Dictionary = v
	for key in ["kills", "kill_xp"]:
		var m: Variant = d.get(key)
		if m is Dictionary:
			for t in m:
				if (t is String or t is StringName) and is_enemy(String(t)):
					l[key][String(t)] = _int(m[t])
	var w: Variant = d.get("waves")
	if w is Dictionary:
		for k in w:
			if (k is String or k is StringName) and WAVE_XP.has(String(k)):
				l.waves[String(k)] = _int(w[k])
	for key in ["rounds", "round_xp", "wave_xp", "evac_bonus"]:
		l[key] = _int(d.get(key, 0))
	var c: Variant = d.get("closed", false)
	l.closed = c is bool and c
	return l


static func _int(v: Variant) -> int:
	return ProfileValues.to_int(v, 0, 0, LEDGER_CAP)


## Lignes du détail de l'écran de fin (langue du joueur) : éliminations par
## type, manches, vagues, bonus d'évacuation.
static func breakdown(l: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for t in ENEMIES:
		var n := int(l.get("kills", {}).get(t, 0))
		if n > 0:
			out.append(Lang.t("%s ×%d : +%d XP", "%s ×%d: +%d XP") % [Lang.t(ENEMIES[t].fr, ENEMIES[t].en), n,
					int(l.kill_xp.get(t, 0))])
	if int(l.get("rounds", 0)) > 0:
		out.append(Lang.t("Manches survécues ×%d : +%d XP", "Rounds survived ×%d: +%d XP") % [int(l.rounds), int(l.round_xp)])
	var waves: Dictionary = l.get("waves", {})
	var nw := 0
	for k in waves:
		nw += int(waves[k])
	if nw > 0:
		out.append(Lang.t("Vagues vaincues ×%d : +%d XP", "Waves cleared ×%d: +%d XP") % [nw, int(l.wave_xp)])
	if int(l.get("evac_bonus", 0)) > 0:
		out.append(Lang.t("Bonus d'évacuation : +%d XP", "Evacuation bonus: +%d XP") % int(l.evac_bonus))
	return out
