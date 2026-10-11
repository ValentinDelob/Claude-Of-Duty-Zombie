class_name Hub2RecapModel
extends RefCounted
## Données du récapitulatif d'après partie du hub v2 (docs/hub_v2/Recap.dc.html),
## sans interface (tests/test_hub2_recap.gd) : en-tête (carte, ÉVACUÉ ou
## défaite, manche, zombies, durée), XP gagnée et passages de niveau
## (animation : XP du profil avant la partie -> après), détail de l'XP par
## catégorie du relevé (XpRules), ce que débloque le nouveau niveau, butin
## gardé ou perdu (§4.16), contrat prêt à remettre, règle des cartes perso
## (ProgressGate : aucune progression).
##
## Source : Router.last_match ({result: MatchResult, map, map_id, progress,
## challenge, solo}, rempli par Game._show_match_end) et le profil enregistré.

## Animation de l'XP (maquette) : départ après 0,7 s, 3,8 s, ease-out cubique.
const XP_DELAY := 0.7
const XP_DURATION := 3.8

var map_name := ""
var map_id := ""
var evacuated := false
var round_reached := 0
var kills := 0
var duration_sec := 0.0
## Partie qui fait progresser le profil (faux : carte perso).
var progress := true
## Défi de la semaine (butin jamais gardé).
var challenge := false
## XP totale du profil avant / après, XP gagnée (partie + récompense du défi).
var xp_start := 0
var xp_end := 0
var gained := 0
var level_before := 1
var level_after := 1
## Détail : [{key, label, xp}] (catégories du relevé, XP > 0).
var rows: Array = []
## Butin : gardé ? armes [{id, name, lvl, rarity, new}], échantillons [{id,
## name, qty}], pièces (nombre).
var kept := false
var weapons: Array = []
var samples: Array = []
var parts := 0
## Contrat prêt à remettre (titre ; "" : aucun).
var contract_ready := ""
## Débloqué par le(s) nouveau(x) niveau(x) ("" : rien, pas de passage).
var unlocked := ""


## Remplit le modèle depuis le dernier résultat (Router.last_match) et le
## profil `pr` (après la partie). (Méthode d'instance : une fonction statique
## qui créerait sa propre classe garderait le script en vie à la sortie.)
func read(last: Dictionary, pr: PlayerProfile) -> Hub2RecapModel:
	var m := self
	var r: MatchResult = last.get("result") if last.get("result") is MatchResult else MatchResult.new()
	m.map_id = String(last.get("map_id", ""))
	var def := HubMaps.def_of(m.map_id) if m.map_id != "" else null
	m.map_name = Hub2PlayData.map_title(def) if def else String(last.get("map", ""))
	m.evacuated = r.evacuated
	m.round_reached = r.round_reached
	m.kills = r.kills
	m.duration_sec = r.duration_sec
	m.progress = bool(last.get("progress", true)) and r.loot.get("custom", false) != true
	m.challenge = bool(last.get("challenge", false)) or r.loot.get("challenge") is Dictionary
	var weekly_xp := 0
	var ch: Variant = r.loot.get("challenge")
	if ch is Dictionary and (ch as Dictionary).get("rewarded", false) == true:
		weekly_xp = int((ch as Dictionary).get("xp", 0))
	m.gained = maxi(r.xp + weekly_xp, 0) if m.progress else 0
	m.xp_end = maxi(r.profile_xp, 0)
	if m.xp_end == 0 and pr:
		m.xp_end = pr.xp
	m.xp_start = maxi(m.xp_end - m.gained, 0)
	m.level_before = PlayerProfile.level_for_xp(m.xp_start)
	m.level_after = PlayerProfile.level_for_xp(m.xp_end)
	m.rows = ledger_rows(r.xp_ledger, weekly_xp) if m.progress else []
	m.kept = r.loot.get("kept", false) == true and m.progress
	var ws: Variant = r.loot.get("weapons", [])
	if ws is Array:
		for w in ws:
			if w is Array and w.size() >= 3 and WeaponDB.exists(String(w[0])):
				m.weapons.append({"id": String(w[0]), "name": WeaponDB.display_name(String(w[0])).to_upper(),
					"lvl": clampi(int(w[1]), 1, PlayerProfile.MAX_LEVEL), "rarity": clampi(int(w[2]), 0, 4),
					"new": w.size() < 4 or w[3] == true})
	var ss: Variant = r.loot.get("samples", {})
	if ss is Dictionary:
		var keys: Array = (ss as Dictionary).keys()
		keys.sort_custom(func(a, b): return sample_order(String(a)) < sample_order(String(b)))
		for k in keys:
			var n := int(ss[k])
			if n > 0:
				m.samples.append({"id": String(k), "name": LootRules.sample_name(String(k)), "qty": n})
	m.parts = maxi(int(r.loot.get("parts", 0)), 0)
	if pr and m.progress:
		# Étape d'histoire prête d'abord (StoryRules), puis contrat temporaire.
		var st := StoryRules.current(pr)
		if not st.is_empty() and StoryRules.is_ready(pr):
			m.contract_ready = HubData.text_of(st.get("title", {}))
	if pr and m.progress and m.contract_ready == "":
		for c in HubContractsView.active(pr):
			if c.ready:
				m.contract_ready = String(c.title)
				break
	if m.progress and m.level_after > m.level_before:
		m.unlocked = unlock_text(m.level_before, m.level_after)
	return m


