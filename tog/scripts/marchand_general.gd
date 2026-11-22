# marchand_general.gd — PNJ marchand général : vend tout le catalogue du jeu
extends Node2D

# dimension de la zone cliquable autour du PNJ (englobe le sprite)
@export var largeur_zone_clic: float = 128.0
@export var hauteur_zone_clic: float = 160.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D

const shader_surlignage := preload("res://assets/shaders/surlignage.gdshader")

var player_near: bool = false
# vrai quand on a cliqué sur le PNJ depuis loin : boutique dès l'arrivée
var interaction_en_attente := false

func _ready() -> void:
	add_to_group("entites_minicarte")
	var mat := ShaderMaterial.new()
	mat.shader = shader_surlignage
	sprite.material = mat
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	var survol := _clic_sur_pnj(get_global_mouse_position())
	if sprite.material.get_shader_parameter("surligne") != survol:
		sprite.material.set_shader_parameter("surligne", survol)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_near = true
		if interaction_en_attente:
			interaction_en_attente = false
			ouvrir_boutique()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_near = false
		interaction_en_attente = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _clic_sur_pnj(get_global_mouse_position()):
			return
		var joueur := get_tree().get_first_node_in_group("player")
		if joueur != null and joueur.has_method("rejoindre_interaction"):
			joueur.rejoindre_interaction(global_position, ouvrir_boutique)
			get_viewport().set_input_as_handled()
			return
		if player_near:
			ouvrir_boutique()
			get_viewport().set_input_as_handled()
		else:
			# le clic propage au joueur (il marche vers le PNJ),
			# boutique dès qu'il entre dans la zone
			interaction_en_attente = true

func _clic_sur_pnj(point: Vector2) -> bool:
	var zone := Rect2(
		Vector2(-largeur_zone_clic / 2.0, -hauteur_zone_clic + 20.0),
		Vector2(largeur_zone_clic, hauteur_zone_clic)
	)
	return zone.has_point(point - global_position)

func ouvrir_boutique() -> void:
	var ui := get_tree().get_first_node_in_group("marchand_ui")
	if ui != null:
		ui.ouvrir()

func repere_minicarte() -> Dictionary:
	return {"categorie": "marchands", "nom": $NomMarchand.text, "role": "Vente de tout le catalogue"}
