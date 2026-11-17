extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$makino.dialogue_opened.connect($DialogueUI.ouvrir)
