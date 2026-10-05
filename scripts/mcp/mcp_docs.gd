class_name McpDocs
extends RefCounted
## Documentation livrée à l'IA par le serveur MCP du jeu (McpServer,
## docs/MCP.md) : l'IA n'a pas le dépôt, seulement le jeu. Les cinq documents
## utiles sont embarqués dans le pck (export_presets.cfg, include_filter) et
## lus depuis res://docs/ ; ils sont rendus par l'outil editor_guide (en
## entier ou par section), comme ressources (zombie://docs/<fichier>) et dans
## le prompt « concevoir_carte ». Les règles de conception sont en plus
## jointes au premier appel d'outil de chaque session (McpServer).

const DIR := "res://docs/"
## Sujet d'editor_guide -> fichier de res://docs/.
const FILES := {
	"regles": "MAP_DESIGN_RULES.md",
	"format": "MAP_AUTHORING.md",
	"objets": "MAP_OBJECTS.md",
	"vues": "EDITOR_VIEWS.md",
	"echelle": "EDITOR_SCALE_ROTATE.md",
}
## Sujets dans l'ordre présenté à l'IA (« consignes » : texte ci-dessous).
const TOPICS := ["regles", "consignes", "format", "objets", "vues", "echelle"]
const TOPIC_TITLES := {
	"regles": "Règles de conception des cartes (OBLIGATOIRES, avec la grille de contrôle)",
	"consignes": "Consignes détaillées pour piloter l'éditeur (niveaux et altitudes, hauteurs, échelle, escaliers, découpe)",
	"format": "L'éditeur de cartes et le format des éléments",
	"objets": "Objets : variantes, barrière invisible, escaliers, décor libre, portes à zombies, effets",
	"vues": "Vues multiples : élévations, hauteurs (format 12)",
	"echelle": "Échelle et rotation 3D du décor (format 14)",
}
## Au-delà de cette taille (caractères), un sujet demandé sans « section »
## rend la liste de ses sections plutôt que le texte entier.
const FULL_MAX := 32000
const URI_PREFIX := "zombie://docs/"
const PROMPT := "concevoir_carte"

## Consignes données à l'initialisation : COURTES (Claude Code coupe au-delà
## de 2 048 caractères) ; le détail est dans le sujet « consignes ».
const INSTRUCTIONS := """Pilote en direct l'éditeur de cartes du jeu Claude of Duty Zombie (clone de BO1 Zombies) ouvert sur cet ordinateur.
- Les règles de conception sont OBLIGATOIRES : leur texte complet est joint au résultat de ton premier appel d'outil (ensuite : editor_guide, sujet « regles »). Suis-les et remplis leur grille de contrôle avant de dire qu'une carte est finie.
- Ordre : editor_status, puis editor_get_map (résumé) et editor_get_selection (la sélection est souvent l'objet de la demande) ; editor_get_element avant de modifier un élément.
- Avant d'écrire des éléments, lis editor_guide « consignes » (niveaux, hauteurs, échelle et inclinaison, escaliers, pièces qui se recouvrent) ; « format », « objets », « vues » et « echelle » détaillent le format ; editor_catalog donne les types admis.
- editor_apply : un appel = une étape d'annulation (Ctrl+Z) avec un « label » clair en français ; « add » pour créer (ids provisoires "$1"…), « put » de l'élément complet relu pour modifier.
- Ressources propres à la carte : prefabs et modèles 3D .glb/.gltf (editor_prefab_*), textures PNG/JPEG des sols, murs et plafonds (editor_texture_*), sans limite de nombre ni de taille.
- Après chaque modification : editor_validate puis editor_screenshot ; editor_highlight pour montrer à l'utilisateur ; editor_undo_last annule ta dernière action.
- L'utilisateur et d'autres participants éditent en même temps : relis avant de modifier, ne refais pas ce qu'il vient de défaire.
- Mètres, x vers l'est, y vers le sud (négatifs admis, sans limite), z vers le haut. Chaque pièce a une « altitude » libre (sol, m ; pièces empilées : 3,1 m d'écart au moins) et son contenu la même ; « etage » (ancien format) est refusé. Niveaux, pièces hautes, sans_plafond, escaliers : « consignes »."""

