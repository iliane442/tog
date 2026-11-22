extends TextureRect

# Les marqueurs les plus utiles au déplacement sont dessinés en dernier.
const CATEGORIES := {
	"ennemis": {"libelle": "Ennemis", "symbole": "◆", "couleur": Color("#ed8b7e"), "rayon": 3.5},
	"ressources": {"libelle": "Ressources", "symbole": "▲", "couleur": Color("#b6d977"), "rayon": 3.5},
	"pnj": {"libelle": "PNJ", "symbole": "•", "couleur": Color("#d5cdbc"), "rayon": 3.5},
	"joueurs": {"libelle": "Joueurs", "symbole": "●", "couleur": Color("#b0c7fc"), "rayon": 4.0},
	"groupe": {"libelle": "Groupe", "symbole": "G", "couleur": Color("#8de8e5"), "rayon": 6.0},
	"butin": {"libelle": "Butin", "symbole": "×", "couleur": Color("#d6a9fa"), "rayon": 5.5},
	"voyages": {"libelle": "Passages", "symbole": "›", "couleur": Color("#8ddce3"), "rayon": 5.5},
	"marchands": {"libelle": "Marchands", "symbole": "B", "couleur": Color("#76deb2"), "rayon": 6.0},
	"quetes": {"libelle": "Quêtes", "symbole": "!", "couleur": Color("#ffda74"), "rayon": 6.0},
}
const ORDRE_LEGENDE := ["quetes", "marchands", "pnj", "ennemis", "voyages", "ressources", "butin", "joueurs"]
const CONTOUR := Color("#231b18")
const INTERVALLE_ACTUALISATION := 0.12
const SCRIPT_CARTE_AGRANDIE := preload("res://scripts/world/carte_agrandie.gd")

@export var dimensions_monde := Vector2.ONE
@export var reperes: Dictionary[Vector2, String] = {}

@onready var joueur: Node2D = get_tree().get_first_node_in_group("player")

static var _categories_masquees: Dictionary = {}
static var _agrandie: CanvasLayer = null
var _calque: Control
var _font: Font
var _marqueurs: Array[Dictionary] = []
var _temps := 0.0

func _ready() -> void:
	_font = get_theme_default_font()
	# Fushia applique son shader de relief uniquement au fond de carte.
	_calque = Control.new()
	_calque.name = "Marqueurs"
	_calque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_calque)
	_calque.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_calque.draw.connect(_dessiner_marqueurs)
	_creer_legende()
	_creer_bouton_agrandir.call_deferred()
	_actualiser_marqueurs.call_deferred()

# bouton d'accès à la vue agrandie, juste sous la carte du panneau
func _creer_bouton_agrandir() -> void:
	var bouton := Button.new()
	bouton.name = "BoutonAgrandir"
	bouton.text = "⤢ Agrandir (touche C)"
	bouton.tooltip_text = "Afficher la carte de la zone en grand."
	bouton.add_theme_font_size_override("font_size", 14)
	bouton.pressed.connect(basculer_agrandie)
	var parent := get_parent()
	parent.add_child(bouton)
	parent.move_child(bouton, get_index() + 1)

# la touche C ouvre ou referme la vue agrandie de la carte
func _unhandled_input(evenement: InputEvent) -> void:
	if evenement is InputEventKey and evenement.pressed and not evenement.echo \
			and evenement.keycode == KEY_C:
		basculer_agrandie()
		get_viewport().set_input_as_handled()

# ouvre la vue agrandie si elle n'existe pas, la referme sinon ; une
# seule vue à la fois, quel que soit le panneau qui la demande
func basculer_agrandie() -> void:
	if _agrandie != null and is_instance_valid(_agrandie):
		_agrandie.fermer()
		return
	if not is_visible_in_tree():
		return
	_agrandie = SCRIPT_CARTE_AGRANDIE.new()
	get_tree().current_scene.add_child(_agrandie)
	_agrandie.ouvrir(self)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_temps += delta
	if _temps >= INTERVALLE_ACTUALISATION:
		_temps = 0.0
		_actualiser_marqueurs()

func _creer_legende() -> void:
	var legende := GridContainer.new()
	legende.name = "FiltresEntites"
	legende.columns = 2
	legende.add_theme_constant_override("h_separation", 4)
	legende.add_theme_constant_override("v_separation", 3)
	get_parent().add_child.call_deferred(legende)
	for categorie in ORDRE_LEGENDE:
		var style: Dictionary = CATEGORIES[categorie]
		var bouton := Button.new()
		bouton.name = categorie
		bouton.text = "%s  %s" % [style["symbole"], style["libelle"]]
		bouton.tooltip_text = "Afficher ou masquer · %s" % style["libelle"]
		bouton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bouton.add_theme_font_size_override("font_size", 15)
		bouton.add_theme_color_override("font_pressed_color", style["couleur"])
		bouton.toggle_mode = true
		bouton.button_pressed = not _categories_masquees.has(categorie)
		bouton.modulate.a = 1.0 if bouton.button_pressed else 0.48
		bouton.toggled.connect(_basculer_filtre.bind(categorie, bouton))
		legende.add_child(bouton)

