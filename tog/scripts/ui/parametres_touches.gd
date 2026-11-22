extends CanvasLayer
# Panneau des raccourcis clavier : chaque action (sorts, fin de tour,
# placement, sélection de cible) se réassigne en cliquant sur sa
# touche puis en appuyant sur la touche voulue ; Échap annule et les
# changements sont sauvegardés immédiatement (voir l'autoload Touches)

signal fermee

const THEME := preload("res://themes/theme_pirate.tres")

var theme_panneau: Theme = THEME

var _action_ecoute: String = ""
var _boutons: Dictionary = {}
var _panneau: PanelContainer

func _ready() -> void:
	layer = 40
	_construire()
	Touches.touches_modifiees.connect(_maj_boutons)

func _construire() -> void:
	var fond := ColorRect.new()
	fond.color = Color(0.0, 0.0, 0.0, 0.55)
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fond)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_panneau = PanelContainer.new()
	_panneau.theme = theme_panneau
	_panneau.custom_minimum_size = Vector2(650, 690)
	centre.add_child(_panneau)
	var marges := MarginContainer.new()
	marges.add_theme_constant_override("margin_left", 24)
	marges.add_theme_constant_override("margin_right", 24)
	marges.add_theme_constant_override("margin_top", 20)
	marges.add_theme_constant_override("margin_bottom", 20)
	_panneau.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var titre := Label.new()
	titre.text = "Raccourcis clavier"
	titre.add_theme_font_size_override("font_size", 26)
	colonne.add_child(titre)
	var aide := Label.new()
	aide.text = "Choisis une action, puis appuie sur la touche à lui attribuer. Échap annule."
	aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	colonne.add_child(aide)
	var defilement := ScrollContainer.new()
	defilement.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(defilement)
	var lignes := VBoxContainer.new()
	lignes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defilement.add_child(lignes)
	for action in Touches.actions:
		var ligne := HBoxContainer.new()
		ligne.add_theme_constant_override("separation", 12)
		lignes.add_child(ligne)
		var nom := Label.new()
		nom.text = str(Touches.actions[action])
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ligne.add_child(nom)
		var bouton := Button.new()
		bouton.custom_minimum_size = Vector2(150, 40)
		bouton.pressed.connect(_on_bouton_touche_presse.bind(str(action)))
		ligne.add_child(bouton)
		_boutons[str(action)] = bouton
	var pied := HBoxContainer.new()
	pied.alignment = BoxContainer.ALIGNMENT_CENTER
	pied.add_theme_constant_override("separation", 20)
	colonne.add_child(pied)
	var bouton_defauts := Button.new()
	bouton_defauts.text = "Réinitialiser"
	bouton_defauts.custom_minimum_size = Vector2(160, 44)
	bouton_defauts.pressed.connect(_on_bouton_defauts_presse)
	pied.add_child(bouton_defauts)
	var bouton_fermer := Button.new()
	bouton_fermer.text = "Fermer"
	bouton_fermer.custom_minimum_size = Vector2(160, 44)
	bouton_fermer.pressed.connect(fermer)
	pied.add_child(bouton_fermer)
	_maj_boutons()

func _on_bouton_touche_presse(action: String) -> void:
	_action_ecoute = action
	_maj_boutons()

func _on_bouton_defauts_presse() -> void:
	Touches.reinitialiser()

func fermer() -> void:
	fermee.emit()
	queue_free()

# capte la touche pressée pour l'action en cours de réassignation
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _action_ecoute == "":
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			fermer()
		elif event.keycode in [KEY_M, KEY_C]:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	var action := _action_ecoute
	_action_ecoute = ""
	if event.keycode != KEY_ESCAPE:
		Touches.definir(action, event.keycode)
	_maj_boutons()

func _maj_boutons() -> void:
	for action in _boutons:
		var bouton: Button = _boutons[action]
		if action == _action_ecoute:
			bouton.text = "Appuie une touche…"
			bouton.modulate = Color(1.0, 0.9, 0.6)
		else:
			bouton.text = Touches.libelle_action(action)
			bouton.modulate = Color.WHITE