## Sujet « consignes » : le détail des anciennes consignes du pont MCP.
const CONSIGNES := """# Consignes détaillées pour piloter l'éditeur de cartes

- Commence toujours par editor_status puis editor_get_map (résumé) et editor_get_selection : ce que l'utilisateur a sélectionné est souvent l'objet de sa demande. editor_get_element donne les éléments complets avant de les modifier.
- Unités en mètres, x vers l'est, y vers le sud, z vers le haut. Coordonnées x, y libres, NÉGATIVES comprises, sans étendue maximale (seuls les nombres finis comptent). Format des éléments : editor_guide, sujet « format », section « Format des fichiers » (et editor_catalog pour les types et leurs clés).
- Niveaux (format 17) : chaque pièce a une « altitude » LIBRE (m, altitude absolue de son sol : 0, 1,5, 3,5, -4…, sans pas imposé ni borne) ; un niveau = les pièces de même altitude (à 5 mm près) ; editor_status et editor_get_map donnent les niveaux. Tout ce qui est dans une pièce (ouvertures, objets) porte l'altitude de SA pièce ; un élément à une altitude sans pièce est signalé (« orphelins » du résumé). Déplacer une pièce en hauteur : « put » de la pièce ET de son contenu avec la nouvelle altitude, dans le même lot. Format d'avant refusé : « etage » (indice d'étage), « etages » (dans carte) et « double_hauteur » n'existent plus ; écris « altitude ».
- Superposition : deux pièces qui se recouvrent en plan sont à 3,1 m au moins l'une de l'autre (2,8 m sous plafond + dalle de 0,3 m) ; côte à côte, n'importe quel écart (demi-niveau : 1,5 m par exemple, relié par une rampe ou un escalier). « plafond » = hauteur sous plafond au-dessus du sol de la pièce (2,8 m au moins, 3,2 par défaut, pas de maximum) ; sous une pièce posée au-dessus, le plafond réel est le plus bas des deux (dessous de sa dalle : résumé « plafond_reel_min »). Pièce HAUTE : grand « plafond » qui traverse les niveaux du dessus (atrium, halle) ; une pièce d'un niveau traversé posée au-dessus de son vide est une MEZZANINE (bord au-dessus du vide : garde-corps). Porte, débris, passage : entre deux pièces de même altitude ; une porte entre deux altitudes est une erreur : relie-les par un escalier.
- Plafond masqué et ciel : « sans_plafond »: true sur une pièce (jamais écrit à faux) : ni plafond ni collision au-dessus, ses murs montent jusqu'à son « plafond » ; on y voit le ciel de la carte, « carte.ciel » = {"type": "noir" | "jour" | "nuit", "luminosite": 0,1 à 2} (défaut noir et 1, jamais écrit à sa valeur par défaut ; op « carte » avec le dictionnaire carte complet relu). Rien n'empêche un joueur de sortir par le haut : ferme la carte (murs assez hauts, pas de décor grimpable). Ce qui est accroché au plafond d'une pièce sans plafond flotte (avertissement).
- editor_apply : un lot d'opérations (put / del / carte / depart / add). Pour créer, utilise « add » sans id ou avec un id provisoire "$1", "$2"… réutilisable dans le même lot (ex. zone d'une pièce) ; pour modifier, « put » de l'élément complet relu avant. Un appel editor_apply = UNE étape d'annulation (un Ctrl+Z) pour l'utilisateur : regroupe ce qui va ensemble, sépare ce qui est indépendant. Donne toujours un « label » clair en français (« Couloir entre l'entrée et l'atelier »).
- Après chaque modification : editor_validate (erreurs bloquantes à corriger) et editor_screenshot pour voir le résultat ; editor_highlight pour montrer à l'utilisateur ce dont tu parles. editor_undo_last annule ta dernière action.
- Respecte les règles de conception (editor_guide, sujet « regles » : surface vide < 15 m², couloirs 2-3 m et 12 m max en ligne droite, boucles, fenêtres, prix des portes, décor) et l'esprit de BO1 Zombies. Remplis leur grille de contrôle (section 13) avant de dire qu'une carte est finie.
- L'utilisateur (et d'autres participants) éditent en même temps : relis la carte avant de modifier un élément, ne refais pas ce qu'il vient de défaire.
- Hauteurs (format 12, editor_guide « vues », section 7) : z vers le haut, en m. Un décor posé au sol a une hauteur de pose « z » (sur un autre décor : un décor qui bloque doit reposer sur le dessus d'un autre) ; un luminaire au sol une « hauteur » (sinon le dessus du meuble dessous) ; ce qui est accroché au plafond (luminaire, effet, décor) une « descente » sous le plafond ; appliques, décors et effets muraux une « hauteur » sur le mur. Ces clés ne s'écrivent jamais à leur valeur par défaut. editor_get_element rend z_min / z_max / z_monde de chaque élément ; editor_screenshot montre aussi les élévations (view : avant, arriere, gauche, droite, dessous ; coupe [p0, p1] pour isoler une tranche).
- Échelle et rotation 3D du décor (format 14, editor_guide « echelle ») : sur un objet « prefab » seulement, « echelle » [sx, sy, sz] (facteurs de 0,25 à 4 dans le repère de l'objet : largeur, profondeur, hauteur ; dimensions finales de 0,05 à 30 m, emprise de 20 m au plus) et « incl » [x, y] (degrés, -180 à 180, au dixième ; décor posé au sol seulement), jamais écrites à leur valeur par défaut ([1, 1, 1], [0, 0]). Orientation = Rz(rot) · Ry(incl y) · Rx(incl x), X est, Y sud, Z haut ; sens positif horaire vu de l'axe de bout (Dessus pour rot, Avant pour Y : le bout est descend, Droite pour X : le bout nord descend). Un décor incliné reste posé : « z » est la hauteur de son point le plus bas ; il ne porte rien. Ne changent JAMAIS d'échelle : objets de jeu (atouts, armes murales, boîte, Pack-a-Punch…), ouvertures, construction, luminaires, effets ; un prefab de la carte qui contient un objet de jeu non plus (le refus le nomme). editor_get_element rend dimensions, echelle_possible, inclinaison_possible et raison ; editor_catalog marque « echelle »: false.
- Escaliers (editor_guide « objets », section 4) : un objet « escalier » a « altitude » = sol de son PIED et « altitude_haut » = sol d'ARRIVÉE (absolu, obligatoire) ; il peut relier deux niveaux quelconques et SAUTER des niveaux (de 0 à 7 m par-dessus 3,5 m : rien au-dessus des marches aux niveaux traversés, sinon erreur) ; pente de 40° au plus, 2,1 m de passage au-dessus des marches et de l'arrivée. « monte » (n, e, s, o) = sens de la montée. Pied (départ) : sol libre d'une pièce à « altitude » devant la première marche ; arrivée : plancher libre d'une pièce à « altitude_haut » au-delà du haut ; trémie automatique. Deux pièces côte à côte d'altitudes différentes (demi-niveau) : l'arrivée peut traverser leur mur commun (palier dans l'épaisseur du mur). Facultatif « sortie » : "gauche" ou "droite" (vu en montant) : palier plat en haut (volée plus courte, donc plus raide : allonger l'escalier si refus) et on sort sur ce côté ; absente = en face. L'éditeur la choisit tout seul à la pose quand le haut des marches touche un mur ; tu peux aussi l'écrire. Seulement pour les variantes droit, large, service, rampe et palier (jamais L, U, colimaçon). Un escalier qui DESCEND s'écrit comme un escalier posé au niveau du dessous qui y monte (pas de champ « descend » : l'objet « escalier_bas » du catalogue est l'outil de l'utilisateur). Cage d'escalier sur plusieurs niveaux : volées côte à côte, jamais au même endroit. Réglages facultatifs : « variante », « sens », « garde_corps », « cotes » ; le nombre de marches n'est PLUS réglable (toujours automatique, ≈ 18 cm par marche, comme en jeu) : jamais de « marches » (refusé). Un refus (invalid) dit quoi et où (départ, arrivée, trémie, coordonnées).
- Boîte mystère (format 15, editor_guide « objets », section 15) : AU SOL, « position » = son centre et « rot » (degrés entiers, sens horaire vu de dessus ; 0 : l'avant, où s'ouvre le couvercle, est au sud), SANS « mur » ni « angle » ; emprise 2 × 1 m tournée, dans une pièce, à 0,1 m au moins de la face des murs, sans chevauchement. CONTRE UN MUR (comme avant), « position » sur le trait du mur + « mur » (et « angle » en biais), SANS « rot ». En jeu, une boîte au sol s'achète de tous les côtés, jamais à travers un mur ; taille fixe (jamais d'« echelle »). Au moins 3 emplacements, un seul « depart »: true.
- Pièces qui se recouvrent : deux pièces se touchent, jamais ne se recouvrent. Un lot editor_apply dont une pièce (add ou put) recouvre une pièce de même altitude est REFUSÉ en entier, sauf avec « decouper »: true : les pièces recouvertes perdent la partie sous la nouvelle (coupées en morceaux reliés par un passage libre si besoin, supprimées s'il n'en reste presque rien ; contenu de la partie découpée rattaché à la nouvelle pièce ; ouvertures dont le mur disparaît déplacées ou retirées), dans le MÊME lot (une seule annulation). Le résultat « decoupe » détaille tout : vérifie-le et préviens l'utilisateur. Un escalier rendu invalide fait refuser la découpe.
- Prefabs de la carte (editor_guide « objets », section 11) : editor_prefab_list / editor_prefab_sources pour voir, editor_prefab_create (groupe de décors posés « ids » ou « parties » du catalogue), editor_prefab_import_model (fichier .glb/.gltf de cet ordinateur par « chemin », ou « data_base64 »), editor_prefab_import (depuis une autre carte), editor_prefab_update / editor_prefab_delete. On pose une prefab avec editor_apply : objet {"type": "prefab", "prefab": "map:<pid>", "position": [x, y], "rot": 0}. La bibliothèque ne change qu'en solo ou chez l'hôte et n'est PAS annulable par Ctrl+Z : préviens l'utilisateur.
- Textures de la carte (format 16, editor_guide « format », section « Textures de la carte ») : editor_texture_list (textures du jeu et de la carte), editor_texture_import (PNG/JPEG par « chemin » ou « data_base64 », « taille » du motif en m), editor_texture_update / editor_texture_delete / editor_texture_import_from_map. Pour l'appliquer : editor_apply, « put » de la pièce complète avec "surface_sol" / "surface_murs" / "surface_plafond": "map:<id>" (ou de la zone avec "sol" / "murs" / "plafond"). Pas de quota : c'est au concepteur de gérer les ressources de sa carte, mais garde des images raisonnables (1024 à 2048 px suffisent).
- Les sujets « format », « objets » et « vues » sont longs : appelle editor_guide sans « section » pour en avoir la liste, puis avec la section voulue (numéro comme « 4 » ou « 6.4 », ou mots du titre)."""

