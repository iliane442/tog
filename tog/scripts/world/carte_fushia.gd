extends TextureRect

@export var dimensions_monde := Vector2.ONE
@export var reperes: Dictionary[Vector2, String] = {}

@onready var joueur: Node2D = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for repere in reperes:
		var point := _position_carte(repere)
		draw_circle(point, 3.5, Color("#302319"))
		draw_circle(point, 2.2, Color("#ffe1a1"))
	if is_instance_valid(joueur):
		var point := _position_carte(joueur.global_position)
		draw_circle(point, 5.5, Color("#132e31"))
		draw_circle(point, 3.4, Color("#f9f6db"))

func _position_carte(position_monde: Vector2) -> Vector2:
	return position_monde / dimensions_monde * size

func _get_tooltip(point: Vector2) -> String:
	var distance_min := 8.0
	var libelle := ""
	for repere in reperes:
		var distance := point.distance_to(_position_carte(repere))
		if distance < distance_min:
			distance_min = distance
			libelle = reperes[repere]
	return libelle
