class_name Hub2PlayData
extends RefCounted
## Données de l'écran JOUER du hub v2 (Partie.dc.html, PartieCoop.dc.html),
## sans interface (tests/test_hub2_play.gd) : vagues spéciales et de boss
## d'une carte (pastilles « 5 Meute »), lignes de cartes (nom, sous-titre,
## record), carte du défi de la semaine, fiches des joueurs du salon (PRÊT,
## ping, armes de départ), décompte « N joueurs prêts sur M ».

## Couleur du liseré d'une pastille de vague, par type (maquette : meute
## turquoise, Brancardier bleu, Chirurgien orange, Infirmière violette).
const WAVE_COLORS := {
	WaveRules.MEUTE: Color("4FE3C1"),
	WaveRules.BRANCARDIER: Color("4D9BFF"),
	WaveRules.CHIRURGIEN: Color("FF9A1F"),
	WaveRules.INFIRMIERE: Color("B56CFF"),
}
## Nom court d'un type de vague [FR, EN].
const WAVE_NAMES := {
	WaveRules.MEUTE: ["Meute", "Pack"],
	WaveRules.BRANCARDIER: ["Brancardier", "Stretcher-Bearer"],
	WaveRules.CHIRURGIEN: ["Chirurgien", "Surgeon"],
	WaveRules.INFIRMIERE: ["Infirmière", "Nurse"],
}
## Pastilles affichées au plus (maquette : 4).
const MAX_WAVES := 4
## Manches parcourues pour trouver les premières vagues (garde).
const SCAN_ROUNDS := 400


## Premières vagues spéciales et de boss d'un schéma (WaveRules) :
## [{round, type, kind}] (au plus `count`), dans l'ordre des manches.
static func wave_chips(sched: Dictionary, count := MAX_WAVES) -> Array:
	var out := []
	var boss := WaveRules.has_boss(sched)
	for n in range(1, SCAN_ROUNDS + 1):
		if out.size() >= count:
			break
		var kind := WaveRules.wave_kind(sched, n, boss)
		var t := ""
		if kind == WaveRules.SPECIAL:
			t = WaveRules.special_type_at(sched, n, boss)
		elif kind == WaveRules.BOSS:
			t = WaveRules.boss_type_at(sched, n)
		if t != "":
			out.append({"round": n, "type": t, "kind": kind})
	return out


## Pastilles de la carte `def` (null : aucune).
static func map_waves(def: MapDef) -> Array:
	if def == null:
		return []
	return wave_chips(WaveRules.parse(def.waves))


static func wave_name(type: String) -> String:
	var n: Array = WAVE_NAMES.get(type, [type, type])
	return Lang.t(n[0], n[1])


static func wave_color(type: String) -> Color:
	return WAVE_COLORS.get(type, Hub2Style.TEXT)


# --------------------------------------------------------------------------
# Cartes
# --------------------------------------------------------------------------

## Nom d'une carte comme les maquettes (« Bunker K-7 ») : nom du jeu écrit en
## capitales (« BUNKER K-7 ») remis en casse de titre (mots avec un chiffre
## gardés : « K-7 ») ; carte perso : son nom tel quel (nettoyé).
static func map_title(def: MapDef) -> String:
	var n := HubPlayView.map_name(def)
	if def == null or def is EditorMapDef or n.to_upper() != n:
		return n
	return title_case(n)


## « BUNKER K-7 » -> « Bunker K-7 ».
static func title_case(t: String) -> String:
	var words := t.split(" ")
	for i in words.size():
		var w := words[i]
		var digit := false
		for ch in w:
			if ch >= "0" and ch <= "9":
				digit = true
		if not digit and w.length() > 0:
			words[i] = w.left(1).to_upper() + w.substr(1).to_lower()
	return " ".join(words)


## Nom de la carte `id` (Hub2PlayData.map_title de sa définition).
static func map_title_of(id: String) -> String:
	return map_title(HubPlayView.def_of(id)) if id != "" else "..."


## Cartes de JOUER : {game: [...], custom: [...]} ; chaque carte {id, def,
## custom, name, sub, best} (HubPlayView.playable_maps : cartes du jeu puis
## cartes perso jouables de l'éditeur).
static func map_lists() -> Dictionary:
	var game := []
	var custom := []
	for m in HubPlayView.playable_maps():
		var row := map_row(String(m.id), m.def, bool(m.custom))
		(custom if m.custom else game).append(row)
	return {"game": game, "custom": custom}


## Ligne d'une carte : nom, sous-titre (« 1 à 4 joueurs » ; carte perso :
## « par <joueur> », faite sur ce PC), record (« record 23 », « — »).
static func map_row(id: String, def: MapDef, custom: bool) -> Dictionary:
	var best := CareerStats.map_best(id)
	return {"id": id, "def": def, "custom": custom,
		"name": map_title(def) if def else "...",
		"sub": Lang.t("par %s", "by %s") % Settings.player_name if custom
			else Lang.t("1 à %d joueurs", "1 to %d players") % Net.DEFAULT_MAX_PLAYERS,
		"best": Lang.t("record %d", "best %d") % best if best > 0 else "—"}


# --------------------------------------------------------------------------
# Défi de la semaine
# --------------------------------------------------------------------------