const RULES_INTRO := "RÈGLES DE CONCEPTION OBLIGATOIRES (jointes une seule fois, au premier appel d'outil de la session). Suis-les pour toute création ou modification de carte et remplis leur grille de contrôle (section 13) avant de dire qu'une carte est finie ; relis-les à tout moment avec editor_guide, sujet « regles ». Le résultat de l'outil appelé suit ce texte.\n\n"

static var _cache := {}


## Texte d'un sujet ("" si le document manque dans cette version du jeu).
static func text_of(topic: String) -> String:
	if topic == "consignes":
		return CONSIGNES
	if not FILES.has(topic):
		return ""
	if not _cache.has(topic):
		var path: String = DIR + String(FILES[topic])
		_cache[topic] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	return String(_cache[topic])


## Texte joint au premier appel d'outil d'une session.
static func rules_intro() -> String:
	var t := text_of("regles")
	if t == "":
		return "Règles de conception introuvables dans cette version du jeu (res://docs/MAP_DESIGN_RULES.md)."
	return RULES_INTRO + t


## Sections d'un texte Markdown (titres « ## » et « ### », hors blocs de
## code) : [{level, title, from, to}] (lignes, `to` exclue).
static func sections(text: String) -> Array:
	var lines := text.split("\n")
	var out := []
	var fence := false
	for i in lines.size():
		var l := lines[i]
		if l.begins_with("```"):
			fence = not fence
			continue
		if fence:
			continue
		var lv := 0
		if l.begins_with("### "):
			lv = 3
		elif l.begins_with("## "):
			lv = 2
		if lv > 0:
			out.append({"level": lv, "title": l.substr(lv + 1).strip_edges(), "from": i, "to": lines.size()})
	for k in out.size():
		for j in range(k + 1, out.size()):
			if int(out[j].level) <= int(out[k].level):
				out[k].to = out[j].from
				break
	return out


