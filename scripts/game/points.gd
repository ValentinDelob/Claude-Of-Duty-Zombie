class_name Points
extends Node
## Attribution de la ferraille (serveur uniquement ; « points » est le nom
## interne de la ferraille, voir PointsRules). Écoute les dégâts validés par
## Combat et crédite le joueur qui tue via Session (qui réplique aux clients).

var game: Game
## Multiplicateur global (bonus « double points »).
var multiplier := 1
## Serveur : total des points GAGNÉS par toute l'équipe (seuil des bonus).
var team_earned := 0


func _ready() -> void:
	game = get_parent()
	if multiplayer.is_server():
		(game.get_node("Combat") as Combat).zombie_damaged.connect(_on_zombie_damaged)


func _on_zombie_damaged(pid: int, _zid: int, _dmg: int, killed: bool, headshot: bool, kind: Combat.HitKind) -> void:
	var pd := game.session.get_data(pid)
	if pd == null:
		return
	award(pid, PointsRules.for_damage(killed, headshot, kind))
	if killed:
		pd.kills += 1
		if headshot:
			pd.headshots += 1
		game.session.sync_stats(pid)


## Serveur : crédite `base` points (x multiplicateur) et les compte dans le
## total de l'équipe (seuil d'apparition des bonus).
func award(pid: int, base: int) -> void:
	var pts := base * multiplier
	if pts <= 0 or game.session.get_data(pid) == null:
		return
	team_earned += pts
	game.session.add_points(pid, pts)
