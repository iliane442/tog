extends Node2D

@export var titre: String
@export_multiline var description: String
@export var quete: String
@export var objet: String
@export var quantite := 1
@export var retour_secondes := 45.0
@export var interlocuteur := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var etiquette: Label = $Etiquette

var _disponible := true

func _ready() -> void:
	if objet != "":
		add_to_group("entites_minicarte")
	var action := "Lire · "
	if objet != "":
		action = "Récolter · "
	elif interlocuteur:
		action = "Parler à "
	etiquette.text = action + titre
	etiquette.hide()

func repere_minicarte() -> Dictionary:
	if not _disponible:
		return {}
	return {"categorie": "ressources", "nom": titre, "role": "À récolter"}

func _process(_delta: float) -> void:
	etiquette.visible = _disponible and _survole()

func _survole() -> bool:
	return sprite.get_rect().grow(8.0).has_point(sprite.get_local_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if not _disponible or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _survole() or get_tree().current_scene.get_node("CombatManager").en_combat:
		return
	var joueur := get_tree().get_first_node_in_group("player")
	if joueur != null:
		joueur.rejoindre_interaction(global_position, _interagir)
		get_viewport().set_input_as_handled()

func _interagir() -> void:
	if not _disponible:
		return
	if objet == "":
		if quete != "":
			QuestManager.progresser(quete, str(name))
		get_tree().current_scene.get_node("DialogueUI").ouvrir_texte(titre, description)
		return
	_disponible = false
	sprite.modulate.a = 0.38
	etiquette.hide()
	Inventaire.ajouter_objet(objet, quantite)
	if quete != "":
		QuestManager.progresser(quete)
	get_tree().current_scene.afficher_info_fushia("+%d %s" % [quantite, Inventaire.nom_objet(objet)])
	await get_tree().create_timer(retour_secondes, false).timeout
	_disponible = true
	sprite.modulate.a = 1.0
