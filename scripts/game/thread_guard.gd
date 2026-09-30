class_name ThreadGuard
extends RefCounted
## Règle des fils de travail (docs/ARCHITECTURE.md, « Fils de travail ») : un
## calcul lancé hors du fil principal (Thread, WorkerThreadPool) ne touche à
## AUCUN état partagé modifiable : ni cache statique (`static var`), ni
## autoload (Settings...), ni ressource, ni nœud. Ce dont il a besoin est
## préparé par le fil principal AVANT le lancement et ne change plus pendant
## le calcul (copie profonde de la carte, catalogue figé en lecture seule,
## langue), ou recalculé localement (sans cache).
##
## Les caches statiques du fil principal appellent main_only() : hors du fil
## principal, l'accès est REFUSÉ (le cache n'est ni lu ni écrit) et noté ; le
## fil principal relève les accès notés (take_violations) et les signale
## (MapPreviewWorld, tests). Tout l'état de ce fichier est protégé par un verrou.

static var _mutex := Mutex.new()
static var _violations := PackedStringArray()
## Langue de chaque calcul en cours (id du fil -> anglais ?), figée par le fil
## principal au lancement : Lang.t n'y lit jamais Settings.
static var _lang := {}


## Appelé hors du fil principal ?
static func worker() -> bool:
	return OS.get_thread_caller_id() != OS.get_main_thread_id()


## Accès à un état réservé au fil principal (`what` : nom du cache) : vrai sur
## le fil principal ; dans un fil de travail, faux (l'appelant n'y touche pas)
## et l'accès est noté.
static func main_only(what: String) -> bool:
	if not worker():
		return true
	_note(what)
	return false


static func _note(what: String) -> void:
	_mutex.lock()
	if _violations.size() < 200:
		_violations.append(what)
	_mutex.unlock()


## Accès refusés notés depuis le dernier relevé (vidés).
static func take_violations() -> PackedStringArray:
	_mutex.lock()
	var out := _violations.duplicate()
	_violations.clear()
	_mutex.unlock()
	return out


## Début d'un calcul dans un fil de travail (appelé DANS le fil) : sa langue,
## lue par le fil principal avant le lancement.
static func enter(lang_en: bool) -> void:
	_mutex.lock()
	_lang[OS.get_thread_caller_id()] = lang_en
	_mutex.unlock()


## Fin du calcul (appelé dans le fil).
static func leave() -> void:
	_mutex.lock()
	_lang.erase(OS.get_thread_caller_id())
	_mutex.unlock()


## Langue du calcul en cours dans ce fil de travail (Lang.is_en). Un fil qui
## n'a pas appelé enter() : accès noté, français.
static func worker_lang_en() -> bool:
	var id := OS.get_thread_caller_id()
	_mutex.lock()
	var known := _lang.has(id)
	var en: bool = _lang.get(id, false)
	_mutex.unlock()
	if not known:
		_note("Settings.language (Lang.t dans un fil sans enter)")
	return en
