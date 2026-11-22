# pnj.gd — sur le nœud racine CharacterBody2D ou Node2D du PNJ
extends Node2D

# Dimension de la zone cliquable autour du PNJ (englobe le sprite)
@export var largeur_zone_clic: float = 128.0
@export var hauteur_zone_clic: float = 160.0

# chaîne des quêtes proposées par ce PNJ, dans l'ordre ; la première non
# terminée et non déjà en cours est proposée à chaque dialogue
@export var chain_quetes: Array[String] = ["1"]

@onready var area: Area2D = $Area2D
@onready var sprite: Sprite2D = $Sprite2D

const shader_surlignage := preload("res://assets/shaders/surlignage.gdshader")

signal dialogue_opened(quest_id: String, pnj: Node2D)

var player_near: bool = false
# vrai quand on a cliqué sur le PNJ depuis loin : dialogue dès l'arrivée
var interaction_en_attente := false

func _ready() -> void:
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
			ouvrir_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_near = false
		interaction_en_attente = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interaction_en_attente = false
		if not get_tree().current_scene.exploration_disponible():
			return
		if not _clic_sur_pnj(get_canvas_transform().affine_inverse() * event.position):
			return
		if player_near:
			ouvrir_dialogue()
			# le clic n'envoie pas le joueur ailleurs
			get_viewport().set_input_as_handled()
		else:
			# le clic propage au joueur (il marche vers le PNJ),
			# dialogue dès qu'il entre dans la zone
			interaction_en_attente = true

func _clic_sur_pnj(point: Vector2) -> bool:
	var zone := Rect2(
		Vector2(-largeur_zone_clic / 2.0, -hauteur_zone_clic + 20.0),
		Vector2(largeur_zone_clic, hauteur_zone_clic)
	)
	return zone.has_point(point - global_position)

# Détermine la quête à proposer : la première de la chaîne qui n'est ni déjà
# en cours ni terminée (y compris lors d'une session précédente).
# Renvoie "" quand il n'y a plus de quête à proposer.
func quest_suivante() -> String:
	for id_quete in chain_quetes:
		if not QuestManager.quetes.has(id_quete):
			continue
		if QuestManager.quetes_actives.has(id_quete) or QuestManager.est_deja_terminee(id_quete):
			continue
		return id_quete
	return ""

func ouvrir_dialogue() -> void:
	if not get_tree().current_scene.exploration_disponible():
		return
	var quest := quest_suivante()
	if quest != "":
		dialogue_opened.emit(quest, self)
