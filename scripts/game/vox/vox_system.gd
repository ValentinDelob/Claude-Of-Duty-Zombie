class_name VoxSystem
extends Node
## Répliques des personnages (docs/CHARACTERS.md), comme les « vox » de BO1 :
## le serveur décide qui parle, de quoi et quelle variante (délai entre deux
## répliques d'un même joueur, délai par situation, probabilité, tirage sans
## répétition), puis chaque machine joue la réplique dans la langue choisie
## (Settings.language) : en 3D sur le joueur qui parle, en 2D pour soi-même.
##
## Les systèmes du jeu appellent `srv_say(pid, catégorie)` (serveur) ; les
## éliminations, tirs, bonus et manches sont écoutés ici par signaux.

## Écart minimal (s) entre deux répliques d'un même joueur.
const GAP := 2.2
## Délai (s) avant de redire une même situation (par joueur), défaut DEFAULT_CD.
const DEFAULT_CD := 6.0
const COOLDOWN := {
	"idle": 70.0, "low_health": 20.0, "surrounded": 30.0, "ammo_low": 25.0, "ammo_out": 20.0,
	"kill_generic": 12.0, "kill_headshot": 8.0, "kill_close": 10.0, "crawler_made": 12.0,
	"no_money": 15.0, "door_open": 10.0, "buy_wall": 10.0,
	"hurt": 3.5, "exert_melee": 4.0, "reload": 12.0, "oh_shit": 25.0, "crawler_near": 30.0,
	"downed_help": 12.0, "buy_ammo": 10.0, "no_power": 12.0, "resp_box_bad": 20.0, "resp_wonder": 20.0,
}
## Répliques prioritaires : passent même juste après une autre réplique.
const URGENT := ["downed", "revived", "teammate_down", "teammate_dead", "last_alive", "game_start", "death"]
## Voix : niveau et portée. Elles jouent sur le bus « Voice » (Audio.track_voice,
## docs/ASSETS.md « Mixage ») et sont simplement plus fortes que le reste, qui ne
## baisse jamais : fichiers à -19 dBFS contre -14 LUFS pour les zombies, d'où
## +8 dB pour sa propre voix et +10 dB pour celles des coéquipiers (le limiteur
## du Master évite toute saturation).
const VOLUME_3D := 10.0
const VOLUME_2D := 8.0
## Coéquipiers : niveau plein jusqu'à UNIT_SIZE_3D m, audibles jusqu'à
## MAX_DISTANCE_3D m, à peine assourdis par la distance (voix claires).
const UNIT_SIZE_3D := 10.0
const MAX_DISTANCE_3D := 50.0

var game: Game
var _last_ms := {}   # pid -> ms de la dernière réplique
var _cat_ms := {}    # "pid:cat" -> ms
var _bags := {}      # "personnage:cat" -> variantes restantes (tirage sans remise)
var _kills := {}     # pid -> [ms des derniers kills]
var _splash := {}    # pid -> [ms, nombre] (kills explosifs groupés)
var _crawlers := {}  # zid des rampants déjà commentés
var _calm_ms := {}   # pid -> dernier ms avec un zombie proche
var _down_ms := {}   # pid -> ms où il est tombé (appel à l'aide)
var _tick := 0.0
var _voices := {}    # pid -> AudioStreamPlayer3D
var _self_voice: AudioStreamPlayer

## Réplique jouée sur cette machine (tests, journal) : pid, catégorie, variante.
signal said(pid: int, category: String, variant: int)


func _ready() -> void:
	game = get_parent() as Game
	_self_voice = AudioStreamPlayer.new()
	_self_voice.volume_db = VOLUME_2D
	Audio.track_voice(_self_voice)
	add_child(_self_voice)
	if not multiplayer.is_server():
		return
	game.combat.zombie_damaged.connect(_on_zombie_damaged)
	game.combat.shot_validated.connect(_on_shot)
	game.rounds.round_started.connect(_on_round_started)
	if game.powerups:
		game.powerups.powerup_grabbed.connect(func(type: String, pid: int): later(1.3, pid, "pw_" + type, 0.9))
	if game.rounds.dogs:
		game.rounds.dogs.dog_round_started.connect(func(_n: int): later(2.0, _random_alive(), "dog_round"))


# --------------------------------------------------------------------------
# Serveur : décision
# --------------------------------------------------------------------------

## Fait dire `category` au joueur `pid` si le moment s'y prête. Serveur.
func srv_say(pid: int, category: String, chance := 1.0) -> bool:
	if not multiplayer.is_server() or pid <= 0 or not game.players.has(pid):
		return false
	var pd: PlayerData = game.session.get_data(pid)
	if pd == null or (pd.life == PlayerData.Life.DEAD):
		return false
	var now := Time.get_ticks_msec()
	if not category in URGENT and now - int(_last_ms.get(pid, -100000)) < GAP * 1000.0:
		return false
	var key := "%d:%s" % [pid, category]
	if now - int(_cat_ms.get(key, -1000000)) < float(COOLDOWN.get(category, DEFAULT_CD)) * 1000.0:
		return false
	if chance < 1.0 and randf() > chance:
		return false
	var ch := CharacterDB.id_of(pid)
	var n := CharacterDB.variants(ch, category)
	if n == 0:
		return false
	_last_ms[pid] = now
	_cat_ms[key] = now
	_cl_say.rpc(pid, category, _draw(ch, category, n))
	return true