## Minuscules sans accents, pour comparer des titres.
static func plain(s: String) -> String:
	var t := s.to_lower()
	var from := "àâäáãéèêëíìîïóòôöõúùûüçñœ"
	var to := ["a", "a", "a", "a", "a", "e", "e", "e", "e", "i", "i", "i", "i", "o", "o", "o", "o", "o", "u", "u", "u", "u", "c", "n", "oe"]
	for i in from.length():
		t = t.replace(from[i], to[i])
	return t.strip_edges()


## Section demandée : numéro (« 4 », « 6.4 », « 2 bis ») ou mots du titre
## (casse et accents ignorés). {} si aucune.
static func find_section(text: String, wanted: String) -> Dictionary:
	var w := plain(wanted).trim_prefix("§").strip_edges().trim_suffix(".")
	if w == "":
		return {}
	var secs := sections(text)
	# Numéro exact d'abord (« 6.4 » ne doit pas rendre « 6.4 bis »).
	for s in secs:
		if _num_of(plain(String(s.title))) == w:
			return s
	for s in secs:
		if plain(String(s.title)).contains(w):
			return s
	return {}


## Numéro d'un titre (« 6.4 », « 2 bis », « 13 ») ; "" sans numéro.
static func _num_of(title: String) -> String:
	var toks := title.split(" ", false)
	if toks.is_empty():
		return ""
	var n := toks[0].trim_suffix(".")
	if not n.replace(".", "").is_valid_int():
		return ""
	if toks.size() > 1 and toks[1] in ["bis", "ter", "quater"]:
		n += " " + toks[1]
	return n


