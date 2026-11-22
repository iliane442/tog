extends CanvasLayer

# Le dialogue, la boutique et le butin partagent la pause et sa libération.
var _panneau_ouvert: Control

func presenter(panneau: Control, premier_focus: Control) -> bool:
	if _panneau_ouvert == panneau:
		return true
	if get_tree().paused:
		return false
	_panneau_ouvert = panneau
	panneau.show()
	get_tree().paused = true
	premier_focus.grab_focus()
	return true

func fermer() -> void:
	if _panneau_ouvert == null:
		return
	_panneau_ouvert.hide()
	_panneau_ouvert = null
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if _panneau_ouvert == null or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		fermer()
