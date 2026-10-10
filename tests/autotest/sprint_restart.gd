extends AutotestScenario
## Course (BO1) : jamais de sprint qui repart tout seul. On ne court que
## touche de course ENFONCÉE (clavier) ou sprint verrouillé au clic de L3 ET
## en avançant ; le verrou tombe à l'arrêt, en reculant, en visant ; une
## course rendue impossible (visée, accroupi, à terre, énergie insuffisante,
## épuisement) ou interrompue (pause, menu, perte de focus, contrôle coupé)
## demande un NOUVEL appui : la touche gardée ou le verrou ne la relancent
## pas d'eux-mêmes une fois l'obstacle levé.
## Clavier : p.input.sprint = touche maintenue (joueur piloté par le script).
## Manette : PlayerInput.update_sprint à chaque image physique, comme
## read_devices (clic de L3 = `_click`).

var H := AutotestHelpers
var p: Player
## Manette simulée : la demande de course vient du verrou de L3.
var _pad := false
## Clic de L3 à la prochaine image physique.
var _click := false
## Images physiques passées en sprint depuis la dernière remise à zéro.
var _sprint_frames := 0


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self)
	if p == null:
		return
	Game.instance.rounds.paused = true
	await H.clear_zombies(self)
	p.untargetable = true
	tree().physics_frame.connect(_tick)
	await _keyboard_cases()
	await _pad_cases()
	await _interrupt_cases()
	tree().physics_frame.disconnect(_tick)
	_pad = false
	p.input = PlayerInput.new()


## Avant les _physics_process de l'image : manette simulée, bande de course
## bouclée (comme sprint_smooth), comptage des images en sprint.
func _tick() -> void:
	if _pad:
		p.input.update_sprint(false, _click)
		_click = false
	var gp := p.global_position
	if gp.x > 22.0: gp.x -= 18.0
	elif gp.x < 3.0: gp.x += 18.0
	if gp != p.global_position:
		p.global_position = gp
	if p.sprinting:
		_sprint_frames += 1


func _ticks(n: int) -> void:
	for i in n:
		await tree().physics_frame


## Départ : posé au bout de la bande de course, énergie pleine, rien d'appuyé.
func _reset(pad: bool) -> void:
	_pad = pad
	_click = false
	if p.downed:
		p.set_downed(false)
	p.input = PlayerInput.new()
	p.teleport_to(Vector3(3.0, 0.05, 3.4), -PI * 0.5)
	p.pitch = 0.0
	p.energy.value = p.energy.max_value
	p.energy.exhausted = false
	await seconds(0.3)


## Images en sprint pendant `s` secondes.
func _sprint_during(s: float) -> int:
	_sprint_frames = 0
	await seconds(s)
	return _sprint_frames


## En marche avant, lance le sprint (touche enfoncée ou clic de L3).
func _start_sprint(label: String) -> bool:
	p.input.move = Vector2(0, 1)
	if _pad:
		_click = true
	else:
		p.input.sprint = true
	await seconds(0.4)
	at.check(p.sprinting, "%s : le sprint part" % label)
	return p.sprinting


## Nouvel appui explicite : le sprint doit repartir.
func _repress(label: String) -> void:
	p.input.move = Vector2(0, 1)
	if _pad:
		_click = true
	else:
		p.input.sprint = false
		await _ticks(3)
		p.input.sprint = true
	await seconds(0.4)
	at.check(p.sprinting, "%s : un nouvel appui relance le sprint" % label)


func _no_restart(label: String, s := 0.8) -> void:
	var n := await _sprint_during(s)
	at.check(n == 0, "%s : pas de sprint sans nouvel appui (%d images en sprint)" % [label, n])


# --------------------------------------------------------------------------
# Clavier (touche maintenue)
# --------------------------------------------------------------------------

