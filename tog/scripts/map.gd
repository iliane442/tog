extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$makino.dialogue_opened.connect($DialogueUI.ouvrir)
	# croix de trésor sauvegardées : elles se redessinent au chargement
	CartesTresor.dessiner_sur_carte()
