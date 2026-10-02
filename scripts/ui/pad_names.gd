class_name PadNames
extends RefCounted
## Noms affichés des boutons et axes de manette (OPTIONS > COMMANDES, invites
## du HUD « Appuyer sur X » / « Press Square »), texte seul, en majuscules
## comme les noms de touches.
##
## Godot range les boutons dans la disposition standard SDL (JoyButton) : la
## même position physique a le même numéro sur une manette Xbox et sur une
## PlayStation (A = Croix, X = Carré, LB = L1...). Seuls les noms changent,
## choisis d'après le nom de la manette (style_of).

const XBOX := "xbox"
const PLAYSTATION := "playstation"
## PlayStation 5 (DualSense) : comme PLAYSTATION, mais « CREATE » au lieu de
## « SHARE » et un bouton micro.
const PS5 := "ps5"

## Noms Xbox, puis PlayStation : [fr, en] (identiques sauf mention).
const XBOX_BUTTONS := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "BACK",
	JOY_BUTTON_GUIDE: "GUIDE",
	JOY_BUTTON_START: "START",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_MISC1: "SHARE",
	JOY_BUTTON_PADDLE1: "P1",
	JOY_BUTTON_PADDLE2: "P2",
	JOY_BUTTON_PADDLE3: "P3",
	JOY_BUTTON_PADDLE4: "P4",
}
const PS_BUTTONS := {
	JOY_BUTTON_A: ["CROIX", "CROSS"],
	JOY_BUTTON_B: ["ROND", "CIRCLE"],
	JOY_BUTTON_X: ["CARRÉ", "SQUARE"],
	JOY_BUTTON_Y: ["TRIANGLE", "TRIANGLE"],
	JOY_BUTTON_BACK: ["SHARE", "SHARE"],
	JOY_BUTTON_GUIDE: ["PS", "PS"],
	JOY_BUTTON_START: ["OPTIONS", "OPTIONS"],
	JOY_BUTTON_LEFT_STICK: ["L3", "L3"],
	JOY_BUTTON_RIGHT_STICK: ["R3", "R3"],
	JOY_BUTTON_LEFT_SHOULDER: ["L1", "L1"],
	JOY_BUTTON_RIGHT_SHOULDER: ["R1", "R1"],
	JOY_BUTTON_MISC1: ["MICRO", "MUTE"],
}
## Croix directionnelle (« flèche » en français : « croix » est un bouton
## PlayStation).
const DPAD := {
	JOY_BUTTON_DPAD_UP: ["FLÈCHE HAUT", "D-PAD UP"],
	JOY_BUTTON_DPAD_DOWN: ["FLÈCHE BAS", "D-PAD DOWN"],
	JOY_BUTTON_DPAD_LEFT: ["FLÈCHE GAUCHE", "D-PAD LEFT"],
	JOY_BUTTON_DPAD_RIGHT: ["FLÈCHE DROITE", "D-PAD RIGHT"],
}


## Style de noms d'après Input.get_joy_name() : DualShock, DualSense, « PS4 /
## PS5 Controller », Sony... -> PlayStation ; tout le reste (Xbox, manettes
## génériques XInput, Switch Pro en disposition standard) -> Xbox.
static func style_of(joy_name: String) -> String:
	var n := joy_name.to_lower()
	if n.contains("dualsense") or n.contains("ps5"):
		return PS5
	for w in ["playstation", "dualshock", "ps4", "ps3", "sony"]:
		if n.contains(w):
			return PLAYSTATION
	return XBOX


static func is_playstation(style: String) -> bool:
	return style == PLAYSTATION or style == PS5


## Nom d'un bouton (JoyButton) dans le style donné.
static func button_label(button: int, style := XBOX) -> String:
	if DPAD.has(button):
		return Lang.t(DPAD[button][0], DPAD[button][1])
	if button == JOY_BUTTON_TOUCHPAD:
		return Lang.t("PAVÉ TACTILE", "TOUCHPAD")
	if is_playstation(style):
		if button == JOY_BUTTON_BACK and style == PS5:
			return "CREATE"
		if PS_BUTTONS.has(button):
			return Lang.t(PS_BUTTONS[button][0], PS_BUTTONS[button][1])
	elif XBOX_BUTTONS.has(button):
		return XBOX_BUTTONS[button]
	return Lang.t("BOUTON %d", "BUTTON %d") % button


## Nom d'un axe (JoyAxis) incliné dans le sens `sign_` (-1 / 1).
static func axis_label(axis: int, sign_: int, style := XBOX) -> String:
	var ps := is_playstation(style)
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			return "L2" if ps else "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2" if ps else "RT"
		JOY_AXIS_LEFT_X:
			return Lang.t("STICK G. GAUCHE", "L STICK LEFT") if sign_ < 0 else Lang.t("STICK G. DROITE", "L STICK RIGHT")
		JOY_AXIS_LEFT_Y:
			return Lang.t("STICK G. HAUT", "L STICK UP") if sign_ < 0 else Lang.t("STICK G. BAS", "L STICK DOWN")
		JOY_AXIS_RIGHT_X:
			return Lang.t("STICK D. GAUCHE", "R STICK LEFT") if sign_ < 0 else Lang.t("STICK D. DROITE", "R STICK RIGHT")
		JOY_AXIS_RIGHT_Y:
			return Lang.t("STICK D. HAUT", "R STICK UP") if sign_ < 0 else Lang.t("STICK D. BAS", "R STICK DOWN")
	return Lang.t("AXE %d", "AXIS %d") % axis