func _keyboard_cases() -> void:
	# Maj relâchée pendant l'arrêt : reprise de la marche, sans sprint.
	await _reset(false)
	await _start_sprint("clavier, Maj relâchée à l'arrêt")
	p.input.move = Vector2.ZERO
	await seconds(0.3)
	p.input.sprint = false
	await seconds(0.2)
	p.input.move = Vector2(0, 1)
	await _no_restart("clavier, Maj relâchée à l'arrêt")

	# Maj gardée enfoncée à l'arrêt : reprise en sprint (la touche est
	# ENFONCÉE : maintien explicite, comme voulu au clavier).
	await _reset(false)
	await _start_sprint("clavier, Maj gardée à l'arrêt")
	p.input.move = Vector2.ZERO
	await seconds(0.4)
	at.check(not p.sprinting, "clavier, Maj gardée : arrêté, plus de sprint")
	p.input.move = Vector2(0, 1)
	await seconds(0.3)
	at.check(p.sprinting, "clavier, Maj gardée à l'arrêt : la touche enfoncée fait courir")

	# Appui très bref : une image de sprint au plus, puis la marche.
	await _reset(false)
	p.input.move = Vector2(0, 1)
	await seconds(0.3)
	p.input.sprint = true
	await _ticks(1)
	p.input.sprint = false
	await seconds(0.1)
	await _no_restart("clavier, appui très bref", 0.6)

	# Souffle insuffisant au moment d'appuyer : la touche gardée ne lance
	# pas la course quand l'énergie remonte.
	await _reset(false)
	p.energy.value = 5.0
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await _no_restart("clavier, Maj gardée sans souffle", 1.2)
	await _repress("clavier, sans souffle")

	# Visée (ADS) en pleine course : elle coupe le sprint ; en relâchant la
	# visée, Maj toujours enfoncée (retenir son souffle), pas de reprise.
	await _reset(false)
	await _start_sprint("clavier, visée")
	p.input.aim = true
	await seconds(0.3)
	at.check(not p.sprinting and p.aiming, "clavier : viser coupe le sprint (sprint %s, visée %s)" % [p.sprinting, p.aiming])
	p.input.aim = false
	await _no_restart("clavier, fin de visée")
	await _repress("clavier, après la visée")

	# Accroupi, Maj enfoncée : en se relevant, pas de sprint.
	await _reset(false)
	p.input.crouch = true
	p.input.move = Vector2(0, 1)
	await seconds(0.3)
	p.input.sprint = true
	await seconds(0.3)
	p.input.crouch = false
	await _no_restart("clavier, relevé")
	await _repress("clavier, relevé")

	# À terre puis réanimé, Maj enfoncée tout du long.
	await _reset(false)
	await _start_sprint("clavier, à terre")
	p.set_downed(true)
	await seconds(0.4)
	at.check(not p.sprinting, "clavier : à terre, pas de sprint")
	p.set_downed(false)
	await _no_restart("clavier, réanimé")
	await _repress("clavier, réanimé")

	# Épuisement : Maj gardée, retour à la marche ; il faut relâcher puis
	# réappuyer (comportement voulu, inchangé), une fois l'épuisement fini
	# (énergie remontée à PlayerEnergy.RECOVER_AT).
	await _reset(false)
	p.energy.value = 15.0
	await _start_sprint("clavier, épuisement")
	await seconds(0.4)
	await _no_restart("clavier, épuisé, Maj gardée", 1.0)
	await until(func(): return not p.energy.exhausted, 4.0, "clavier : fin de l'épuisement")
	await _no_restart("clavier, reposé, Maj gardée", 0.3)
	await _repress("clavier, après l'épuisement")


# --------------------------------------------------------------------------
# Manette (sprint verrouillé au clic de L3)
# --------------------------------------------------------------------------

