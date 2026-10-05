class_name NetGuard
extends RefCounted
## Garde-fous des messages réseau reçus (fonctions pures, testées dans
## tests/test_security.gd). Voir docs/SECURITY.md, « Règles pour tout RPC ».
##
## Un client malveillant peut envoyer n'importe quelle valeur dans un RPC :
## NaN ou infini (toutes les comparaisons « > » deviennent fausses et
## contournent les contrôles de distance), vecteurs nuls, tableaux immenses.
## Chaque RPC « any_peer » passe ses arguments par ces fonctions AVANT de
## s'en servir.

## Coordonnée la plus grande acceptée (m) : garde contre les valeurs absurdes,
## bien au-delà de toute carte que le validateur accepte (format 17 : pas
## d'étendue maximale, mais une grille limitée par la mémoire, moins de 200 km).
const MAX_COORD := 1000000.0


## Vrai si le nombre est fini (ni NaN ni infini) et raisonnable.
static func finite(f: float) -> bool:
	return is_finite(f) and absf(f) <= MAX_COORD


## Vrai si les trois composantes sont finies et raisonnables.
static func finite_vec(v: Vector3) -> bool:
	return finite(v.x) and finite(v.y) and finite(v.z)


## Direction utilisable : finie et non nulle.
static func valid_dir(v: Vector3) -> bool:
	return finite_vec(v) and v.length_squared() > 0.0001


## Copie bornée d'un tableau de vecteurs : au plus `max_n` éléments, en
## s'arrêtant au premier vecteur non fini. `pairs` : garde un nombre pair
## d'éléments (paires position / normale).
static func clean_vecs(a: PackedVector3Array, max_n: int, pairs := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in a:
		if out.size() >= max_n or not finite_vec(v):
			break
		out.append(v)
	if pairs and out.size() % 2 == 1:
		out.resize(out.size() - 1)
	return out


## Distance du point `p` au rayon (origine, direction unitaire), et abscisse
## le long du rayon : [distance, abscisse]. Abscisse négative : derrière.
static func ray_distance(origin: Vector3, dir: Vector3, p: Vector3) -> Vector2:
	var to := p - origin
	var along := to.dot(dir)
	return Vector2((to - dir * along).length(), along)


## Nom de fichier ou de catégorie venu du réseau : lettres minuscules,
## chiffres et « _ » seulement (jamais de « / », « . » ni « : »).
static func safe_token(s: String, max_len := 48) -> bool:
	if s.is_empty() or s.length() > max_len:
		return false
	for c in s:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## Aucun expéditeur valable : le RPC est ignoré (valeur des *_sender).
const NO_SENDER := -1


## Prologue d'un RPC client -> serveur (docs/SECURITY.md, règles 1, 2 et 5) :
## l'identifiant de l'expéditeur, ou NO_SENDER si cette machine n'est pas le
## serveur ou si `limiter` (facultatif) refuse le message.
static func server_sender(node: Node, limiter: Limiter = null) -> int:
	var mp := node.multiplayer
	if not mp.is_server():
		return NO_SENDER
	var pid := mp.get_remote_sender_id()
	if limiter != null and not limiter.allow(pid):
		return NO_SENDER
	return pid


## Comme server_sender, et l'expéditeur est un joueur de la partie : ses
## données de session existent et, si `need_player`, son nœud Player aussi.
static func known_sender(node: Node, game: Game, limiter: Limiter = null, need_player := true) -> int:
	var pid := server_sender(node, limiter)
	if pid == NO_SENDER or game.session.get_data(pid) == null or (need_player and not game.players.has(pid)):
		return NO_SENDER
	return pid


## Comme known_sender, et le joueur est vivant (ni à terre ni mort).
static func alive_sender(node: Node, game: Game, limiter: Limiter = null, need_player := true) -> int:
	var pid := known_sender(node, game, limiter, need_player)
	if pid == NO_SENDER or game.session.get_data(pid).life != PlayerData.Life.ALIVE:
		return NO_SENDER
	return pid


## Seau de jetons par joueur et par type de message : `rate` messages par
## seconde en moyenne, rafale de `burst`. Protège le serveur (et, par
## ricochet, les autres clients) d'une inondation de requêtes. Seule
## implémentation du projet : la cadence de tir de Combat s'en sert aussi,
## avec un débit propre à l'arme en main (take).
class Limiter:
	var rate: float
	var burst: float
	var _tokens := {}   # clé -> jetons restants
	var _t := {}        # clé -> instant du dernier remplissage (s)

	func _init(per_second: float, burst_size: float) -> void:
		rate = per_second
		burst = burst_size

	## Vrai si le message de `pid` est accepté ; `now` en secondes (tests),
	## temps réel par défaut.
	func allow(pid: int, now := -1.0) -> bool:
		return take(pid, now if now >= 0.0 else Time.get_ticks_msec() / 1000.0, rate)

	## Prend un jeton pour `pid` à l'instant `t` (s), le seau se remplissant de
	## `per_second` jetons par seconde depuis l'appel précédent, jusqu'à
	## `cap` jetons (`burst` si négatif). Vrai si accepté.
	func take(pid: int, t: float, per_second: float, cap := -1.0) -> bool:
		var size := cap if cap >= 0.0 else burst
		var tokens: float = minf(float(_tokens.get(pid, size)) + (t - float(_t.get(pid, t))) * per_second, size)
		_t[pid] = t
		if tokens < 1.0:
			_tokens[pid] = tokens
			return false
		_tokens[pid] = tokens - 1.0
		return true

	func forget(pid: int) -> void:
		_tokens.erase(pid)
		_t.erase(pid)
