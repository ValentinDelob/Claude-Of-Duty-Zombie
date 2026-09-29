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

## Coordonnée la plus grande acceptée (m) : aucune carte n'en approche.
const MAX_COORD := 100000.0


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


## Seau de jetons par joueur et par type de message : `rate` messages par
## seconde en moyenne, rafale de `burst`. Protège le serveur (et, par
## ricochet, les autres clients) d'une inondation de requêtes.
class Limiter:
	var rate: float
	var burst: float
	var _tokens := {}   # clé -> jetons restants
	var _t := {}        # clé -> instant du dernier remplissage (s)

	func _init(per_second: float, burst_size: float) -> void:
		rate = per_second
		burst = burst_size

	## Vrai si le message de `pid` est accepté ; `now` en secondes (tests).
	func allow(pid: int, now := -1.0) -> bool:
		var t := now if now >= 0.0 else Time.get_ticks_msec() / 1000.0
		var tokens: float = minf(float(_tokens.get(pid, burst)) + (t - float(_t.get(pid, t))) * rate, burst)
		_t[pid] = t
		if tokens < 1.0:
			_tokens[pid] = tokens
			return false
		_tokens[pid] = tokens - 1.0
		return true

	func forget(pid: int) -> void:
		_tokens.erase(pid)
		_t.erase(pid)