## Liste lisible des sections d'un sujet (pour choisir « section »).
static func section_list(topic: String) -> String:
	var t := text_of(topic)
	var lines := t.split("\n")
	var out := ["Sujet « %s » : %s (%d caractères). Sections (rappelle editor_guide avec « section » : numéro comme \"4\" ou \"6.4\", ou mots du titre) :" % [topic, TOPIC_TITLES.get(topic, ""), t.length()]]
	for s in sections(t):
		var n := 0
		for i in range(int(s.from), int(s.to)):
			n += lines[i].length() + 1
		out.append("%s%s (%d car.)" % ["  " if int(s.level) == 3 else "- ", s.title, n])
	return "\n".join(out)


## Outil editor_guide : {"text"} ou {"error"}.
static func guide(topic: Variant, section: Variant) -> Dictionary:
	if topic == null:
		var lst := ["Sujets d'editor_guide (argument « topic ») :"]
		for k in TOPICS:
			lst.append("- %s : %s" % [k, TOPIC_TITLES[k]])
		return {"text": "\n".join(lst)}
	if not topic is String or not String(topic) in TOPICS:
		return {"error": "topic : l'un de %s" % ", ".join(TOPICS)}
	if section != null and not section is String:
		return {"error": "section : texte (numéro comme \"4\" ou \"6.4\", ou mots du titre)"}
	var t := text_of(topic)
	if t == "":
		return {"error": "Document « %s » absent de cette version du jeu." % topic}
	if section != null and String(section).strip_edges() != "":
		var s := find_section(t, String(section))
		if s.is_empty():
			return {"error": "Section « %s » introuvable.\n\n%s" % [String(section).left(80), section_list(topic)]}
		var lines := t.split("\n")
		return {"text": "\n".join(lines.slice(int(s.from), int(s.to))).strip_edges()}
	if t.length() > FULL_MAX:
		return {"text": section_list(topic)}
	return {"text": t}


