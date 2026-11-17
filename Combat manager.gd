
extends Node

signal combat_commence
signal combat_termine
signal placement_commence
signal placement_termine

var en_combat := false
var en_placement := false

func lancer_combat() -> void:
	if en_combat:
		return

	en_combat = true
	en_placement = true

	print("COMBAT LANCÉ — PHASE DE PLACEMENT")
	placement_commence.emit()


func valider_placement() -> void:
	if not en_combat or not en_placement:
		return

	en_placement = false
	print("PLACEMENT VALIDÉ — DÉBUT DES TOURS")

	placement_termine.emit()
	combat_commence.emit()


func terminer_combat() -> void:
	if not en_combat:
		return

	en_combat = false
	en_placement = false

	print("COMBAT TERMINÉ")
	combat_termine.emit()


# Pour tester : F lance le combat, G le termine
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			lancer_combat()
		elif event.keycode == KEY_G:
			terminer_combat()
