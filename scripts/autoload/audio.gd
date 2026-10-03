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
## Fondu en cours de chaque lecteur de musique (lecteur -> Tween) : un
## lecteur relancé perd le fondu de sortie qui allait l'arrêter.
var _fades: Dictionary = {}
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

## Voix des personnages : bus « Voice » (réglage « VOIX DES PERSONNAGES »). Elles
## sont simplement mixées plus fort que le reste (VoxSystem.VOLUME_2D / VOLUME_3D) ;
## les autres sons ne baissent JAMAIS quand un personnage parle (choix de
## l'utilisateur : une baisse dénature le jeu).
const VOICE_BUS := "Voice"


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
	_setup_voice_bus()
	_preload_all()


## Sons chargés en tâche de fond dès le lancement (chemin -> nom) : sans cela,
## le premier « zombie_attack_3 », « flesh_hit_2 »... de la partie chargeait
## son fichier au moment de le jouer (≈ 0,9 ms par son, en pleine mêlée).
var _pending: Dictionary = {}


func _preload_all() -> void:
	var names := {}
	for f in DirAccess.get_files_at(DIR):
		# Jeu exporté : seuls les « .wav.import » sont listés.
		var n := f.trim_suffix(".import")
		if n.ends_with(".wav"):
			names[n.get_basename()] = true
	for sound: String in names:
		var path := DIR + sound + ".wav"
		if ResourceLoader.load_threaded_request(path, "AudioStream") == OK:
			_pending[sound] = path


## Bus « Voice » (default_bus_layout.tres), recréé s'il manque. Retire tout
## ancien effet de baisse (« Duck ») des bus SFX et Music.
func _setup_voice_bus() -> void:
	if AudioServer.get_bus_index(VOICE_BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, VOICE_BUS)
		AudioServer.set_bus_send(i, "Master")
	for bus in ["SFX", "Music"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		for e in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
			if AudioServer.get_bus_effect(idx, e).resource_name == "Duck":
				AudioServer.remove_bus_effect(idx, e)


## Déclare un lecteur de réplique (VoxSystem) : il joue sur le bus Voice.
func track_voice(p: Node) -> void:
	p.set("bus", VOICE_BUS)


func get_stream(sound: String) -> AudioStream:
	if _shutdown:
		return null
	if _cache.has(sound):
		return _cache[sound]
	var path := DIR + sound + ".wav"
	var st: AudioStream = null
	if _pending.has(sound):
		# Déjà chargé en tâche de fond (sinon : attend la fin de son chargement).
		st = ResourceLoader.load_threaded_get(_pending[sound]) as AudioStream
		_pending.erase(sound)
	elif ResourceLoader.exists(path):
		st = load(path)
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
	@warning_ignore("incompatible_ternary")
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
		_set_fade(old, tw_out)
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
	var tw_in := create_tween()
	_set_fade(_music, tw_in)
	tw_in.tween_property(_music, "volume_db", volume_db, fade)


func stop_music(fade := 1.5) -> void:
	play_music("", 0.0, fade)


## Fondu `tw` du lecteur `p` : celui qu'il avait est arrêté (sans quoi un fondu
## de sortie encore en cours couperait la musique que l'on vient d'y relancer).
func _set_fade(p: AudioStreamPlayer, tw: Tween) -> void:
	var prev: Tween = _fades.get(p)
	if prev != null and prev.is_valid():
		prev.kill()
	_fades[p] = tw


## Coupe la musique tout de suite, sans fondu (entrée dans l'éditeur de
## cartes : aucune musique n'y est jouée) ; la prochaine play_music la
## relance normalement (retour au menu principal).
func cut_music() -> void:
	for t: Tween in _fades.values():
		if t.is_valid():
			t.kill()
	_fades.clear()
	for m in [_music, _music_b]:
		m.stop()
		m.stream = null
	_music_name = ""


## Arrête les sons 2D en cours dont le nom commence par `prefix` (ex.
## « menu_ » : râle de la silhouette, souffle des transitions du menu).
func stop_sounds(prefix: String) -> void:
	for p in _pool_2d:
		if p.playing and p.stream != null and p.stream.resource_path.get_file().begins_with(prefix):
			p.stop()


## Musique en cours ("" : aucune).
func music_name() -> String:
	return _music_name


## Un lecteur de musique joue-t-il encore (fondu de sortie compris) ?
func music_playing() -> bool:
	return _music.playing or _music_b.playing


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
	# Chargements en tâche de fond : récupérés (fin d'attente) puis lâchés,
	# pour que le chargeur ne garde aucun son à la fermeture.
	for sound: String in _pending:
		ResourceLoader.load_threaded_get(_pending[sound])
	_pending.clear()
	_cache.clear()
	_group_of.clear()