## Raccourcis pour les systèmes du jeu (serveur ; sans effet hors partie).
static func say(pid: int, category: String, chance := 1.0) -> void:
	var g := Game.instance
	if g and g.vox:
		g.vox.srv_say(pid, category, chance)


static func say_later(delay: float, pid: int, category: String, chance := 1.0) -> void:
	var g := Game.instance
	if g and g.vox:
		g.vox.later(delay, pid, category, chance)


## Catégorie de la réplique pour une arme sortie de la boîte mystère.
static func box_category(weapon: String) -> String:
	if weapon == ThrowableRules.MONKEY_ID:
		return "box_monkey"
	if weapon == "ray":
		return "box_ray"
	if weapon == "thunder":
		return "box_thunder"
	if not WeaponDB.exists(weapon):
		return "box_good"
	match String(WeaponDB.stats(weapon).get("class", "")):
		"pistol", "revolver":
			return "box_bad"
		"shotgun":
			return "box_shotgun"
		"sniper":
			return "box_sniper"
		"lmg":
			return "box_lmg"
		"launcher", "rocket":
			return "box_launcher"
	return "box_good"


## Arme sortie de la boîte : commentaire du joueur, puis parfois d'un
## coéquipier proche (moquerie ou envie, comme les réponses de BO1).
static func box_result(owner: int, weapon: String) -> void:
	var g := Game.instance
	if g == null or g.vox == null:
		return
	var cat := box_category(weapon)
	g.vox.srv_say(owner, cat, 0.85)
	var resp := "resp_wonder" if cat in ["box_ray", "box_thunder"] else "resp_box_bad" if cat == "box_bad" else ""
	if resp == "" or not g.players.has(owner):
		return
	var near: Array[int] = []
	for m in g.vox.teammates(owner):
		if g.players[m].global_position.distance_to(g.players[owner].global_position) < 15.0:
			near.append(m)
	if not near.is_empty():
		g.vox.later(2.6, near.pick_random(), resp, 0.7 if resp == "resp_wonder" else 0.45)


## Réplique différée (après une annonce, une animation...).
func later(delay: float, pid: int, category: String, chance := 1.0) -> void:
	if not multiplayer.is_server() or pid <= 0:
		return
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(self):
			srv_say(pid, category, chance))


## Tous les coéquipiers vivants de `pid` (pas lui).
func teammates(pid: int) -> Array[int]:
	var out: Array[int] = []
	for id in game.session.data:
		var pd: PlayerData = game.session.data[id]
		if id != pid and pd.life == PlayerData.Life.ALIVE and game.players.has(id):
			out.append(id)
	return out


func _draw(ch: String, category: String, n: int) -> int:
	var key := ch + ":" + category
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		for i in n:
			bag.append(i)
		bag.shuffle()
	var v: int = bag.pop_back()
	_bags[key] = bag
	return v


func _random_alive() -> int:
	var ids: Array[int] = []
	for id in game.session.data:
		if (game.session.data[id] as PlayerData).life == PlayerData.Life.ALIVE and game.players.has(id):
			ids.append(id)
	return ids.pick_random() if not ids.is_empty() else -1


func _on_zombie_damaged(pid: int, zid: int, _damage: int, killed: bool, headshot: bool, kind: Combat.HitKind) -> void:
	if pid <= 0 or not game.players.has(pid):
		return
	var z = game.zombies.get_zombie(zid)
	if not killed:
		if z is Zombie and z.is_crawler() and not _crawlers.has(zid):
			_crawlers[zid] = true
			srv_say(pid, "crawler_made", 0.6)
		return
	_crawlers.erase(zid)
	var now := Time.get_ticks_msec()
	var recent: Array = (_kills.get(pid, []) as Array).filter(func(t): return now - int(t) < 4000)
	recent.append(now)
	_kills[pid] = recent
	if recent.size() >= 5:
		_kills[pid] = []
		srv_say(pid, "kill_streak")
		return
	if z is Hellhound:
		srv_say(pid, "kill_dog", 0.5)
		return
	var pd: PlayerData = game.session.get_data(pid)
	var weapon := String(pd.current_weapon().get("id", "")) if pd else ""
	match kind:
		Combat.HitKind.MELEE:
			srv_say(pid, "kill_bowie" if pd and pd.knife == "bowie" else "kill_melee", 0.5)
		Combat.HitKind.TRAP:
			srv_say(pid, "kill_trap", 0.35)
		Combat.HitKind.SPLASH:
			var s: Array = _splash.get(pid, [0, 0])
			if now - int(s[0]) > 400:
				s = [now, 0]
			s[1] = int(s[1]) + 1
			_splash[pid] = s
			if s[1] == 2:
				srv_say(pid, "kill_ray" if weapon == "ray" else "kill_explosive", 0.7)
		Combat.HitKind.SPECIAL:
			if weapon == "thunder":
				srv_say(pid, "kill_thunder", 0.5)
		_:
			if weapon == "ray":
				srv_say(pid, "kill_ray", 0.3)
			elif headshot:
				srv_say(pid, "kill_headshot", 0.2)
			elif z is Node3D and (z as Node3D).global_position.distance_to(game.players[pid].global_position) < 1.7:
				srv_say(pid, "kill_close", 0.25)
			else:
				srv_say(pid, "kill_generic", 0.04)


