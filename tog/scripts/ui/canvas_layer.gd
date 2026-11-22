# dialogue_ui.gd — sur le CanvasLayer
extends "res://scripts/ui/fenetre_secondaire.gd"

@onready var panel: PanelContainer = $PanelContainer
@onready var titre: Label = $PanelContainer/VBoxContainer/Titre
@onready var texte: Label = $PanelContainer/VBoxContainer/Defilement/Texte
@onready var btn_accepter: Button = $PanelContainer/VBoxContainer/Actions/Accepter
@onready var btn_refuser: Button = $PanelContainer/VBoxContainer/Actions/Refuser

var quest_id_actuel: String

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	btn_accepter.pressed.connect(_on_accepter)
	btn_refuser.pressed.connect(fermer)

func ouvrir(quest_id: String, _pnj: Node2D) -> void:
	if panel.visible or not presenter(panel, btn_accepter):
		return
	quest_id_actuel = quest_id
	var quest = QuestManager.get_quest(quest_id)
	titre.text = quest.titre
	texte.text = quest.description
	$PanelContainer/VBoxContainer/Defilement.scroll_vertical = 0

func _on_accepter() -> void:
	QuestManager.accepter_quete(quest_id_actuel)
	fermer()