## Ordre d'affichage d'un échantillon (LootRules.SAMPLES).
static func sample_order(id: String) -> int:
	var i := 0
	for kind in LootRules.SAMPLES:
		for s in LootRules.SAMPLES[kind]:
			if s[0] == id:
				return i
			i += 1
	return i


## Détail de l'XP (maquette : « Zombies éliminés +2 840 ») depuis le relevé
## XpRules : zombies (ennemis communs), vagues spéciales et boss (ennemis des
## vagues + vagues vaincues), manches survécues, évacuation réussie, défi de
## la semaine (récompense). Catégories à 0 omises.
static func ledger_rows(l: Dictionary, weekly_xp := 0) -> Array:
	var common := 0
	var waves := int(l.get("wave_xp", 0))
	var kx: Variant = l.get("kill_xp", {})
	if kx is Dictionary:
		for t in kx:
			if XpRules.category_of(String(t)) == XpRules.COMMON:
				common += int(kx[t])
			else:
				waves += int(kx[t])
	var out := []
	for e in [["kills", Lang.t("Zombies éliminés", "Zombies killed"), common],
			["waves", Lang.t("Vagues spéciales et boss", "Special and boss waves"), waves],
			["rounds", Lang.t("Manches survécues", "Rounds survived"), int(l.get("round_xp", 0))],
			["evac", Lang.t("Évacuation réussie", "Successful evacuation"), int(l.get("evac_bonus", 0))],
			["weekly", Lang.t("Défi de la semaine", "Weekly challenge"), weekly_xp]]:
		if int(e[2]) > 0:
			out.append({"key": e[0], "label": e[1], "xp": int(e[2])})
	return out


## Ce que débloquent les niveaux `before` + 1 à `after` : armes de ce niveau
## utilisables (équiper, construire : GameWeapon.can_equip), nouveaux
## échanges du labo (ExchangeRules : min_level atteint).
static func unlock_text(before: int, after: int, day := -1) -> String:
	var items := PackedStringArray()
	items.append(Lang.t("Armes de niveau %d utilisables", "Level %d weapons usable") % after)
	var n := new_exchanges(before, after, day)
	if n == 1:
		items.append(Lang.t("1 nouvel échange au labo", "1 new trade at the lab"))
	elif n > 1:
		items.append(Lang.t("%d nouveaux échanges au labo", "%d new trades at the lab") % n)
	else:
		items.append(Lang.t("pièces de niveau %d au butin", "level %d parts in loot") % after)
	return " · ".join(items)


## Échanges du catalogue (dans leurs dates) dont le niveau requis est entre
## `before` + 1 et `after`.
static func new_exchanges(before: int, after: int, day := -1) -> int:
	var d := HubContractsView.data()
	var today := day if day >= 0 else HubContractsView.today()
	var n := 0
	for x in d.exchanges:
		var ml := int(x.get("min_level", 1))
		if ml > before and ml <= after and ContractRules.in_dates(x, today):
			n += 1
	return n


# --------------------------------------------------------------------------
# Animation de l'XP
# --------------------------------------------------------------------------

