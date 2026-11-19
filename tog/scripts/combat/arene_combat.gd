extends Node2D

const TUILES := preload("res://assets/world/kit_cartes/sols.tres")
const TAILLE_CASE := 64
const PLANS := [
	[ # Piliers
		".............",
		".............",
		"....#...#....",
		"....#...#....",
		".............",
		"....#...#....",
		"....#...#....",
		".............",
		".............",
	],
	[ # Mur percé
		"..............",
		"......##......",
		"......##......",
		"..............",
		"..............",
		"......##......",
		"......##......",
		"......##......",
		"..............",
	],
	[ # Chicane
		"............",
		"....#.......",
		"....#.......",
		"....###.....",
		"............",
		".....###....",
		".......#....",
		".......#....",
		"............",
	],
	[ # Cour
		".............",
		"....#####....",
		"....#...#....",
		".............",
		".............",
		"....#...#....",
		"....#####....",
		".............",
	],
	[ # Deux passages
		"..............",
		"..............",
		".....####.....",
		".....####.....",
		"..............",
		".....####.....",
		".....####.....",
		"..............",
		"..............",
		"..............",
	],
]

var index_plan: int
var dimensions: Vector2i
var sol: TileMapLayer
var obstacles: TileMapLayer
var _camera: Camera2D

func _ready() -> void:
	z_index = -5
	var plan: Array = PLANS[index_plan]
	dimensions = Vector2i(plan[0].length(), plan.size())
	sol = TileMapLayer.new()
	obstacles = TileMapLayer.new()
	for couche in [sol, obstacles]:
		couche.tile_set = TUILES
		couche.collision_enabled = false
		couche.hide()
		add_child(couche)
	for y in dimensions.y:
		for x in dimensions.x:
			var couche := obstacles if plan[y][x] == "#" else sol
			couche.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	_camera = Camera2D.new()
	_camera.position = Vector2(dimensions * TAILLE_CASE) / 2.0
	add_child(_camera)
	_ajuster_camera()
	get_viewport().size_changed.connect(_ajuster_camera)

func activer_camera() -> void:
	_camera.make_current()
	_camera.force_update_scroll()

func _ajuster_camera() -> void:
	var taille := Vector2(dimensions * TAILLE_CASE)
	var disponible := get_viewport_rect().size * Vector2(0.78, 0.68)
	var zoom := minf(disponible.x / taille.x, disponible.y / taille.y)
	_camera.zoom = Vector2.ONE * minf(zoom, 1.4)

func case_joueur() -> Vector2i:
	return Vector2i(2, dimensions.y / 2)

func cases_ennemis() -> Array[Vector2i]:
	var depart := case_joueur()
	var arrivee := Vector2i(dimensions.x - 4, depart.y)
	var cases := sol.get_used_cells()
	cases.erase(depart)
	# La première ligne ennemie reste à portée après quelques déplacements.
	cases.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(arrivee) < b.distance_squared_to(arrivee))
	return cases

func _draw() -> void:
	var taille := Vector2(dimensions * TAILLE_CASE)
	draw_rect(Rect2(Vector2.ZERO, taille).grow(4.0), Color("#513f31"))
	for y in dimensions.y:
		for x in dimensions.x:
			var case := Vector2i(x, y)
			var cadre := Rect2(Vector2(case * TAILLE_CASE), Vector2.ONE * TAILLE_CASE)
			var teinte := Color("#b9a58a") if (x + y) % 2 == 0 else Color("#a89379")
			if obstacles.get_cell_source_id(case) != -1:
				draw_rect(cadre, Color("#463d36"))
				draw_rect(cadre.grow(-4.0), Color("#62574e"))
			else:
				draw_rect(cadre, teinte)
			draw_rect(cadre, Color("#71604e"), false, 1.0)