func _basculer_filtre(visible_sur_carte: bool, categorie: String, bouton: Button) -> void:
	if visible_sur_carte:
		_categories_masquees.erase(categorie)
	else:
		_categories_masquees[categorie] = true
	bouton.modulate.a = 1.0 if visible_sur_carte else 0.48
	_actualiser_marqueurs()

func _actualiser_marqueurs() -> void:
	var par_categorie := {}
	for categorie in CATEGORIES:
		par_categorie[categorie] = []
	var scene := get_tree().current_scene
	if scene != null:
		for noeud in get_tree().get_nodes_in_group("entites_minicarte"):
			var entite := noeud as Node2D
			if entite == null or entite.is_queued_for_deletion() or not entite.is_visible_in_tree():
				continue
			if not scene.is_ancestor_of(entite):
				continue
			var fiche: Dictionary = entite.repere_minicarte()
			var categorie := str(fiche.get("categorie", ""))
			if not par_categorie.has(categorie) or _categories_masquees.has(categorie):
				continue
			if categorie == "joueurs" and fiche.get("groupe", false):
				categorie = "groupe"
			var style: Dictionary = CATEGORIES[categorie]
			var texte := "%s · %s" % [fiche["nom"], fiche.get("role", style["libelle"])]
			par_categorie[categorie].append({
				"position": entite.global_position,
				"categorie": categorie,
				"texte": texte,
			})
	_marqueurs.clear()
	for position in reperes:
		_marqueurs.append({"position": position, "categorie": "", "texte": reperes[position]})
	for categorie in par_categorie:
		_marqueurs.append_array(par_categorie[categorie])
	_calque.queue_redraw()

func _dessiner_marqueurs() -> void:
	for marqueur in _marqueurs:
		var point := _position_carte(marqueur["position"])
		var categorie: String = marqueur["categorie"]
		var style: Dictionary = CATEGORIES.get(categorie, {})
		var rayon := float(style.get("rayon", 2.3))
		var couleur: Color = style.get("couleur", Color("#ead2a7"))
		if categorie == "ennemis" or categorie == "ressources":
			_dessiner_pointe(point, rayon, couleur, categorie == "ennemis")
			continue
		_calque.draw_circle(point, rayon + 1.0, CONTOUR, true, -1.0, true)
		_calque.draw_circle(point, rayon, couleur, true, -1.0, true)
		if rayon >= 5.0:
			var symbole: String = style["symbole"]
			var taille := 11
			var avance := _font.get_string_size(symbole, HORIZONTAL_ALIGNMENT_LEFT, -1, taille).x
			var ligne := _font.get_ascent(taille) - _font.get_height(taille) / 2.0
			_calque.draw_string(_font, point + Vector2(-avance / 2.0, ligne), symbole, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, CONTOUR)
	if is_instance_valid(joueur):
		var point := _position_carte(joueur.global_position)
		_calque.draw_circle(point, 5.5, Color("#132e31"), true, -1.0, true)
		_calque.draw_circle(point, 3.4, Color("#f9f6db"), true, -1.0, true)

func _dessiner_pointe(point: Vector2, rayon: float, couleur: Color, losange: bool) -> void:
	var silhouette := PackedVector2Array([Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT])
	if not losange:
		silhouette = PackedVector2Array([Vector2.UP, Vector2(1, 0.85), Vector2(-1, 0.85)])
	var bord := PackedVector2Array()
	var coeur := PackedVector2Array()
	for sommet in silhouette:
		bord.append(point + sommet * (rayon + 1.1))
		coeur.append(point + sommet * rayon)
	_calque.draw_colored_polygon(bord, CONTOUR)
	_calque.draw_colored_polygon(coeur, couleur)

func _position_carte(position_monde: Vector2) -> Vector2:
	return position_monde / dimensions_monde * size

func _get_tooltip(point: Vector2) -> String:
	var proches: Array[Dictionary] = []
	for marqueur in _marqueurs:
		var distance := point.distance_to(_position_carte(marqueur["position"]))
		if distance <= 8.0:
			proches.append({"distance": distance, "texte": marqueur["texte"]})
	if is_instance_valid(joueur) and point.distance_to(_position_carte(joueur.global_position)) <= 5.5:
		proches.append({"distance": 0.0, "texte": "Ta position"})
	proches.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	var lignes := PackedStringArray()
	for repere in proches:
		if not lignes.has(repere["texte"]):
			lignes.append(repere["texte"])
	if lignes.size() > 6:
		var autres := lignes.size() - 6
		lignes.resize(6)
		lignes.append("… +%d autres" % autres)
	return "\n".join(lignes)