## Carte du défi (maquette) : {kicker « DÉFI DE LA SEMAINE · S41 », left
## « 3 j 14 h » (ou « réussi »), title « Bunker K-7 · Horde pressée »,
## line « Évacue à la manche 10 ou plus : +400 XP et des échantillons »}.
static func weekly_card(ch: WeeklyChallenge, pr: PlayerProfile) -> Dictionary:
	if ch == null:
		return {"kicker": Lang.t("DÉFI DE LA SEMAINE", "WEEKLY CHALLENGE"), "left": "",
			"title": Lang.t("Indisponible cette semaine", "Unavailable this week"),
			"line": Lang.t("Aucune carte du jeu ne convient au défi cette semaine.", "No game map suits the challenge this week.")}
	var mods := PackedStringArray()
	for m in ch.modifiers:
		mods.append(WeeklyChallenge.mod_title(m))
	var map := map_title_of(ch.map_id)
	var title := map if mods.is_empty() else "%s · %s" % [map, " · ".join(mods)]
	var done := pr != null and pr.weekly.is_rewarded(ch.key)
	var xp := ch.reward_xp_for(pr.level() if pr else 1)
	var line := Lang.t("Évacue à la manche %d ou plus : +%s XP et des échantillons",
			"Evacuate at round %d or later: +%s XP and samples") % [ch.goal_round, Hub2Style.num(xp)]
	if ch.reward_samples.is_empty():
		line = Lang.t("Évacue à la manche %d ou plus : +%s XP", "Evacuate at round %d or later: +%s XP") % [ch.goal_round, Hub2Style.num(xp)]
	if done:
		line = Lang.t("Récompense reçue cette semaine · meilleur : %s", "Reward claimed this week · best: %s") % ch.best_text(pr)
	return {"kicker": "%s · %s" % [Lang.t("DÉFI DE LA SEMAINE", "WEEKLY CHALLENGE"), ch.week_label()],
		"left": Lang.t("réussi", "complete") if done else WeeklyChallenge.remaining_text(ch.seconds_left()),
		"title": title, "line": line}


# --------------------------------------------------------------------------
# Salon (coop)
# --------------------------------------------------------------------------

## Un joueur du salon est-il PRÊT ? Revenu au salon après la partie
## précédente (LobbyReturn : pas « away ») et, si l'hôte a choisi une carte
## perso, carte reçue et vérifiée (MapShare). L'hôte est toujours prêt.
## Pas de bouton PRÊT à part (la maquette n'en montre pas) : l'état suit ce
## qui empêche vraiment de lancer.
static func player_ready(pid: int, p: Dictionary, share: MapShare) -> bool:
	if p.get("away", false):
		return false
	if pid == 1 or share == null or share.offer.is_empty():
		return true
	return String(share.states.get(pid, {}).get("etat", "attente")) == "prete"


## Texte d'état d'un joueur qui n'est pas prêt (sous-titre de l'aide) ;
## « EN ATTENTE » sur sa carte.
static func status_text(ready: bool) -> String:
	return Lang.t("PRÊT", "READY") if ready else Lang.t("EN ATTENTE", "WAITING")


## Ping affiché : « 24 ms » ; l'hôte (ou inconnu) : « — ».
static func ping_text(pid: int, p: Dictionary) -> String:
	if pid == 1 or not p.has("ping"):
		return "—"
	return "%d ms" % int(p.ping)


## Fiches des joueurs du salon, dans l'ordre des places : [{pid, slot, name,
## lvl, host, me, ping, gear (armes de départ), ready, color}].
static func lobby_cards(players: Dictionary, share: MapShare, local_id: int) -> Array:
	var by_slot := {}
	for pid in players:
		by_slot[int(players[pid].get("slot", 0))] = pid
	var slots := by_slot.keys()
	slots.sort()
	var out := []
	for s in slots:
		var pid: int = by_slot[s]
		var p: Dictionary = players[pid]
		out.append({"pid": pid, "slot": int(s), "name": String(p.get("name", "?")),
			"lvl": int(p.get("lvl", 1)), "host": pid == 1, "me": pid == local_id,
			"ping": ping_text(pid, p), "gear": PackedStringArray(p.get("start", PackedStringArray())),
			"ready": player_ready(pid, p, share), "color": HudStyle.player_color(int(s))})
	return out


## « 3 joueurs prêts sur 3 » / « 1 joueur prêt sur 2 ».
static func ready_line(ready: int, total: int) -> String:
	if Lang.is_en():
		return "%d of %d player%s ready" % [ready, total, "" if total == 1 else "s"]
	return "%d joueur%s prêt%s sur %d" % [ready, "" if ready <= 1 else "s", "" if ready <= 1 else "s", total]


## Places affichées dans le salon (cartes « PLACE LIBRE » comprises) :
## 4 (maquette), plus si le salon accepte plus de joueurs et qu'ils sont là.
static func lobby_columns(players: int, max_players: int) -> int:
	return clampi(maxi(players, mini(max_players, 4)), 1, Net.MAX_SUPPORTED_PLAYERS)


## Adresse « 192.168.1.24:7777 » (port toujours écrit, comme la maquette).
static func address_text(ip: String, port: int) -> String:
	return "%s:%d" % [ip, port]


## Adresse saisie (« 192.168.1.24 » ou « 192.168.1.24:7777 ») -> [ip, port]
## (port par défaut si absent) ; [] si illisible.
static func parse_address(t: String, default_port := Net.DEFAULT_PORT) -> Array:
	t = t.strip_edges()
	var ip := t
	var port := default_port
	var i := t.rfind(":")
	if i >= 0:
		ip = t.left(i)
		var pt := t.substr(i + 1)
		if not pt.is_valid_int():
			return []
		port = pt.to_int()
	if not Net.is_valid_ipv4(ip) or not Net.is_valid_port(port):
		return []
	return [ip, port]
