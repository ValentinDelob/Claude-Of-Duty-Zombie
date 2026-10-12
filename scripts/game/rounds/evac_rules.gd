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
## * Vote de n'importe où pendant la fenêtre (maquette
##   docs/hub_v2/Evacuation.dc.html) : CONTINUER (action « vote_continue »,
##   F1 / croix gauche) ou ÉVACUER (« vote_evacuate », F2 / croix droite).
##   L'autre touche change le vote ; on ne revient jamais à « en attente »
##   (EN ATTENTE = pas encore voté, pas un choix).
## * Tous les votants ont voté CONTINUER (READY) : la partie reprend (manche
##   suivante après RESUME_DELAY secondes).
## * Tous les votants ont voté ÉVACUER (LEAVE) ET sont DEBOUT dans la zone de
##   la porte au même moment : l'équipe entière s'évacue (fin de partie
##   réussie). Un joueur à terre bloque donc l'évacuation tant qu'il n'est pas
##   relevé.
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


## Vote qu'un joueur peut choisir : CONTINUER ou ÉVACUER (jamais « en
## attente », ni une valeur inconnue venue du réseau).
static func is_choice(v: Variant) -> bool:
	return v is int and (v == Vote.READY or v == Vote.LEAVE)


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


## Votes des seuls joueurs encore dans la partie (`life` : pid -> Life) ;
## les votes d'un joueur parti sont oubliés.
static func prune_votes(votes: Dictionary, life: Dictionary) -> Dictionary:
	var out := {}
	for pid in votes:
		if life.has(pid):
			out[pid] = votes[pid]
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


## Lignes du cadre de vote, une par votant (un mort, spectateur, n'en a
## pas) : [{pid, vote, me}], le joueur local `me` d'abord, puis l'ordre
## `order` (identifiants par place dans l'équipe), puis les autres votants.
static func vote_rows(votes: Dictionary, life: Dictionary, me: int, order: Array) -> Array:
	var vs := voters(life)
	var ids := []
	if me in vs:
		ids.append(me)
	for pid in order + vs:
		if pid in vs and not pid in ids:
			ids.append(pid)
	var out := []
	for pid in ids:
		var v: Variant = votes.get(pid, Vote.NONE)
		out.append({"pid": pid, "vote": int(v) if is_choice(v) else Vote.NONE, "me": pid == me})
	return out


## Nom affiché d'un vote : CONTINUER, ÉVACUER, EN ATTENTE (pas encore voté).
static func vote_text(v: int) -> String:
	match v:
		Vote.READY:
			return Lang.t("CONTINUER", "CONTINUE")
		Vote.LEAVE:
			return Lang.t("ÉVACUER", "EVACUATE")
	return Lang.t("EN ATTENTE", "WAITING")


## Temps restant « m:ss ».
static func clock_text(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]
