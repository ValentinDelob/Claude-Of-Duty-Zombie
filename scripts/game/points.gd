class_name Points
extends Node
## Attribution de la ferraille (serveur uniquement ; « points » est le nom
## interne de la ferraille, voir PointsRules). Écoute les dégâts validés par
## Combat et crédite le joueur qui touche (balle, couteau : plafonné par
## zombie) ou qui tue, via Session (qui réplique aux clients). Paie aussi les
## planches reposées (srv_repair, plafonné par joueur et par manche).

var game: Game
## Serveur : ferraille de reconstruction payée, pid -> [manche, montant].
var _repair_paid: Dictionary = {}


func _ready() -> void:
	game = get_parent()
	if multiplayer.is_server():
		(game.get_node("Combat") as Combat).zombie_damaged.connect(_on_zombie_damaged)


func _on_zombie_damaged(pid: int, zid: int, _dmg: int, killed: bool, headshot: bool, kind: Combat.HitKind) -> void:
	var pd := game.session.get_data(pid)
	if pd == null:
		return
	var z: Zombie = null if killed else game.zombies.get_zombie(zid)
	var pts := PointsRules.for_damage(killed, headshot, kind, z.paid_hits if z else PointsRules.HIT_CAP)
	if not killed and pts > 0:
		z.paid_hits += 1
	award(pid, pts)
	if killed:
		pd.kills += 1
		if headshot:
			pd.headshots += 1
		game.session.sync_stats(pid)


## Serveur : crédite `pts` de ferraille au joueur `pid`.
func award(pid: int, pts: int) -> void:
	if pts <= 0 or game.session.get_data(pid) == null:
		return
	game.session.add_points(pid, pts)


## Serveur : `pid` vient de reposer une planche ; crédite PointsRules.REPAIR
## tant que son plafond de la manche (REPAIR_CAP) n'est pas atteint. Chacun a
## son propre plafond. Retourne la ferraille gagnée.
func srv_repair(pid: int) -> int:
	if not multiplayer.is_server() or game.session.get_data(pid) == null:
		return 0
	var paid := repair_paid(pid)
	var pts := PointsRules.for_repair(paid)
	_repair_paid[pid] = [_round(), paid + pts]
	award(pid, pts)
	return pts


## Ferraille de reconstruction déjà payée à `pid` pendant la manche en cours.
func repair_paid(pid: int) -> int:
	var rec: Array = _repair_paid.get(pid, [-1, 0])
	return int(rec[1]) if int(rec[0]) == _round() else 0


func _round() -> int:
	return game.rounds.round_n if game and game.rounds else 0