func _on_shot(pid: int) -> void:
	var pd: PlayerData = game.session.get_data(pid)
	if pd == null:
		return
	var w: Dictionary = pd.current_weapon()
	var id := String(w.get("id", ""))
	if id == "" or not WeaponDB.exists(id):
		return
	var st: Dictionary = WeaponDB.stats(id, bool(w.get("pap", false)))
	if st.get("infinite", false):
		return
	var mag := int(w.get("mag", 0))
	var reserve := int(w.get("reserve", 0))
	if mag == 0 and reserve == 0:
		srv_say(pid, "ammo_out")
	elif reserve == 0 and mag <= maxi(1, int(st.get("mag", 8)) / 3):
		srv_say(pid, "ammo_low", 0.8)


func _on_round_started(n: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := _random_alive()
	if n <= 1:
		later(1.5, pid, "game_start")
		return
	if game.rounds.dogs and game.rounds.dogs.cl_active:
		return  # la manche des chiens a sa propre réplique
	var others := teammates(pid)
	if not others.is_empty() and randf() < 0.35:
		later(2.5, pid, "tease_" + CharacterDB.id_of(others.pick_random()))
	else:
		later(2.5, pid, "round_start", 0.7)


## Encerclement et moments de calme, vérifiés une fois par seconde.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var now := Time.get_ticks_msec()
	for pid in game.players:
		var pd: PlayerData = game.session.get_data(pid)
		if pd == null:
			continue
		# À terre depuis un moment, personne ne le relève : appel à l'aide.
		if pd.life == PlayerData.Life.DOWNED:
			if not _down_ms.has(pid):
				_down_ms[pid] = now
			elif now - int(_down_ms[pid]) > 9000 and int(game.downed.downed.get(pid, {}).get("reviver", 0)) == 0:
				srv_say(pid, "downed_help", 0.6)
			continue
		_down_ms.erase(pid)
		if pd.life != PlayerData.Life.ALIVE:
			continue
		var pl: Player = game.players[pid]
		var pos: Vector3 = pl.global_position
		var fwd := -pl.global_transform.basis.z
		var close := 0
		var near := false
		var behind := false
		var crawler := false
		for z in game.zombies.zombies.values():
			if not is_instance_valid(z) or not z.is_alive():
				continue
			var to: Vector3 = (z as Node3D).global_position - pos
			var d := to.length()
			if d < 3.5:
				close += 1
			if d < 12.0:
				near = true
			if d < 2.2 and Vector2(to.x, to.z).normalized().dot(Vector2(fwd.x, fwd.z).normalized()) < -0.3:
				behind = true
			if d < 4.0 and z is Zombie and z.is_crawler():
				crawler = true
		if close >= 5:
			srv_say(pid, "surrounded")
		elif behind:
			srv_say(pid, "oh_shit", 0.5)
		elif crawler:
			srv_say(pid, "crawler_near", 0.35)
		if near:
			_calm_ms[pid] = now
		elif now - int(_calm_ms.get(pid, now)) > 25000:
			_calm_ms[pid] = now
			srv_say(pid, "idle", 0.5)
		if not _calm_ms.has(pid):
			_calm_ms[pid] = now


# --------------------------------------------------------------------------
# Toutes les machines : lecture
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_say(pid: int, category: String, variant: int) -> void:
	said.emit(pid, category, variant)
	var ch := CharacterDB.id_of(pid)
	var path := CharacterDB.vox_path(Settings.language, ch, category, variant)
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	var p: Player = game.players.get(pid)
	if p == null or p == game.local_player:
		_self_voice.stream = stream
		_self_voice.play()
		return
	var v: AudioStreamPlayer3D = _voices.get(pid)
	if v == null or not is_instance_valid(v):
		v = AudioStreamPlayer3D.new()
		v.unit_size = UNIT_SIZE_3D
		v.max_distance = MAX_DISTANCE_3D
		v.attenuation_filter_cutoff_hz = 9000.0
		v.attenuation_filter_db = -6.0
		v.volume_db = VOLUME_3D
		Audio.track_voice(v)
		v.position = Vector3(0, 1.6, 0)  # à la hauteur de la bouche
		p.add_child(v)
		_voices[pid] = v
	v.stream = stream
	v.play()
