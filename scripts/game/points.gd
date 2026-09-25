class_name Points
extends Node
## Attribution des points (serveur uniquement). Écoute les dégâts validés par
## Combat et crédite le joueur via Session (qui réplique aux clients).

var game: Game
## Multiplicateur global (bonus « double points »).
var multiplier := 1


func _ready() -> void:
	game = get_parent()
	if multiplayer.is_server():
		(game.get_node("Combat") as Combat).zombie_damaged.connect(_on_zombie_damaged)


func _on_zombie_damaged(pid: int, _zid: int, _dmg: int, killed: bool, headshot: bool, kind: Combat.HitKind) -> void:
	var pd := game.session.get_data(pid)
	if pd == null:
		return
	var pts := PointsRules.for_damage(killed, headshot, kind) * multiplier
	if pts > 0:
		game.session.add_points(pid, pts)
	if killed:
		pd.kills += 1
		if headshot:
			pd.headshots += 1
		game.session.sync_stats(pid)