func _pad_cases() -> void:
	# Arrêt (stick relâché) : le verrou tombe.
	await _reset(true)
	await _start_sprint("manette, arrêt")
	p.input.move = Vector2.ZERO
	await seconds(0.3)
	p.input.move = Vector2(0, 1)
	await _no_restart("manette, arrêt")
	await _repress("manette, arrêt")

	# Recul : le verrou tombe.
	await _reset(true)
	await _start_sprint("manette, recul")
	p.input.move = Vector2(0, -1)
	await seconds(0.2)
	p.input.move = Vector2(0, 1)
	await _no_restart("manette, recul")

	# Pas de côté (stick sur le côté) : le verrou tombe.
	await _reset(true)
	await _start_sprint("manette, de côté")
	p.input.move = Vector2(1, 0.1)
	await seconds(0.2)
	p.input.move = Vector2(0, 1)
	await _no_restart("manette, de côté")

	# Tourner (stick droit) en avançant : le sprint continue.
	await _reset(true)
	await _start_sprint("manette, virage")
	for i in 20:
		p.yaw -= 0.05
		p.rotation.y = p.yaw
		await _ticks(1)
	at.check(p.sprinting, "manette : tourner en avançant garde le sprint")

	# Visée : coupe le sprint et le verrou ; pas de reprise en fin de visée
	# (ni après un clic de L3 pour retenir son souffle).
	await _reset(true)
	await _start_sprint("manette, visée")
	p.input.aim = true
	await seconds(0.2)
	_click = true  # retenir son souffle
	await seconds(0.2)
	at.check(not p.sprinting and p.aiming, "manette : viser coupe le sprint (sprint %s, visée %s)" % [p.sprinting, p.aiming])
	p.input.aim = false
	await _no_restart("manette, fin de visée")
	await _repress("manette, après la visée")

	# Clic sans souffle : rien, et pas de départ quand l'énergie remonte.
	await _reset(true)
	p.energy.value = 5.0
	p.input.move = Vector2(0, 1)
	await seconds(0.1)
	_click = true
	await _no_restart("manette, clic sans souffle", 1.2)
	await _repress("manette, sans souffle")

	# Clic accroupi : en se relevant, pas de sprint.
	await _reset(true)
	p.input.crouch = true
	p.input.move = Vector2(0, 1)
	await seconds(0.3)
	_click = true
	await seconds(0.3)
	p.input.crouch = false
	await _no_restart("manette, relevé")

	# À terre puis réanimé, stick toujours en avant.
	await _reset(true)
	await _start_sprint("manette, à terre")
	p.set_downed(true)
	await seconds(0.4)
	p.set_downed(false)
	await _no_restart("manette, réanimé")

	# Épuisement : le verrou se relâche, marche jusqu'au prochain clic.
	await _reset(true)
	p.energy.value = 15.0
	await _start_sprint("manette, épuisement")
	await seconds(0.4)
	await _no_restart("manette, épuisé", 1.0)
	await until(func(): return not p.energy.exhausted, 4.0, "manette : fin de l'épuisement")
	await _no_restart("manette, reposé", 0.3)
	await _repress("manette, après l'épuisement")


# --------------------------------------------------------------------------
# Interruptions : pause, menu, perte de focus, contrôle coupé
# --------------------------------------------------------------------------

func _interrupt_cases() -> void:
	var menu: PauseMenu = Game.instance.hud.pause_menu
	# Pause solo (arbre en pause), touche gardée / stick en avant tout du long.
	for pad in [false, true]:
		var dev: String = "manette" if pad else "clavier"
		await _reset(pad)
		await _start_sprint("%s, pause" % dev)
		menu.open()
		await seconds(0.3)
		menu.close()
		await _no_restart("%s, après la pause" % dev)
		await _repress("%s, après la pause" % dev)

	# Menu ouvert sans pause (multijoueur : la partie continue) : la
	# lecture des commandes s'arrête ; à la fermeture, touche encore enfoncée.
	await _reset(false)
	await _start_sprint("clavier, menu")
	p.bot_controlled = false
	menu.visible = true
	await seconds(0.3)
	menu.visible = false
	p.bot_controlled = true
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await _no_restart("clavier, après le menu")
	await _repress("clavier, après le menu")

	# Perte de focus de la fenêtre (Alt+Tab) puis retour.
	for pad in [false, true]:
		var dev: String = "manette" if pad else "clavier"
		await _reset(pad)
		await _start_sprint("%s, focus" % dev)
		p.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await seconds(0.2)
		p.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await _no_restart("%s, retour de focus" % dev)
		await _repress("%s, retour de focus" % dev)

	# Contrôle coupé (mort, cinématique) puis rendu, touche enfoncée.
	await _reset(false)
	await _start_sprint("clavier, contrôle coupé")
	p.input_enabled = false
	await seconds(0.2)
	p.input_enabled = true
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await _no_restart("clavier, contrôle rendu")
	await _repress("clavier, contrôle rendu")
