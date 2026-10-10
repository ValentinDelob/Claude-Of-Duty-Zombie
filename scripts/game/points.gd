class_name Points
extends Node
## Attribution de la ferraille (serveur uniquement ; « points » est le nom
## interne de la ferraille, voir PointsRules). Écoute les dégâts validés par
## Combat et crédite le joueur qui touche (balle, couteau : plafonné par
## zombie) ou qui tue, via Session (qui réplique aux clients).

var game: Game


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
