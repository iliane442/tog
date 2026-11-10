# dialogue_ui.gd — sur le CanvasLayer
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var texte: TextEdit = $PanelContainer/VBoxContainer/Texte
@onready var btn_accepter: Button = $PanelContainer/VBoxContainer/Accepter
@onready var btn_refuser: Button = $PanelContainer/VBoxContainer/Refuser

var pnj_actuel: Node2D
var quest_id_actuel: String

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texte.editable = false
	panel.visible = false
	btn_accepter.pressed.connect(_on_accepter)
	btn_refuser.pressed.connect(_on_refuser)

func ouvrir(quest_id: String, pnj: Node2D) -> void:
	pnj_actuel = pnj
	quest_id_actuel = quest_id
	var quest = QuestManager.get_quest(quest_id)
	panel.visible = true
	texte.text = quest.titre + "\n\n" + quest.description
	
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		fermer()
		get_viewport().set_input_as_handled()

func _on_accepter() -> void:
	QuestManager.accepter_quete(quest_id_actuel)
	fermer()

func _on_refuser() -> void:
	fermer()

func fermer() -> void:
	panel.visible = false
	get_tree().paused = false
