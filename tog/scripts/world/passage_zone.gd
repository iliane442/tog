extends Area2D

@export_file("*.tscn") var destination: String
@export var arrivee: StringName

func _ready() -> void:
	add_to_group("entites_minicarte")
	body_entered.connect(_traverser)

func _traverser(corps: Node2D) -> void:
	if corps.is_in_group("player"):
		get_tree().current_scene.rejoindre_zone(destination, arrivee)

func repere_minicarte() -> Dictionary:
	var etiquette := get_node_or_null("Etiquette") as Label
	var nom := etiquette.text if etiquette != null else "Changement de zone"
	return {"categorie": "voyages", "nom": nom, "role": "Passage"}
