class_name Hub2Input
extends RefCounted
## Commandes standard du hub v2 (HUB_PLAN §4.1, §9) : identifiant d'invite
## -> touches du clavier et boutons de la manette, noms affichés selon le
## périphérique utilisé en dernier (Settings.using_pad ; Xbox ou PlayStation
## par PadNames), et reconnaissance des événements.
##
## Les écrans donnent leurs invites en [identifiant, texte] ; un identifiant
## qui n'est pas ci-dessous est une action propre à l'écran : il donne ses
## touches dans l'invite, [id, texte, touches_clavier, boutons_manette]
## (Hub2Prompts.set_items), et la reçoit cliquée par Hub2Panel.on_prompt.

const ACCEPT := "accept"
const BACK := "back"
const TABS := "tabs"
## Écran JOUER (START ; P au clavier).
const PLAY := "play"
## Action secondaire (retirer, recycler, armes de départ) : Suppr ou R / X.
const SECONDARY := "secondary"
## Filtre / tri / changer de carte : Tab / Y.
const FILTER := "filter"


## Touches du clavier de l'invite `id` (noms affichés).
static func keys_of(id: String) -> PackedStringArray:
	match id:
		ACCEPT: return PackedStringArray([Lang.t("Entrée", "Enter")])
		BACK: return PackedStringArray([Lang.t("Échap", "Esc")])
		TABS: return PackedStringArray([physical_key_name(KEY_Q), physical_key_name(KEY_E)])
		PLAY: return PackedStringArray([physical_key_name(KEY_P)])
		SECONDARY: return PackedStringArray([Lang.t("Suppr", "Del")])
		FILTER: return PackedStringArray(["Tab"])
	return PackedStringArray()


## Boutons de la manette de l'invite `id`.
static func pads_of(id: String) -> Array:
	match id:
		ACCEPT: return [JOY_BUTTON_A]
		BACK: return [JOY_BUTTON_B]
		TABS: return [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
		PLAY: return [JOY_BUTTON_START]
		SECONDARY: return [JOY_BUTTON_X]
		FILTER: return [JOY_BUTTON_Y]
	return []


## Nom d'une touche physique dans la disposition du clavier (Q s'affiche A en
## AZERTY).
static func physical_key_name(physical: int) -> String:
	return Settings.code_label(Settings.key_code(physical))


## Texte de la touche (keycap) pour `keys` (clavier) / `pads` (manette) selon
## le périphérique courant : « LB RB », « Entrée », « START », « L1 R1 ».
static func keycap_text(keys: PackedStringArray, pads: Array, pad := false) -> String:
	var names := PackedStringArray()
	if pad and not pads.is_empty():
		for b in pads:
			names.append(PadNames.button_label(b, Settings.pad_style()))
	else:
		names = keys
	return " ".join(names)


## Bouton de face PlayStation seul à dessiner en symbole (-1 : texte).
static func ps_symbol(pads: Array, pad := false) -> int:
	if pad and pads.size() == 1 and int(pads[0]) in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y] \
			and PadNames.is_playstation(Settings.pad_style()):
		return int(pads[0])
	return -1


## Indication autour des onglets (LB / RB de la barre du haut) : -1 gauche,
## 1 droite.
static func tab_hint(dir: int) -> String:
	if Settings.using_pad:
		return PadNames.button_label(JOY_BUTTON_LEFT_SHOULDER if dir < 0 else JOY_BUTTON_RIGHT_SHOULDER, Settings.pad_style())
	return physical_key_name(KEY_Q if dir < 0 else KEY_E)


# --- Reconnaissance des événements --------------------------------------------

## Touche physique `physical` appuyée (sans Ctrl / Alt, pas de répétition).
static func is_key(event: InputEvent, physical: int) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.physical_keycode == physical \
		and not k.ctrl_pressed and not k.alt_pressed


## Onglet précédent (-1), suivant (1), sinon 0 : LB / RB, Page préc. / suiv.,
## Q / E.
static func tab_step(event: InputEvent) -> int:
	if event.is_action_pressed("ui_page_up") or is_key(event, KEY_Q):
		return -1
	if event.is_action_pressed("ui_page_down") or is_key(event, KEY_E):
		return 1
	return 0


## Écran JOUER : START (manette) ou P.
static func is_play(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
		return true
	return is_key(event, KEY_P)
