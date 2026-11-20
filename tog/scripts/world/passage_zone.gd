extends Area2D

@export_file("*.tscn") var destination: String
@export var arrivee: StringName

func _ready() -> void:
	body_entered.connect(_traverser)

func _traverser(corps: Node2D) -> void:
	if corps.is_in_group("player"):
		get_tree().current_scene.rejoindre_zone(destination, arrivee)