## ease-out cubique de la maquette : 1 − (1 − x)³.
static func ease_cubic(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


## Avancement de l'XP (0..1) au temps `t` (s depuis l'affichage).
static func xp_progress(t: float) -> float:
	return clampf((t - XP_DELAY) / XP_DURATION, 0.0, 1.0)


## XP affichée « +N XP » au temps `t`.
func gained_at(t: float) -> int:
	return roundi(gained * ease_cubic(xp_progress(t)))


## Niveau, XP dans le niveau et XP du niveau pour une XP totale (barre).
## Niveau maximum : besoin 0 (barre pleine).
static func level_state(total: int) -> Dictionary:
	var lvl := PlayerProfile.level_for_xp(total)
	if lvl >= PlayerProfile.MAX_LEVEL:
		return {"level": lvl, "in": total - PlayerProfile.xp_for_level(lvl), "need": 0}
	return {"level": lvl, "in": total - PlayerProfile.xp_for_level(lvl), "need": PlayerProfile.xp_to_next(lvl)}


## État de l'XP au temps `t` : {level, in, need, gained, levels (passages
## déjà faits), pct (0..1)}.
func state_at(t: float) -> Dictionary:
	var g := gained_at(t)
	var s := level_state(xp_start + g)
	s["gained"] = g
	s["levels"] = int(s.level) - level_before
	s["pct"] = 1.0 if int(s.need) <= 0 else clampf(float(s["in"]) / float(s.need), 0.0, 1.0)
	return s


## XP gagnée (depuis le début) à laquelle chaque passage de niveau arrive :
## [[niveau atteint, XP gagnée]...].
func level_ups() -> Array:
	var out := []
	for lvl in range(level_before + 1, level_after + 1):
		out.append([lvl, PlayerProfile.xp_for_level(lvl) - xp_start])
	return out


## Temps (s depuis l'affichage) où l'XP affichée atteint `g` (premier instant).
func time_of_gain(g: int) -> float:
	if gained <= 0:
		return XP_DELAY
	var target := clampf(float(g) / float(gained), 0.0, 1.0)
	# Inverse de l'ease-out cubique, puis arrondi : recherche par dichotomie
	# sur l'arrondi réel (gained_at).
	var lo := XP_DELAY
	var hi := XP_DELAY + XP_DURATION
	if target <= 0.0:
		return lo
	for i in 40:
		var mid := (lo + hi) * 0.5
		if gained_at(mid) >= g:
			hi = mid
		else:
			lo = mid
	return hi


# --------------------------------------------------------------------------
# Textes
# --------------------------------------------------------------------------

## Titre : « ÉVACUÉ » (turquoise), sinon la défaite (« LA HORDE L'EMPORTE »).
func title() -> String:
	return Lang.t("ÉVACUÉ", "EVACUATED") if evacuated else Lang.t("LA HORDE L’EMPORTE", "THE HORDE WINS")


## « RETOUR AU LABO · BUNKER K-7 ».
func kicker() -> String:
	return "%s · %s" % [Lang.t("RETOUR AU LABO", "BACK AT THE LAB"), map_name.to_upper()]


## Durée « 42:18 » (h:mm:ss au-delà d'une heure).
func duration_text() -> String:
	return MatchResult.time_text(duration_sec)


## « 8 420 / 13 100 » (niveau maximum : XP totale).
static func xp_line(s: Dictionary, total: int) -> String:
	if int(s.need) <= 0:
		return Hub2Style.num(total)
	return "%s / %s" % [Hub2Style.num(int(s["in"])), Hub2Style.num(int(s.need))]


## Titre du bloc du butin : gardé, perdu, ou non gardé (défi, carte perso).
func loot_title() -> String:
	if kept:
		return Lang.t("BUTIN GARDÉ", "LOOT KEPT")
	if not progress or challenge:
		return Lang.t("BUTIN NON GARDÉ", "LOOT NOT KEPT")
	return Lang.t("BUTIN PERDU", "LOOT LOST")


## Nombre total d'échantillons rapportés (ou perdus).
func sample_total() -> int:
	var n := 0
	for s in samples:
		n += int(s.qty)
	return n


## Bloc d'état en bas à droite : [libellé, texte, sorte] ; sorte « ok »
## (turquoise : RIEN DE PERDU), « lost » (rouge : PERDU), « fun » (violet :
## carte perso), « challenge » (défi : butin non gardé).
func outcome() -> Array:
	if not progress:
		return [Lang.t("POUR LE FUN", "JUST FOR FUN"), Lang.t("Carte personnalisée : aucune progression", "Custom map: no progression"), "fun"]
	if challenge:
		return [Lang.t("DÉFI", "CHALLENGE"), Lang.t("Le butin du défi n’est jamais gardé ; l’XP l’est", "Challenge loot is never kept; XP is"), "challenge"]
	if kept:
		return [Lang.t("RIEN DE PERDU", "NOTHING LOST"), Lang.t("Évacuation réussie", "Successful evacuation"), "ok"]
	if lost_text() == "":
		return [Lang.t("RIEN À PERDRE", "NOTHING TO LOSE"), Lang.t("Aucun butin porté ; l’XP est gardée", "No loot carried; XP is kept"), "lost"]
	return [Lang.t("PERDU", "LOST"), lost_text(), "lost"]


## Ce qui est perdu faute d'évacuation (§4.16) : « 3 armes, 9 échantillons,
## 1 pièce » ; "" : rien.
func lost_text() -> String:
	if kept:
		return ""
	var items := PackedStringArray()
	if weapons.size() > 0:
		items.append(Lang.t("%d arme%s", "%d weapon%s") % [weapons.size(), "s" if weapons.size() > 1 else ""])
	var n := sample_total()
	if n > 0:
		items.append(Lang.t("%d échantillon%s", "%d sample%s") % [n, "s" if n > 1 else ""])
	if parts > 0:
		items.append(Lang.t("%d pièce%s", "%d part%s") % [parts, "s" if parts > 1 else ""])
	return ", ".join(items)
