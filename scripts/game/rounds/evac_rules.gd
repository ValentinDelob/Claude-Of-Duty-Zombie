class_name EvacRules
extends RefCounted
## Règles de la fenêtre d'évacuation (GAME_CONCEPT.md §4.5 ; fonctions pures,
## tests/test_evac_rules.gd). EvacDoor les applique sur le serveur.
##
## * Après une vague spéciale ou de boss VAINCUE, la porte d'évacuation
##   s'ouvre DURATION secondes ; aucun zombie, la manche suivante attend.
## * Votants : les joueurs qui ne sont pas morts (debout ou à terre). Les
##   morts réapparaissent à l'ouverture (la vague est terminée, §4.6) ; un
##   joueur mort pendant la fenêtre est spectateur : il ne vote pas et part
##   avec l'équipe.
## * Vote à la porte ([F] / X) : chaque appui alterne « partir » et « prêt »
##   (premier appui : « partir »).
## * Tous les votants ont voté « prêt » : la partie reprend (manche suivante
##   après RESUME_DELAY secondes).
## * Tous les votants ont voté « partir » ET sont DEBOUT dans la zone de la
##   porte au même moment : l'équipe entière s'évacue (fin de partie réussie).
##   Un joueur à terre bloque donc l'évacuation tant qu'il n'est pas relevé.
## * Fin des DURATION secondes sans évacuation : la partie continue (comme
##   « tous prêts »).

enum Vote { NONE, READY, LEAVE }

const DURATION := 120.0
## Délai avant la manche suivante quand la fenêtre se ferme sans évacuation.
const RESUME_DELAY := 3.0
## Zone de la porte, dans le repère de la porte (x le long du mur, z vers la
## pièce depuis la face du mur, m) : 4 m de large, 3,5 m de profondeur.
const ZONE_HALF_WIDTH := 2.0
const ZONE_DEPTH := 3.5
## Écart de hauteur toléré (pieds du joueur / sol de la porte).
const ZONE_HEIGHT := 1.5
## Issues d'une décision.
const NONE := ""
const RESUME := "resume"
const EVACUATE := "evacuate"


## Vote suivant après un appui à la porte.
static func next_vote(cur: int) -> int:
	return Vote.READY if cur == Vote.LEAVE else Vote.LEAVE


## Point local (repère de la porte : origine au pied de la porte, sur la face
## du mur, +z vers la pièce) dans la zone de la porte ?
static func in_zone_local(local: Vector3) -> bool:
	return absf(local.x) <= ZONE_HALF_WIDTH and local.z >= -0.2 and local.z <= ZONE_DEPTH \
			and absf(local.y) <= ZONE_HEIGHT


## Votants : identifiants des joueurs non morts (`life` : pid -> PlayerData.Life).
static func voters(life: Dictionary) -> Array:
	var out := []
	for pid in life:
		if int(life[pid]) != PlayerData.Life.DEAD:
			out.append(pid)
	out.sort()
	return out


## Décision du serveur : `votes` (pid -> Vote), `life` (pid -> Life),
## `in_zone` (pid -> bool, joueur dans la zone de la porte), `time_left` (s).
static func decide(votes: Dictionary, life: Dictionary, in_zone: Dictionary, time_left: float) -> String:
	var vs := voters(life)
	if vs.is_empty():
		return NONE
	var all_ready := true
	var all_leave := true
	for pid in vs:
		var v := int(votes.get(pid, Vote.NONE))
		if v != Vote.READY:
			all_ready = false
		if v != Vote.LEAVE or int(life[pid]) != PlayerData.Life.ALIVE or not bool(in_zone.get(pid, false)):
			all_leave = false
	if all_leave:
		return EVACUATE
	if all_ready or time_left <= 0.0:
		return RESUME
	return NONE


## Compteurs pour l'affichage : {voters, leave, ready, in_zone}.
static func tally(votes: Dictionary, life: Dictionary, in_zone: Dictionary) -> Dictionary:
	var out := {"voters": 0, "leave": 0, "ready": 0, "in_zone": 0}
	for pid in voters(life):
		out.voters += 1
		var v := int(votes.get(pid, Vote.NONE))
		if v == Vote.LEAVE:
			out.leave += 1
		elif v == Vote.READY:
			out.ready += 1
		if bool(in_zone.get(pid, false)) and int(life[pid]) == PlayerData.Life.ALIVE:
			out.in_zone += 1
	return out


## Temps restant « m:ss ».
static func clock_text(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


## Bandeau du HUD pendant la fenêtre (deux lignes, langue du joueur).
static func status_text(time_left: float, t: Dictionary, my_vote: int) -> String:
	var mine := ""
	match my_vote:
		Vote.LEAVE:
			mine = Lang.t("vous : PARTIR", "you: LEAVE")
		Vote.READY:
			mine = Lang.t("vous : PRÊT", "you: READY")
		_:
			mine = Lang.t("vous : pas encore voté", "you: no vote yet")
	return Lang.t("ÉVACUATION OUVERTE — %s", "EVACUATION OPEN — %s") % clock_text(time_left) + "\n" \
			+ Lang.t("Partir %d/%d · Prêts %d/%d · À la porte %d/%d · %s",
				"Leave %d/%d · Ready %d/%d · At the door %d/%d · %s") \
			% [t.leave, t.voters, t.ready, t.voters, t.in_zone, t.voters, mine]
