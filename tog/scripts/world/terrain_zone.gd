@tool
extends Node2D

const TAILLE_CASE := 64
const CODES := ".:=#F~,"
const COULEURS := [
	Color("#698956"), Color("#b29568"), Color("#9b8c78"), Color("#697071"),
	Color("#284d3e"), Color("#285767"), Color("#416d46"),
]
const PINS := [
	preload("res://assets/world/kit_cartes/nature/pin_de_montagne.png"),
	preload("res://assets/world/world-prop-tree-pine-v1.png"),
	preload("res://assets/world/world-prop-tree-round-v1.png"),
]
const SOLS := preload("res://assets/world/kit_cartes/sols.png")
const SHADER_SOL := preload("res://assets/shaders/terrain_zone.gdshader")

@export var plan: PackedStringArray
@export var souterrain := false

var apercu: Texture2D
var _dimensions := Vector2i.ZERO

func dimensions_monde() -> Vector2:
	return Vector2(_dimensions * TAILLE_CASE)

func _ready() -> void:
	if Engine.is_editor_hint():
		_construire_textures()

func preparer(sol: TileMapLayer, falaises: TileMapLayer, paysage: Node2D) -> void:
	var codes := _construire_textures()
	var hasard := RandomNumberGenerator.new()
	hasard.seed = 82159
	for y in _dimensions.y:
		for x in _dimensions.x:
			var id := codes[_index(Vector2i(x, y))]
			var couche := falaises if id >= 3 and id <= 5 else sol
			couche.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
			if id == 4 and hasard.randf() < 0.65:
				_planter_arbre(paysage, Vector2i(x, y), hasard)

func _construire_textures() -> PackedByteArray:
	if plan.is_empty():
		return PackedByteArray()
	_dimensions = Vector2i(plan[0].length(), plan.size())
	var codes := PackedByteArray()
	codes.resize(_dimensions.x * _dimensions.y)
	var hauteurs := PackedInt32Array()
	hauteurs.resize(codes.size())
	var file: Array[Vector2i] = []
	for y in _dimensions.y:
		for x in _dimensions.x:
			var case_sol := Vector2i(x, y)
			var id := CODES.find(plan[y][x])
			codes[_index(case_sol)] = id
			if id == 3:
				hauteurs[_index(case_sol)] = -1
			else:
				file.append(case_sol)
	# Distance au pied de la pente, utilisée pour éclairer les crêtes.
	var cadre := Rect2i(Vector2i.ZERO, _dimensions)
	var debut := 0
	while debut < file.size():
		var case_sol := file[debut]
		debut += 1
		for direction in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var voisine: Vector2i = case_sol + direction
			if cadre.has_point(voisine) and hauteurs[_index(voisine)] < 0:
				hauteurs[_index(voisine)] = hauteurs[_index(case_sol)] + 1
				file.append(voisine)

	var donnees := Image.create_empty(_dimensions.x, _dimensions.y, false, Image.FORMAT_RGB8)
	var carte := Image.create_empty(_dimensions.x, _dimensions.y, false, Image.FORMAT_RGB8)
	for y in _dimensions.y:
		for x in _dimensions.x:
			var index := _index(Vector2i(x, y))
			var id := codes[index]
			var hauteur := clampf(hauteurs[index] / 10.0, 0.0, 1.0)
			donnees.set_pixel(x, y, Color(id / 8.0, hauteur, 0.0))
			var couleur: Color = COULEURS[id]
			if souterrain:
				if id == 3:
					couleur = Color("#272d3b")
				elif id == 5:
					couleur = Color("#305363")
				else:
					couleur = Color("#8b8075") if id == 2 else Color("#626779")
			elif id == 3:
				couleur = couleur.lerp(Color("#c1bab1"), hauteur)
			carte.set_pixel(x, y, couleur)
	apercu = ImageTexture.create_from_image(carte)
	var texture_donnees := ImageTexture.create_from_image(donnees)
	var materiau := ShaderMaterial.new()
	materiau.shader = SHADER_SOL
	materiau.set_shader_parameter("donnees", texture_donnees)
	materiau.set_shader_parameter("hauteur", texture_donnees)
	materiau.set_shader_parameter("sols", SOLS)
	materiau.set_shader_parameter("dimensions", Vector2(_dimensions))
	materiau.set_shader_parameter("souterrain", souterrain)
	material = materiau
	queue_redraw()
	return codes

func _index(case_sol: Vector2i) -> int:
	return case_sol.y * _dimensions.x + case_sol.x

func _planter_arbre(paysage: Node2D, case_sol: Vector2i, hasard: RandomNumberGenerator) -> void:
	var arbre := Sprite2D.new()
	arbre.texture = PINS[hasard.randi_range(0, PINS.size() - 1)]
	arbre.offset.y = -arbre.texture.get_height() * 0.5
	arbre.position = Vector2(case_sol * TAILLE_CASE) + Vector2(
		hasard.randf_range(12.0, 52.0), hasard.randf_range(14.0, 58.0))
	arbre.scale *= hasard.randf_range(0.72, 1.16)
	arbre.flip_h = hasard.randf() < 0.5
	paysage.add_child(arbre)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, dimensions_monde()), Color.WHITE)
