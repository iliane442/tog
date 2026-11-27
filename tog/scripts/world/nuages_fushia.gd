extends Node2D

const FORMES := [
	preload("res://tinyswords/Terrain/Decorations/Clouds/Clouds_01.png"),
	preload("res://tinyswords/Terrain/Decorations/Clouds/Clouds_03.png"),
	preload("res://tinyswords/Terrain/Decorations/Clouds/Clouds_06.png"),
]
const BORDURE := 640.0
const VITESSES := [39.0, 52.0, 34.0, 47.0, 57.0, 42.0]
const POSITIONS := [
	Vector2(540, 560), Vector2(2330, 380), Vector2(3470, 680),
	Vector2(1180, 1540), Vector2(2690, 1250), Vector2(4060, 1820),
]

@onready var _largeur: float = get_parent().get_node("TerrainZone").dimensions_monde().x

func _ready() -> void:
	for indice in POSITIONS.size():
		var nuage := Sprite2D.new()
		nuage.texture = FORMES[indice % FORMES.size()]
		nuage.position = POSITIONS[indice]
		nuage.scale = Vector2.ONE * (1.0 + 0.14 * (indice % 3))
		nuage.modulate = Color(1.0, 0.97, 0.91, 0.24 + 0.04 * (indice % 3))
		add_child(nuage)

func _process(delta: float) -> void:
	for indice in get_child_count():
		var nuage := get_child(indice) as Sprite2D
		nuage.position.x = wrapf(
			nuage.position.x + VITESSES[indice] * delta, -BORDURE, _largeur + BORDURE
		)
