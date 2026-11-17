# hud.gd — HUD du jeu :
#  - en bas à gauche : panneau parchemin avec les barres de vie et d'XP ;
#  - en haut à droite : compteur de Berry avec icône de pièce.
# Suit automatiquement les stats via Personnage.caracteristiques_modifiees.
extends CanvasLayer

const ICONE_COEUR := "res://addons/pixel_ui_fantasy/icons/heart.png"
const ICONE_XP := "res://addons/pixel_ui_fantasy/icons/xp.png"
const ICONE_PIECE := "res://addons/pixel_ui_fantasy/icons/coin.png"

const MARGE := 24.0
const MARGE_PANNEAU := 12.0
const LARGEUR_BARRE := 380.0
const HAUTEUR_BARRE := 26.0
const TAILLE_ICONE := 24.0

var barre_vie: ProgressBar
var barre_xp: ProgressBar
var label_vie: Label
var label_xp: Label
var label_berry: Label

func _ready() -> void:
	_construire()
	Personnage.caracteristiques_modifiees.connect(maj)
	maj()

func _construire() -> void:
	_construire_panneau_stats()
	_construire_compteur_berry()

# ancre un panneau sur un coin de l'écran ; grâce aux directions de
# croissance, le panneau s'étend toujours vers l'intérieur de l'écran
func _ancrer_coin(element: Control, gauche: bool, haut: bool) -> void:
	var x := 0.0 if gauche else 1.0
	var y := 0.0 if haut else 1.0
	element.anchor_left = x
	element.anchor_right = x
	element.anchor_top = y
	element.anchor_bottom = y
	element.offset_left = MARGE if gauche else -MARGE
	element.offset_right = MARGE if gauche else -MARGE
	element.offset_top = MARGE if haut else -MARGE
	element.offset_bottom = MARGE if haut else -MARGE
	element.grow_horizontal = Control.GROW_DIRECTION_END if gauche else Control.GROW_DIRECTION_BEGIN
	element.grow_vertical = Control.GROW_DIRECTION_END if haut else Control.GROW_DIRECTION_BEGIN

# construit un panneau parchemin ancré sur un coin de l'écran
func _panneau_coin(gauche: bool, haut: bool) -> PanelContainer:
	var panneau := PanelContainer.new()
	panneau.theme_type_variation = "ParchmentPanel"
	_ancrer_coin(panneau, gauche, haut)
	add_child(panneau)
	return panneau

func _construire_panneau_stats() -> void:
	var panneau := _panneau_coin(true, false)
	var marges := MarginContainer.new()
	marges.add_theme_constant_override("margin_left", MARGE_PANNEAU)
	marges.add_theme_constant_override("margin_right", MARGE_PANNEAU)
	marges.add_theme_constant_override("margin_top", MARGE_PANNEAU)
	marges.add_theme_constant_override("margin_bottom", MARGE_PANNEAU)
	panneau.add_child(marges)

	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)

	var ligne_vie := _groupe_barre(ICONE_COEUR, "RedBar")
	barre_vie = ligne_vie.get_child(1)
	label_vie = ligne_vie.get_child(2)
	colonne.add_child(ligne_vie)

	var ligne_xp := _groupe_barre(ICONE_XP, "GoldBar")
	barre_xp = ligne_xp.get_child(1)
	label_xp = ligne_xp.get_child(2)
	colonne.add_child(ligne_xp)

func _construire_compteur_berry() -> void:
	var panneau := _panneau_coin(false, true)
	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 8)
	panneau.add_child(ligne)

	var piece := TextureRect.new()
	piece.texture = load(ICONE_PIECE)
	piece.custom_minimum_size = Vector2(TAILLE_ICONE, TAILLE_ICONE)
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	piece.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ligne.add_child(piece)

	label_berry = Label.new()
	label_berry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ligne.add_child(label_berry)

# construit un groupe icône + barre + libellé (la barre est l'enfant 1,
# le libellé l'enfant 2)
func _groupe_barre(chemin_icone: String, variation: String) -> HBoxContainer:
	var groupe := HBoxContainer.new()
	groupe.add_theme_constant_override("separation", 10)
	var icone := TextureRect.new()
	icone.texture = load(chemin_icone)
	icone.custom_minimum_size = Vector2(TAILLE_ICONE, TAILLE_ICONE)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var barre := ProgressBar.new()
	barre.theme_type_variation = variation
	barre.show_percentage = false
	barre.custom_minimum_size = Vector2(LARGEUR_BARRE, HAUTEUR_BARRE)
	barre.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	groupe.add_child(icone)
	groupe.add_child(barre)
	groupe.add_child(label)
	return groupe

# rafraîchit tout le HUD (Vie, XP et Berry)
func maj() -> void:
	barre_vie.max_value = maxi(Personnage.vie_max, 1)
	barre_vie.value = Personnage.vie
	label_vie.text = "%d / %d" % [Personnage.vie, Personnage.vie_max]
	barre_xp.max_value = maxi(Personnage.xp_prochain_niveau(), 1)
	barre_xp.value = Personnage.xp
	label_xp.text = "Niv %d — %d / %d" % [Personnage.niveau, Personnage.xp, Personnage.xp_prochain_niveau()]
	label_berry.text = "%d" % Personnage.berry
