class_name PerkSystem
extends Node
## Octroi et retrait des atouts (chemin réseau : /root/Game/Perks).
## Le serveur modifie PlayerData.perks et les stats dérivées ; tout le monde
## reçoit l'événement (animation de boisson, icônes du HUD).

const DRINK_TIME := 2.3

var game: Game
## Solo : nombre d'achats de LAZARUS TONIC (limités à PerkDB.SOLO_REVIVE_LIMIT).
var solo_revive_buys := 0
## Serveur : dernière explosion de NOVA FLOP par joueur (pid -> s).
var _nova_last := {}


func _ready() -> void:
	game = get_parent()
	game.get_node("Combat").player_dived_landed.connect(_on_dived_landed)


## Serveur : donne un atout (achat déjà validé).
func srv_grant(pid: int, perk: String) -> void:
	var pd := game.session.get_data(pid)
	if pd == null or pd.has_perk(perk):
		return
	pd.perks.append(perk)
	if perk == "lazarus" and Net.mode == Net.Mode.SOLO:
		solo_revive_buys += 1
	_apply_stats(pd)
	pd.health = pd.max_health
	game.session.sync_stats(pid)
	_cl_granted.rpc(pid, perk)
	# Boire interrompt le rechargement (BO1), ici comme chez le client
	# (WeaponController.drink) : après _cl_granted, pour que le client arrête
	# sa prédiction avant de recevoir l'inventaire corrigé.
	game.combat.srv_hands_busy(pid, DRINK_TIME)
	VoxSystem.say_later(2.6, pid, "perk_" + perk)
	print("[Perks] %s boit %s" % [Net.player_name(pid), PerkDB.display_name(perk)])


## Serveur : retire tous les atouts (joueur à terre ou mort).
func srv_clear(pid: int) -> void:
	var pd := game.session.get_data(pid)
	if pd == null or pd.perks.is_empty():
		return
	pd.perks = PackedStringArray()
	_apply_stats(pd)
	pd.health = mini(pd.health, pd.max_health)
	game.session.sync_stats(pid)


func _apply_stats(pd: PlayerData) -> void:
	pd.max_health = PerkDB.max_health(pd)


@rpc("authority", "call_local", "reliable")
func _cl_granted(pid: int, perk: String) -> void:
	var p: Player = game.players.get(pid)
	if p == null:
		return
	Audio.play_3d("perk_drink", p.global_position + Vector3.UP * 1.5, -2.0, 0.05)
	if p.is_local:
		Audio.play_2d("jingle_" + perk, -6.0, 0.0)
		if p.weapons:
			p.weapons.drink(PerkDB.color(perk), DRINK_TIME)
		game.hud.show_banner(PerkDB.display_name(perk), 1.5)


## Effets de déplacement appliqués au joueur local (lus depuis les stats).
func apply_local_effects(p: Player) -> void:
	var pd := game.session.get_data(p.peer_id)
	if pd == null:
		return
	p.speed_multiplier = PerkDB.speed_mult(pd)
	# STRIDE SODA : ses secondes de sprint en plus deviennent de l'énergie max
	# (une seconde de course = PlayerEnergy.SPRINT_COST).
	p.energy.set_bonus_max(PerkDB.sprint_bonus(pd) * PlayerEnergy.SPRINT_COST)


# ---- NOVA FLOP : plongeon explosif (serveur), effets (tous)

## Serveur : un joueur a atterri d'un plongeon (Combat.srv_dive_landed a déjà
## borné position et hauteur). Explosion de zone : les kills rapportent comme
## une explosion (HitKind.SPLASH), aucun dégât au plongeur ni aux coéquipiers.
func _on_dived_landed(pid: int, pos: Vector3, height: float) -> void:
	var pd := game.session.get_data(pid)
	if not PerkDB.nova_triggers(pd, height):
		return
	var t := GameClock.now()
	if t - float(_nova_last.get(pid, -INF)) < PerkDB.NOVA_COOLDOWN:
		return
	_nova_last[pid] = t
	print("[Perks] %s : plongeon explosif NOVA FLOP en %s (chute %.2f m)" % [Net.player_name(pid), pos, height])
	game.combat.explosion(pid, pos + Vector3.UP * 0.3, PerkDB.NOVA_RADIUS, PerkDB.NOVA_DAMAGE, 0)
	_cl_nova_blast.rpc(pos)


@rpc("authority", "call_local", "reliable")
func _cl_nova_blast(pos: Vector3) -> void:
	NovaFx.play(game, pos)
