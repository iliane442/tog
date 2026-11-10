# pnj.gd — sur le nœud racine CharacterBody2D ou Node2D du PNJ
extends Node2D

@export var quest_id: String = "1"

# Dimension de la zone cliquable autour du PNJ (englobe le sprite)
@export var largeur_zone_clic: float = 128.0
@export var hauteur_zone_clic: float = 160.0

@onready var area: Area2D = $Area2D

signal dialogue_opened(quest_id: String, pnj: Node2D)

var player_near: bool = false
# vrai quand on a cliqué sur le PNJ depuis loin : dialogue dès l'arrivée
var interaction_en_attente := false
# quête actuellement proposée par ce PNJ (avance quand la quête est terminée)
var quest_actuelle := ""

func _ready() -> void:
	quest_actuelle = quest_id
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

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
		if not _clic_sur_pnj(get_global_mouse_position()):
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

# Détermine la quête à proposer : la courante, ou celle d'après si elle est
# terminée (y compris lors d'une session précédente). Renvoie "" quand il
# n'y a plus de quête à proposer.
func quest_suivante() -> String:
	while QuestManager.quetes.has(quest_actuelle) and (
		QuestManager.est_terminee(quest_actuelle)
		or QuestManager.est_deja_terminee(quest_actuelle)
	):
		quest_actuelle = str(int(quest_actuelle) + 1)
	if not QuestManager.quetes.has(quest_actuelle):
		return ""
	return quest_actuelle

func ouvrir_dialogue() -> void:
	var quest := quest_suivante()
	if quest != "":
		dialogue_opened.emit(quest, self)
