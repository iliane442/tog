# dialogue_ui.gd — sur le CanvasLayer
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var texte: TextEdit = $PanelContainer/VBoxContainer/Texte
@onready var btn_accepter: Button = $PanelContainer/VBoxContainer/Accepter
@onready var btn_refuser: Button = $PanelContainer/VBoxContainer/Refuser

var pnj_actuel: Node2D
var quest_id_actuel: String
# libellé personnalisé + callback : le bouton Accepter devient un choix
# arbitraire (ex. « Prendre le bateau ») au lieu d'une quête
var _rappel_choix: Callable
var _libelle_choix: String
var _rappel_secondaire: Callable
var _btn_secondaire: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texte.editable = false
	panel.visible = false
	btn_accepter.pressed.connect(_on_accepter)
	btn_refuser.pressed.connect(_on_refuser)
	_btn_secondaire = Button.new()
	btn_refuser.get_parent().add_child(_btn_secondaire)
	btn_refuser.get_parent().move_child(_btn_secondaire, btn_refuser.get_index())
	_btn_secondaire.hide()
	_btn_secondaire.pressed.connect(_on_secondaire)

func ouvrir(quest_id: String, pnj: Node2D) -> void:
	pnj_actuel = pnj
	quest_id_actuel = quest_id
	_rappel_choix = Callable()
	_libelle_choix = ""
	var quest = QuestManager.get_quest(quest_id)
	_afficher(quest.titre, quest.description)

func ouvrir_texte(titre: String, description: String) -> void:
	pnj_actuel = null
	quest_id_actuel = ""
	_rappel_choix = Callable()
	_libelle_choix = ""
	_afficher(titre, description)

func ouvrir_choix(titre: String, description: String, libelle_bouton: String, rappel: Callable,
		libelle_secondaire := "", rappel_secondaire := Callable()) -> void:
	pnj_actuel = null
	quest_id_actuel = ""
	_rappel_choix = rappel
	_libelle_choix = libelle_bouton
	_afficher(titre, description)
	_rappel_secondaire = rappel_secondaire
	_btn_secondaire.text = libelle_secondaire
	_btn_secondaire.visible = rappel_secondaire.is_valid()

func _afficher(titre: String, description: String) -> void:
	_btn_secondaire.hide()
	var a_quete := quest_id_actuel != ""
	var a_choix := _rappel_choix.is_valid()
	btn_accepter.visible = a_quete or a_choix
	btn_accepter.text = _libelle_choix if a_choix else "Accepter"
	btn_refuser.text = "Refuser" if btn_accepter.visible else "Fermer"
	panel.visible = true
	texte.text = titre + "\n\n" + description
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		fermer()
		get_viewport().set_input_as_handled()

func _on_accepter() -> void:
	if quest_id_actuel != "":
		QuestManager.accepter_quete(quest_id_actuel)
		fermer()
		return
	var rappel := _rappel_choix
	# fermer AVANT d'exécuter : le changement de zone refuse les pauses
	fermer()
	rappel.call()

func _on_refuser() -> void:
	fermer()

func _on_secondaire() -> void:
	var rappel := _rappel_secondaire
	fermer()
	rappel.call()

func fermer() -> void:
	panel.visible = false
	get_tree().paused = false