# ------------------------------------------------------------------ ressources et prompt

static func resources() -> Array:
	var out := []
	for k in TOPICS:
		var t := text_of(k)
		if t == "":
			continue
		out.append({"uri": uri_of(k), "name": file_of(k), "title": TOPIC_TITLES[k], "description": TOPIC_TITLES[k], "mimeType": "text/markdown", "size": t.to_utf8_buffer().size()})
	return out


static func file_of(topic: String) -> String:
	return String(FILES.get(topic, "CONSIGNES_MCP.md"))


static func uri_of(topic: String) -> String:
	return URI_PREFIX + file_of(topic)


## Contenu d'une ressource ({} si l'adresse est inconnue).
static func read_resource(uri: String) -> Dictionary:
	for k in TOPICS:
		if uri == uri_of(k):
			var t := text_of(k)
			if t == "":
				return {}
			return {"uri": uri, "mimeType": "text/markdown", "text": t}
	return {}


static func prompts() -> Array:
	return [{"name": PROMPT, "title": "Concevoir une carte", "description": "Concevoir ou retoucher une carte dans l'éditeur ouvert en suivant les règles de conception (jointes) et les consignes de l'éditeur.",
		"arguments": [{"name": "demande", "description": "Ce que la carte doit être ou ce qu'il faut changer (facultatif).", "required": false}]}]


## Prompt « concevoir_carte » : la demande, puis les règles et les consignes
## jointes en entier ; les autres sujets sont cités (editor_guide).
static func get_prompt(name: Variant, args: Variant) -> Dictionary:
	if not name is String or name != PROMPT:
		return {"error": "prompt inconnu : %s (seul : %s)" % [str(name).left(40), PROMPT]}
	var demande := ""
	if args is Dictionary and (args as Dictionary).get("demande") is String:
		demande = String(args.demande).strip_edges().left(4000)
	var intro := "Conçois une carte (ou retouche la carte ouverte) dans l'éditeur de cartes de Claude of Duty Zombie avec les outils editor_*. Les règles de conception jointes sont OBLIGATOIRES : suis-les et remplis leur grille de contrôle (section 13) dans ton compte rendu. Suis aussi les consignes jointes ; pour le format des éléments, appelle editor_guide (sujets « format », « objets », « vues », « echelle ») et editor_catalog."
	if demande != "":
		intro += "\n\nDemande : " + demande
	var msgs := [{"role": "user", "content": {"type": "text", "text": intro}}]
	for k in ["regles", "consignes"]:
		var t := text_of(k)
		if t != "":
			msgs.append({"role": "user", "content": {"type": "resource", "resource": {"uri": uri_of(k), "mimeType": "text/markdown", "text": t}}})
	return {"description": "Concevoir une carte en suivant les règles de conception", "messages": msgs}
