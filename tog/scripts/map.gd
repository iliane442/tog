extends Node2D

@onready var fenetre_menu: Control = $MenuUI/Fenetre
@onready var _combat = $CombatManager

func _ready() -> void:
	$makino.dialogue_opened.connect($DialogueUI.ouvrir)
	$MenuUI.menu_ouvert.connect($player.arreter_deplacement)
	$MenuUI.menu_ouvert.connect($CombatManager._quitter_survol_ennemi)

func exploration_disponible() -> bool:
	return not get_tree().paused and not fenetre_menu.visible and not _combat.en_combat
