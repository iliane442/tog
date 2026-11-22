# coffre.gd — coffre interactif posé sur la carte
# Clic dessus à portée du joueur : animation d'ouverture puis fenêtre de loot.
extends Area2D

# rareté du coffre : 1 commun, 2 rare, 3 épique, 4 légendaire
@export var rarete: int = 1
# identifiant unique de sauvegarde (laisser vide pour l'auto-générer)
@export var coffre_id: String = ""

# distance max entre le joueur et le coffre pour l'ouvrir
const PORTEE := 150.0

const SPRITES := {
	1: [
		"res://assets/sprites/coffres/coffre_commun_ferme.png",
		"res://assets/sprites/coffres/coffre_commun_ouvert.png",
	],
	2: [
		"res://assets/sprites/coffres/coffre_rare_ferme.png",
		"res://assets/sprites/coffres/coffre_rare_ouvert.png",
	],
	3: [
		"res://assets/sprites/coffres/coffre_epique_ferme.png",
		"res://assets/sprites/coffres/coffre_epique_ouvert.png",
	],
	4: [
		"res://assets/sprites/coffres/coffre_legendaire_ferme.png",
		"res://assets/sprites/coffres/coffre_legendaire_ouvert.png",
	],
}

# teinte des étincelles selon la rareté du coffre
const COULEURS_RARETE := {
	1: Color(0.62, 0.62, 0.62),
	2: Color(0.0, 0.50, 1.0),
	3: Color(0.50, 0.0, 1.0),
	4: Color(1.0, 0.84, 0.0),
}

@onready var sprite: Sprite2D = $Sprite2D

var _particules: CPUParticles2D
var _ouverture_en_cours := false

func _ready() -> void:
	input_pickable = true
	add_to_group("coffres")
	# cliquable même quand une fenêtre de loot met le jeu en pause :
	# on peut ouvrir plusieurs coffres à la suite sans refermer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clamp_rarete()
	if coffre_id == "":
		coffre_id = "coffre_" + str(get_path())
	if Coffres.est_ouvert(coffre_id):
		_maj_sprite(true)
	_configurer_particules()

func _clamp_rarete() -> void:
	rarete = clampi(rarete, 1, 4)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var carte := get_tree().current_scene
	# Pendant la révélation du butin, il est possible d'ouvrir un autre
	# coffre proche. Les autres fenêtres gardent la main sur les entrées.
	if carte.has_method("exploration_disponible") and not carte.exploration_disponible():
		var fenetre_butin := carte.get_node_or_null("CoffreUI/Fenetre") as Control
		if fenetre_butin == null or not fenetre_butin.is_visible_in_tree():
			return
	var joueur := get_tree().get_first_node_in_group("player")
	if joueur == null:
		return
	# trop loin : on laisse le clic au joueur pour qu'il s'y déplace
	if joueur.global_position.distance_to(global_position) > PORTEE:
		return
	_viewport.set_input_as_handled()
	ouvrir()

# ouvre le coffre : première fois -> animation puis fenêtre ; sinon fenêtre directe
func ouvrir() -> void:
	if _ouverture_en_cours:
		return
	if not Coffres.est_ouvert(coffre_id):
		Coffres.ouvrir(coffre_id, rarete)
		_ouvert_seq_animee()
	else:
		_ouvrir_fenetre()

# le coffre se tremousse, s'ouvre d'un coup avec des étincelles, fenêtre à la fin
func _ouvert_seq_animee() -> void:
	_ouverture_en_cours = true
	var t := create_tween()
	t.tween_property(sprite, "rotation", 0.12, 0.08)
	t.tween_property(sprite, "rotation", -0.12, 0.12)
	t.tween_property(sprite, "rotation", 0.10, 0.10)
	t.tween_property(sprite, "rotation", 0.0, 0.06)
	t.tween_callback(_basculer_ouvert)
	t.tween_interval(0.05)
	t.tween_callback(_ouvrir_fenetre)
	t.finished.connect(func() -> void: _ouverture_en_cours = false)

# échange le sprite, pop de taille et éclat d'étincelles à la couleur de la rareté
func _basculer_ouvert() -> void:
	_maj_sprite(true)
	var couleur: Color = COULEURS_RARETE.get(rarete, COULEURS_RARETE[1])
	var degrade := Gradient.new()
	degrade.set_color(0, couleur)
	degrade.set_color(1, Color(couleur.r, couleur.g, couleur.b, 0.0))
	_particules.color_ramp = degrade
	_particules.restart()
	var t := create_tween()
	t.tween_property(sprite, "scale", Vector2(1.25, 1.25), 0.10).set_trans(Tween.TRANS_BACK)
	t.tween_property(sprite, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _ouvrir_fenetre() -> void:
	var ui := get_tree().get_first_node_in_group("coffres_ui")
	if ui != null:
		ui.ouvrir(self, Coffres.contenu(coffre_id))

# burst unique d'étincelles au-dessus du coffre, armé à l'ajout
func _configurer_particules() -> void:
	_particules = CPUParticles2D.new()
	_particules.position = Vector2(0, -34)
	# l'éclat continue d'animer pendant la fenêtre de loot (jeu en pause)
	_particules.process_mode = Node.PROCESS_MODE_ALWAYS
	_particules.emitting = false
	_particules.one_shot = true
	_particules.explosiveness = 1.0
	_particules.amount = 20
	_particules.lifetime = 0.55
	_particules.spread = 180.0
	_particules.direction = Vector2(0, -1)
	_particules.initial_velocity_min = 70.0
	_particules.initial_velocity_max = 160.0
	_particules.gravity = Vector2(0, 350)
	_particules.scale_amount_min = 2.5
	_particules.scale_amount_max = 4.5
	add_child(_particules)

func _maj_sprite(ouvert: bool) -> void:
	var paire: Array = SPRITES.get(rarete, SPRITES[1])
	var chemin: String = paire[1] if ouvert else paire[0]
	sprite.texture = load(chemin)
