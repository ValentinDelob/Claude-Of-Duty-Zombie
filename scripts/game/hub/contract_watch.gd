class_name ContractWatch
extends Node
## Surveillance des contrats actifs du joueur LOCAL pendant la partie
## (docs/HUB_PLAN.md D13, §5.6 ; enfant de Game, aucun message réseau, D12).
##
## À chaque échantillon reçu (LootSystem.loot_changed) : quand les
## échantillons du profil + ceux de la partie couvrent un contrat actif
## (ContractRules.goals_met), message UNIQUE par contrat et par partie, sobre,
## sous le compteur d'échantillons : « CONTRAT « … » : OBJECTIF ATTEINT » puis
## « évacuez pour garder vos échantillons » (ContractRules.goal_message, FR /
## EN). La partie continue (§4.2) ; le contrat ne se remet qu'au hub.
##
## Un contrat déjà couvert par le profil seul au début de la partie n'est
## jamais annoncé (il est déjà PRÊT au labo : évacuer n'y change rien).

## Durée d'affichage d'un message (s), fondus compris.
const SHOW_SEC := 7.0
const FADE_SEC := 0.6

var game: Game
var profile: PlayerProfile
var data: HubData
var day := -1
## Contrats déjà annoncés (ou couverts dès le départ) : id -> true.
var announced: Dictionary = {}
## Messages affichés pendant la partie, dans l'ordre (tests).
var shown: PackedStringArray = []
var _queue: Array = []
var _box: VBoxContainer
var _title: Label
var _sub: Label
var _t := 0.0


## Contrats actifs nouvellement couverts par profil + partie (`samples`),
## hors `already` (id -> true). Pure.
static func new_goals(pr: PlayerProfile, d: HubData, samples: Dictionary, today: int, already: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if pr == null or d == null or pr.contracts == null:
		return out
	for id in ContractRules.goals_met(pr, d, samples, today):
		if not already.has(id):
			out.append(id)
	return out


func _ready() -> void:
	game = get_parent() as Game
	if game == null:
		return  # test : setup() appelé à la main
	# Catalogue imposé par un test ou un scénario (HubContractsView), sinon les
	# fichiers livrés ; même jour que le hub.
	setup(ProfileStore.load_profile(), HubContractsView.data(), HubContractsView.today())
	if game and game.loot:
		game.loot.loot_changed.connect(check)


## Profil et catalogue suivis ; les contrats déjà couverts au départ sont
## marqués annoncés (jamais de message pour eux).
func setup(pr: PlayerProfile, d: HubData, today: int) -> void:
	profile = pr
	data = d
	day = today
	announced.clear()
	for id in new_goals(profile, data, {}, day, {}):
		announced[id] = true


## Échantillons de la partie du joueur local (copie du serveur).
func match_samples() -> Dictionary:
	return game.loot.my_samples if game and game.loot else {}


## Vérifie les contrats actifs avec les échantillons de la partie `samples`
## (par défaut ceux du joueur local) ; annonce les nouveaux couverts.
func check(samples: Variant = null) -> void:
	var s: Dictionary = samples if samples is Dictionary else match_samples()
	for id in new_goals(profile, data, s, day, announced):
		announced[id] = true
		var t := ContractRules.goal_message(data.contract(id))
		shown.append(t)
		_queue.append(t)
		print("[ContractWatch] %s" % t)
	if _t <= 0.0 and not _queue.is_empty():
		_show_next()


## Message affiché en ce moment ("" : aucun ; tests).
func current_text() -> String:
	if _box == null or not _box.visible:
		return ""
	return _title.text + " — " + _sub.text


func _show_next() -> void:
	var t: String = _queue.pop_front()
	if game == null or game.hud == null:
		return
	_ensure_box()
	var cut := t.find(" — ")
	_title.text = t.left(cut) if cut >= 0 else t
	var sub := t.substr(cut + 3) if cut >= 0 else ""
	_sub.text = sub.left(1).to_upper() + sub.substr(1)
	_box.visible = true
	_box.modulate.a = 0.0
	_t = SHOW_SEC
	Audio.play_2d("purchase", -10.0, 0.0)


func _process(delta: float) -> void:
	if _t <= 0.0:
		return
	_t -= delta
	if _box:
		var shown_for := SHOW_SEC - _t
		_box.modulate.a = clampf(minf(shown_for, _t) / FADE_SEC, 0.0, 1.0)
	if _t <= 0.0:
		if _box:
			_box.visible = false
		if not _queue.is_empty():
			_show_next()


## Encadré à droite, sous le compteur d'échantillons de la partie
## (LootSystem : 150 px du haut) : deux lignes, sans fond.
func _ensure_box() -> void:
	if _box:
		return
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 0)
	_box.anchor_left = 1.0
	_box.anchor_right = 1.0
	_box.offset_left = -620
	_box.offset_right = -24
	_box.offset_top = 176
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = HudStyle.label("", 18, HudStyle.ROUND, "text", 3)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_box.add_child(_title)
	_sub = HudStyle.label("", 15, HudStyle.TEXT_DIM, "text", 2)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_box.add_child(_sub)
	game.hud.add_child(_box)
