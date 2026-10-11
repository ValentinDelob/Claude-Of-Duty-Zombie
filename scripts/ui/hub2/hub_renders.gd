class_name HubRenders
extends RefCounted
## Rendus Blender des modèles en cubes affichés par le hub (docs/hub_v2) :
## armes, ennemis, échantillons, joueur et Dr Brown. Images régénérées par
## `sh tools/hub_renders.sh` dans assets/ui/hub/renders/ :
##   weapons/<modèle>.png       560 × 280, canon vers la droite
##   enemies/<type>.png         600 × 720, 3/4 face (types du codex)
##   samples/<sorte>.png        512 × 512 (LootRules.SAMPLES)
##   characters/<nom>.png       joueur 600 × 720, scientist_hero 1400 × 1800,
##                              scientist_bust 900 × 900
## Images importées sans perte avec mipmaps : un TextureRect qui les réduit
## (taille logique 1280 × 720) prend `texture_filter = FILTER`.
##
## Ennemi INCONNU du codex : même image, teinte noire dans l'interface
## (modulate noir), aucun rendu dédié.
##
## Joueur à la couleur d'un joueur : poser `player_team_mask` (seulement la
## zone d'équipe, blanche à pleine teinte, le reste transparent) par-dessus
## `player_neutral`, avec modulate = HudStyle.player_color(emplacement) :
## même teinte qu'en jeu (assets/shaders/player_voxel.gdshader : zone grise
## × team_color). `player` = déjà à la couleur du joueur 1 (ambre).
##
## Identifiant sans image : une texture vide (transparente) et un
## avertissement unique dans le journal, jamais d'erreur ni de null.

const ROOT := "res://assets/ui/hub/renders/"
const WEAPONS_DIR := ROOT + "weapons/"
const ENEMIES_DIR := ROOT + "enemies/"
const SAMPLES_DIR := ROOT + "samples/"
const CHARACTERS_DIR := ROOT + "characters/"

## Filtre à donner aux contrôles qui réduisent ces images.
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Tailles des rendus (px).
const WEAPON_SIZE := Vector2i(560, 280)
const ENEMY_SIZE := Vector2i(600, 720)
const SAMPLE_SIZE := Vector2i(512, 512)

## Personnages.
const PLAYER := "player"
const PLAYER_NEUTRAL := "player_neutral"
const PLAYER_TEAM_MASK := "player_team_mask"
const SCIENTIST_HERO := "scientist_hero"
const SCIENTIST_BUST := "scientist_bust"
const CHARACTERS := [PLAYER, PLAYER_NEUTRAL, PLAYER_TEAM_MASK, SCIENTIST_HERO, SCIENTIST_BUST]
const CHARACTER_SIZES := {
	PLAYER: Vector2i(600, 720), PLAYER_NEUTRAL: Vector2i(600, 720), PLAYER_TEAM_MASK: Vector2i(600, 720),
	SCIENTIST_HERO: Vector2i(1400, 1800), SCIENTIST_BUST: Vector2i(900, 900),
}

## Objets lancés (ThrowableRules.CRATE_ITEMS) : identifiant -> modèle.
const THROWABLE_MODELS := {"frag": "frag", "decoy": "teddy"}

static var _cache := {}
static var _warned := {}
static var _empty: Texture2D


## Modèle en cubes d'une arme (WeaponDB, KnifeDB) ou d'un objet lancé.
static func weapon_model(id: String) -> String:
	if WeaponDB.exists(id):
		return String(WeaponDB.stats(id).get("model", id))
	if KnifeDB.exists(id):
		return String(KnifeDB.info(id).get("model", id))
	return String(THROWABLE_MODELS.get(id, id))


static func weapon_path(id: String) -> String:
	return WEAPONS_DIR + weapon_model(id) + ".png"


## `type` : identifiant du codex (CodexData, XpRules : walker, crawler, dog…).
static func enemy_path(type: String) -> String:
	return ENEMIES_DIR + type + ".png"


## `id` : sorte d'échantillon (LootRules.SAMPLES).
static func sample_path(id: String) -> String:
	return SAMPLES_DIR + id + ".png"


## `name` : une des constantes CHARACTERS.
static func character_path(name: String) -> String:
	return CHARACTERS_DIR + name + ".png"


static func has(path: String) -> bool:
	return ResourceLoader.exists(path)


static func weapon(id: String) -> Texture2D:
	return texture(weapon_path(id))


static func enemy(type: String) -> Texture2D:
	return texture(enemy_path(type))


static func sample(id: String) -> Texture2D:
	return texture(sample_path(id))


static func character(name: String) -> Texture2D:
	return texture(character_path(name))


## Texture d'un rendu (gardée en mémoire) ; texture vide si l'image manque.
static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if has(path):
		tex = load(path) as Texture2D
	if tex == null:
		if not _warned.has(path):
			_warned[path] = true
			push_warning("HubRenders : rendu absent %s (sh tools/hub_renders.sh)" % path)
		return empty()
	_cache[path] = tex
	return tex


## Texture de repli : 4 × 4 transparente.
static func empty() -> Texture2D:
	if _empty == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_empty = ImageTexture.create_from_image(img)
	return _empty


static func is_fallback(tex: Texture2D) -> bool:
	return tex == empty()


static func clear_cache() -> void:
	_cache.clear()
	_warned.clear()
