# pnj.gd — sur le nœud racine CharacterBody2D ou Node2D du PNJ
extends Node2D

@export var quest_id: String = "chasse_loups"

@onready var area: Area2D = $Area2D

signal dialogue_opened(quest_id: String, pnj: Node2D)

var player_near: bool = false

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_near = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_near = false

func _unhandled_input(event: InputEvent) -> void:
	if player_near and event is InputEventKey and event.pressed and event.keycode == KEY_E:
		dialogue_opened.emit(quest_id, self)
		get_viewport().set_input_as_handled()
