class_name ThrowableRules
extends RefCounted
## Règles des objets de l'emplacement de grenade (fonctions pures, testées
## unitairement) : grenades à fragmentation et PELUCHE LEURRE (ancien
## singe-tambour). Ces objets ne passent jamais dans l'arsenal ; on les
## obtient à la caisse au hasard (GAME_CONCEPT §4.12 bis), plus une dotation
## gratuite de grenades (provisoire).

enum Kind { FRAG, DECOY }

# ---------------------------------------------------------------- emplacement
## L'emplacement de grenade ne contient qu'une sorte d'objet à la fois, au plus
## SLOT_MAX (le maximum historique des grenades).
const SLOT_MAX := 4
## Dotation gratuite (PROVISOIRE) : grenades au début de la partie et gain au
## début de chaque manche, tant que l'emplacement contient des grenades ou est
## vide. FRAG_MAX : alias de SLOT_MAX pour les grenades.
const FRAG_START := 2
const FRAG_PER_ROUND := 2
const FRAG_MAX := SLOT_MAX

# ---------------------------------------------------------------- caisse
## Objets que la caisse au hasard peut donner : identifiant, sorte (Kind) et
## poids du tirage. Pour ajouter un objet : une entrée ici, puis sa sorte dans
## Kind, son modèle (Throwable.build_model), son effet (ThrowableSystem) et ses
## noms (NAMES).
const CRATE_ITEMS := [
	{"id": "frag", "kind": Kind.FRAG, "weight": 1.0},
	{"id": "decoy", "kind": Kind.DECOY, "weight": 1.0},
]
## Noms affichés par sorte d'objet.
const NAMES := {
	Kind.FRAG: {"fr": "GRENADE", "en": "GRENADE"},
	Kind.DECOY: {"fr": "PELUCHE LEURRE", "en": "DECOY TEDDY"},
}

# ---------------------------------------------------------------- grenade
## Mèche : comptée depuis le dégoupillage (maintenir la touche = « cuire »).
const FUSE := 4.0
## Rayon et dégâts de l'explosion (au centre ; 50 % au bord). Tue en un coup
## jusqu'aux manches 10-11 à 1 m du point d'impact (1045 / 1149 PV).
const FRAG_RADIUS := 5.0
const FRAG_DAMAGE := 1300
## Dégâts subis par le lanceur (réduits, comme BO1 ; jamais aux coéquipiers).
const FRAG_SELF_DAMAGE := 80

# ---------------------------------------------------------------- peluche leurre
## Durée de la musique : tous les zombies convergent vers la peluche.
const DECOY_TIME := 8.0
## Explosion finale : tue tout ce qui l'entoure, quelle que soit la manche.
const DECOY_RADIUS := 4.5
const DECOY_DAMAGE := 100000
const DECOY_SELF_DAMAGE := 60
## Les zombies arrivés à cette distance de la peluche l'encerclent sans avancer.
const LURE_STOP := 1.1

# ---------------------------------------------------------------- lancer
## Vitesse de lancer (m/s) et composante verticale ajoutée (lancer en cloche).
const FRAG_SPEED := 15.0
const DECOY_SPEED := 10.5
const THROW_LIFT := 2.6
const GRAVITY := 14.0
const RADIUS := 0.05
## Rebond : part de la vitesse normale conservée, perte tangentielle.
const RESTITUTION := 0.42
const TANGENT_LOSS := 0.3
## Roulement au sol : freinage proportionnel (1/s) et constant (m/s²).
const ROLL_FRICTION := 1.6
const ROLL_DECEL := 5.0


## Réserve de grenades après le début d'une manche (+2, plafonnée à 4).
static func frags_after_round(current: int) -> int:
	return mini(maxi(current, 0) + FRAG_PER_ROUND, FRAG_MAX)


## L'emplacement reçoit-il la dotation de grenades (grenades, ou vide) ?
static func gets_free_frags(kind: int, count: int) -> bool:
	return kind == Kind.FRAG or count <= 0


## Objet de la caisse d'identifiant `id` ({} si inconnu).
static func crate_item(id: String) -> Dictionary:
	for it: Dictionary in CRATE_ITEMS:
		if it.id == id:
			return it
	return {}


## Tirage pondéré d'un objet de la caisse (identifiant).
static func pick_crate_item(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for it: Dictionary in CRATE_ITEMS:
		total += float(it.weight)
	var r := rng.randf() * total
	for it: Dictionary in CRATE_ITEMS:
		r -= float(it.weight)
		if r <= 0.0:
			return it.id
	return CRATE_ITEMS[CRATE_ITEMS.size() - 1].id


## Temps restant avant l'explosion d'une grenade dégoupillée à `cook_start`.
static func fuse_left(cook_start: float, now: float) -> float:
	return FUSE - (now - cook_start)


## Vitesse initiale d'un objet lancé dans la direction `dir` (visée).
static func throw_velocity(kind: int, dir: Vector3) -> Vector3:
	var speed := FRAG_SPEED if kind == Kind.FRAG else DECOY_SPEED
	return dir.normalized() * speed + Vector3.UP * THROW_LIFT


## Dégâts d'explosion à la distance `d` du centre (décroissance linéaire de
## 100 % à 50 % au bord, 0 au-delà).
static func splash(damage: int, radius: float, d: float) -> int:
	if d > radius or radius <= 0.0:
		return 0
	return int(float(damage) * (1.0 - d / radius * 0.5))


## Rebond d'une vitesse `vel` sur une surface de normale `n`.
static func bounce(vel: Vector3, n: Vector3) -> Vector3:
	var vn := vel.dot(n)
	if vn >= 0.0:
		return vel
	var normal := n * vn
	var tangent := vel - normal
	return tangent * (1.0 - TANGENT_LOSS) - normal * RESTITUTION


## Nom affiché d'une sorte d'objet, dans la langue du joueur.
static func kind_name(kind: int) -> String:
	return Lang.pick(NAMES.get(kind, NAMES[Kind.FRAG]))
