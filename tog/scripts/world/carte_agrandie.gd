extends CanvasLayer

# Vue agrandie de la carte de la zone : une seconde instance de la
# mini-carte (même texture, mêmes marqueurs vivants, mêmes filtres)
# affichée très grand par-dessus le jeu. La touche C, le bouton du
# panneau ou un clic sur le fond la ferment (Échap aussi) ; elle se
# referme toute seule si le jeu masque la mini-carte (menu, combat).

signal fermee

const THEME := preload("res://themes/theme_pirate.tres")
const MARGE_FOND := 0.06
const REMPLISSAGE_ECRAN := Vector2(0.88, 0.84)

var _mini: TextureRect
var _carte: TextureRect
var _fermeture_demandee := false

func ouvrir(carte_mini: TextureRect) -> void:
	name = "CarteAgrandie"
	layer = 50
	_mini = carte_mini
	var fond := ColorRect.new()
	fond.name = "Fond"
	fond.color = Color(0.0, 0.0, 0.0, 0.66)
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.gui_input.connect(_sur_fond)
	add_child(fond)
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.add_child(centre)
	var panneau := PanelContainer.new()
	panneau.name = "Panneau"
	panneau.theme = THEME
	panneau.theme_type_variation = "ParchmentPanel"
	centre.add_child(panneau)
	var marges := MarginContainer.new()
	marges.name = "Marges"
	for cote in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(cote, 18)
	panneau.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.name = "Colonne"
	colonne.add_theme_constant_override("separation", 6)
	marges.add_child(colonne)
	var titre := Label.new()
	titre.name = "Titre"
	titre.text = "CARTE DE LA ZONE"
	titre.theme_type_variation = "Ribbon"
	titre.add_theme_font_size_override("font_size", 24)
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonne.add_child(titre)
	_carte = _mini.get_script().new() as TextureRect
	_carte.name = "CarteGrande"
	_carte.texture = _mini.texture
	_carte.material = _mini.material
	_carte.texture_filter = _mini.texture_filter
	_carte.dimensions_monde = _mini.dimensions_monde
	_carte.reperes = _mini.reperes
	_carte.expand_mode = _mini.expand_mode
	_carte.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_carte.custom_minimum_size = _taille_agrandie()
	_carte.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	colonne.add_child(_carte)
	# l'instance ajoute elle-même sa légende de filtres dans son parent
	# (la colonne) : filtres partagés avec la mini-carte, marqueurs
	# vivants et info-bulles inclus

func _taille_agrandie() -> Vector2:
	var ecran := get_viewport().get_visible_rect().size
	var disponible := ecran * REMPLISSAGE_ECRAN
	# la grande carte garde les proportions du monde : la dimension qui
	# limite fixe l'autre
	var ratio := float(_mini.dimensions_monde.x) / maxi(float(_mini.dimensions_monde.y), 1.0)
	if ratio <= 0.0:
		ratio = 1.0
	var hauteur := minf(disponible.y, disponible.x / ratio)
	return Vector2(hauteur * ratio, hauteur)

# clic sur le fond : fermer (les clics sur la carte, la légende et les
# info-bulles restent à la carte)
func _sur_fond(evenement: InputEvent) -> void:
	if evenement is InputEventMouseButton and evenement.pressed \
			and evenement.button_index == MOUSE_BUTTON_LEFT:
		fermer()

# Échap ou C : fermer
func _unhandled_input(evenement: InputEvent) -> void:
	if evenement is InputEventKey and evenement.pressed and not evenement.echo \
			and (evenement.keycode == KEY_ESCAPE or evenement.keycode == KEY_C):
		fermer()
		get_viewport().set_input_as_handled()

# la grande carte suit la mini-carte : menu ouvert, combat lancé, écran
# de création — tout ce qui masque la mini referme la vue agrandie
func _process(_delta: float) -> void:
	if _fermeture_demandee:
		return
	if _mini == null or not is_instance_valid(_mini) or not _mini.is_visible_in_tree():
		fermer()

func fermer() -> void:
	if _fermeture_demandee:
		return
	_fermeture_demandee = true
	fermee.emit()
	queue_free()
