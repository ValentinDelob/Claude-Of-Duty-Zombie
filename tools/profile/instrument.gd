extends SceneTree
## Profileur (tools/profile.sh) : instrumente une COPIE du projet, jamais les
## sources. Chaque _process / _physics_process des scripts du jeu, plus les
## fonctions de EXTRA, est enveloppé d'une mesure (Time.get_ticks_usec)
## cumulée dans ProfTmp (scripts/prof_tmp.gd, écrit dans la copie). Temps
## inclusifs : une fonction compte aussi celles qu'elle appelle. Hellhound
## hérite de Zombie : son temps comprend l'appel à super().
##   godot --headless --path . -s res://tools/profile/instrument.gd -- --dst=<copie>

const PROF := """class_name ProfTmp
extends RefCounted
## Copie instrumentée seulement (tools/profile.sh) : temps cumulés.
static var acc := {}
static var calls := {}


static func add(k: StringName, t0: int) -> void:
	acc[k] = acc.get(k, 0) + (Time.get_ticks_usec() - t0)
	calls[k] = calls.get(k, 0) + 1


static func reset() -> void:
	acc.clear()
	calls.clear()
"""

const EXTRA := {
	"res://scripts/game/player/player.gd": ["_move", "_update_camera_effects", "_local_physics"],
	"res://scripts/game/weapons/weapon_controller.gd": ["tick", "_fire", "_trace"],
	"res://scripts/game/interact/interaction_system.gd": ["local_tick"],
	"res://scripts/game/weapons/view_model.gd": ["update"],
	"res://scripts/game/zombies/zombie.gd": ["_chase", "_separation", "_update_pose", "_groan", "_footstep", "_nearest_player", "_follow_floor", "_check_stuck", "_process_death"],
	"res://scripts/game/zombies/zombie_manager.gd": ["separation_grid", "build_snapshot", "pose_step"],
	"res://scripts/game/dogs/hellhound.gd": ["_emit_flames"],
	"res://scripts/game/combat.gd": ["damage_zombie", "explosion", "srv_fire", "_apply_hits"],
	"res://scripts/game/fx/fx.gd": ["blood_hit", "impact", "tracer", "dirt_burst"],
	"res://scripts/game/fx/particle_pool.gd": ["burst", "emit"],
	"res://scripts/game/throwables/throwable_system.gd": ["explosion_fx"],
	"res://scripts/game/zombies/zombie_gibs.gd": ["apply", "crawl_pose", "limb_at"],
	"res://scripts/game/rounds/spawner.gd": ["pick_spawn_point", "recycle"],
	"res://scripts/autoload/audio.gd": ["play_3d"],
	"res://scripts/game/hud/hud.gd": ["_process"],
	"res://scripts/game/map/mesh_nav.gd": ["find_path", "world_line_clear"],
	"res://scripts/game/map/nav_grid.gd": ["find_path", "world_line_clear"],
	"res://scripts/game/player/player_visual.gd": ["animate"],
}


var dst := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dst="):
			dst = a.trim_prefix("--dst=").trim_suffix("/")
	if dst == "" or not DirAccess.dir_exists_absolute(dst + "/scripts"):
		push_error("[prof] --dst=<copie du projet> manquant")
		quit(1)
		return
	var files: Array[String] = []
	_walk("res://scripts", files)
	var n := 0
	for f in files:
		if f.contains("/editor/"):
			continue
		var wanted: Array = ["_process", "_physics_process"]
		wanted.append_array(EXTRA.get(f, []))
		if _instrument(f, wanted):
			n += 1
	var fa := FileAccess.open(dst + "/scripts/prof_tmp.gd", FileAccess.WRITE)
	fa.store_string(PROF)
	fa.close()
	print("[prof] %d scripts instrumentés" % n)
	quit()


func _walk(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d, out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)


static func _split_params(s: String) -> Array:
	var out := []
	var depth := 0
	var cur := ""
	for ch in s:
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		out.append(cur)
	return out


func _instrument(path: String, wanted: Array) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var base := path.get_file().get_basename()
	var re := RegEx.create_from_string("^(static )?func ([A-Za-z0-9_]+)\\((.*)\\)\\s*(->\\s*([^:]+))?:\\s*$")
	var wrappers := []
	var cur_func := ""
	var cur_inner := ""
	var changed := false
	for i in lines.size():
		var line: String = lines[i]
		var m := re.search(line)
		if m:
			cur_func = ""
			var fname := m.get_string(2)
			if fname in wanted:
				var is_static := m.get_string(1) != ""
				var params := m.get_string(3)
				var ret := m.get_string(5).strip_edges()
				var inner := "__prof_%s_%s" % [base, fname]
				cur_func = fname
				cur_inner = inner
				lines[i] = line.replace("func %s(" % fname, "func %s(" % inner)
				var args := []
				for p in _split_params(params):
					var nm: String = p.strip_edges().split(":")[0].split("=")[0].strip_edges()
					args.append(nm)
				var key := "%s.%s" % [base, fname]
				var w := "\n%sfunc %s(%s)%s:\n\tvar __t := Time.get_ticks_usec()\n" % ["static " if is_static else "", fname, params, (" -> " + ret) if ret != "" else ""]
				if ret == "" or ret == "void":
					w += "\t%s(%s)\n\tProfTmp.add(&\"%s\", __t)\n" % [inner, ", ".join(args), key]
				else:
					w += "\tvar __r = %s(%s)\n\tProfTmp.add(&\"%s\", __t)\n\treturn __r\n" % [inner, ", ".join(args), key]
				wrappers.append(w)
				changed = true
			continue
		if cur_func != "" and line.begins_with("\t") and line.contains("super("):
			lines[i] = line.replace("super(", "super.%s(" % cur_func)
		elif line != "" and not line.begins_with("\t") and not line.begins_with("#"):
			cur_func = ""
	if not changed:
		return false
	var out := "\n".join(lines) + "\n" + "\n".join(wrappers)
	var fa := FileAccess.open(dst + "/" + path.trim_prefix("res://"), FileAccess.WRITE)
	fa.store_string(out)
	fa.close()
	return true
