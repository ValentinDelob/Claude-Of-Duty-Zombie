class_name ReviveTarget
extends Interactable
## Point d'interaction attaché à chaque joueur : quand il est à terre, ses
## coéquipiers maintiennent [F] près de lui pour le réanimer.

var owner_pid := 0


func setup(pid: int) -> void:
	owner_pid = pid
	interact_id = "revive_%d" % pid
	name = "Revive"
	interact_range = DownedSystem.REVIVE_RANGE
	hold_time = DownedSystem.REVIVE_TIME


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.4


func prompt(pid: int) -> String:
	var d := system.game.downed
	if pid == owner_pid or not d.is_downed(owner_pid):
		return ""
	var r := d.reviver_of(owner_pid)
	if r != 0 and r != pid:
		return ""
	return "[F] Maintenir pour réanimer %s" % Net.player_name(owner_pid)


func srv_use(pid: int) -> void:
	system.game.downed.srv_start_revive(pid, owner_pid)


func srv_release(pid: int) -> void:
	system.game.downed.srv_stop_revive(pid, owner_pid)
