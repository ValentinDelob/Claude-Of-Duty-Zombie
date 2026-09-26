extends Node
## Audio — lecture des sons (pool de lecteurs 3D / 2D) et musiques d'ambiance.
##
##   Audio.play_3d("pistol_fire", position)
##   Audio.play_2d("ui_select")
##   Audio.play_music("menu_ambience")
## Les noms correspondent aux fichiers res://assets/audio/<nom>.wav.

const DIR := "res://assets/audio/"
const POOL_3D := 40
const POOL_2D := 16

var _cache: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _music: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name := ""
## Limite le nombre de lectures simultanées d'un même son (ex. 20 zombies qui grognent).
var _recent: Dictionary = {}
var _shutdown := false
## Groupes de voix 3D à polyphonie limitée (vocalises et pas des zombies) :
## au-delà, la voix la plus lointaine est remplacée si le nouveau son est
## plus proche de l'auditeur, sinon le nouveau son est ignoré.
const VOICE_LIMITS := {"zombie": 7, "zombie_step": 4}
## Distance maximale d'audibilité des sons 3D (m).
const MAX_DISTANCE := 45.0
var _group_of: Dictionary = {}  # AudioStreamPlayer3D -> groupe
## Nombre de lectures 3D par son depuis le lancement (diagnostic, autotests).
var played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 6.0
		p.max_distance = MAX_DISTANCE
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_2d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = "Music"
	add_child(_music_b)


func get_stream(sound: String) -> AudioStream:
	if _shutdown:
		return null
	if _cache.has(sound):
		return _cache[sound]
	var path := DIR + sound + ".wav"
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if st == null:
		push_warning("[Audio] son introuvable : " + sound)
	_cache[sound] = st
	return st


func _throttled(sound: String, max_per_100ms: int) -> bool:
	var now := Time.get_ticks_msec()
	var entry: Array = _recent.get(sound, [0, 0])
	if now - entry[0] > 100:
		entry = [now, 0]
	entry[1] += 1
	_recent[sound] = entry
	return entry[1] > max_per_100ms


func play_3d(sound: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.06, max_per_100ms := 6, pitch := 1.0, group := "") -> void:
	var st := get_stream(sound)
	if st == null or _throttled(sound, max_per_100ms):
		return
	var p: AudioStreamPlayer3D
	if group != "":
		p = _group_voice(group, pos)
		if p == null:
			return
	else:
		p = _pool_3d[_next_3d]
		_next_3d = (_next_3d + 1) % POOL_3D
	_group_of[p] = group
	p.stream = st
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()
	played[sound] = int(played.get(sound, 0)) + 1


## Position de l'auditeur (caméra active), ou null sans caméra 3D.
func listener_position() -> Variant:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	return cam.global_position if cam else null


## Lecteur pour un son d'un groupe à polyphonie limitée (VOICE_LIMITS), ou
## null si le son est inaudible (trop loin) ou moins prioritaire que les
## voix en cours du groupe (priorité à la proximité).
func _group_voice(group: String, pos: Vector3) -> AudioStreamPlayer3D:
	var ear: Variant = listener_position()
	var d := 0.0 if ear == null else pos.distance_to(ear)
	if d > MAX_DISTANCE:
		return null
	var count := 0
	var farthest: AudioStreamPlayer3D = null
	var far_d := -1.0
	for q in _pool_3d:
		if q.playing and _group_of.get(q, "") == group:
			count += 1
			var qd := 0.0 if ear == null else q.global_position.distance_to(ear)
			if qd > far_d:
				far_d = qd
				farthest = q
	if count < int(VOICE_LIMITS.get(group, 8)):
		var p := _pool_3d[_next_3d]
		_next_3d = (_next_3d + 1) % POOL_3D
		return p
	if farthest != null and d < far_d:
		farthest.stop()
		return farthest
	return null


## Nombre de voix en cours d'un groupe (tests).
func group_playing(group: String) -> int:
	var n := 0
	for q in _pool_3d:
		if q.playing and _group_of.get(q, "") == group:
			n += 1
	return n


## Son non spatialisé (arme du joueur local, interface...).
func play_2d(sound: String, volume_db := 0.0, pitch_jitter := 0.04, bus := "SFX", pitch := 1.0) -> void:
	var st := get_stream(sound)
	if st == null or _throttled(sound, 8):
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = st
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


func play_ui(sound: String, volume_db := 0.0) -> void:
	play_2d(sound, volume_db, 0.02, "UI")


## Musique / ambiance en boucle avec fondu enchaîné.
func play_music(sound: String, volume_db := 0.0, fade := 2.0) -> void:
	if sound == _music_name:
		return
	_music_name = sound
	var old := _music
	_music = _music_b
	_music_b = old
	if old.playing:
		var tw_out := create_tween()
		tw_out.tween_property(old, "volume_db", -60.0, fade)
		tw_out.tween_callback(old.stop)
	if sound == "":
		return
	var st := get_stream(sound)
	if st == null:
		return
	_music.stream = st
	_music.volume_db = -60.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", volume_db, fade)


func stop_music(fade := 1.5) -> void:
	play_music("", 0.0, fade)


## Coupe immédiatement tous les sons (sortie du jeu, fin d'autotest) et
## refuse toute nouvelle lecture : plus aucune ressource audio n'est
## référencée à la fermeture.
func stop_all() -> void:
	_shutdown = true
	for p in _pool_3d:
		p.stop()
		p.stream = null
	for p in _pool_2d:
		p.stop()
		p.stream = null
	for m in [_music, _music_b]:
		m.stop()
		m.stream = null
	_music_name = ""
	_cache.clear()
	_group_of.clear()
