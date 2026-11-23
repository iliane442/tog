extends Node2D

const TUILES := preload("res://assets/world/kit_cartes/sols.tres")
const TEXTURE_PIERRE := preload("res://assets/world/kit_cartes/sols.png")
const TAILLE_CASE := 64
const PROJECTION := Transform2D(Vector2(0.875, 0.40625), Vector2(-0.875, 0.40625), Vector2.ZERO)
const HAUTEUR_PLATEAU := 34.0
const HAUTEUR_MUR := 42.0
const OPACITE_MUR := 0.38
const CASE_HORS_ARENE := Vector2i(-1, -1)
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
var dallage: Texture2D
var maconnerie: Texture2D
var fond_personnalise: Texture2D
var sol: TileMapLayer
var obstacles: TileMapLayer
var _camera: Camera2D
var _plateau: Node2D
var _cadre_camera: Rect2

func _ready() -> void:
	y_sort_enabled = true
	var plan: Array = PLANS[index_plan]
	dimensions = Vector2i(plan[0].length(), plan.size())
	sol = TileMapLayer.new()
	obstacles = TileMapLayer.new()
	for couche in [sol, obstacles]:
		couche.tile_set = TUILES
		couche.collision_enabled = false
		couche.transform = PROJECTION
		couche.hide()
		add_child(couche)
	for y in dimensions.y:
		for x in dimensions.x:
			var couche := obstacles if plan[y][x] == "#" else sol
			couche.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	_creer_fond()
	_plateau = Node2D.new()
	_plateau.z_index = -5
	_plateau.draw.connect(_dessiner_plateau)
	add_child(_plateau)
	for case in obstacles.get_used_cells():
		var bloc := Node2D.new()
		bloc.position = _contour_mur(case)[2]
		bloc.self_modulate.a = OPACITE_MUR
		bloc.draw.connect(_dessiner_mur.bind(bloc, case))
		add_child(bloc)

	var coins := _contour(Rect2(Vector2.ZERO, Vector2(dimensions * TAILLE_CASE)))
	_cadre_camera = Rect2(Vector2(coins[3].x, -96.0),
		Vector2(coins[1].x - coins[3].x, coins[2].y + HAUTEUR_PLATEAU + 104.0))
	_camera = Camera2D.new()
	_camera.position = _cadre_camera.get_center()
	add_child(_camera)
	_ajuster_camera()
	get_viewport().size_changed.connect(_ajuster_camera)

func activer_camera() -> void:
	_camera.make_current()
	_camera.force_update_scroll()

func _ajuster_camera() -> void:
	var disponible := get_viewport_rect().size * Vector2(0.84, 0.70)
	var zoom := minf(disponible.x / _cadre_camera.size.x, disponible.y / _cadre_camera.size.y)
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

func _creer_fond() -> void:
	var couche := CanvasLayer.new()
	couche.layer = -1
	add_child(couche)
	var fond := TextureRect.new()
	if fond_personnalise != null:
		fond.texture = fond_personnalise
		fond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		fond.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fond.modulate = Color(0.77, 0.86, 0.96)
	else:
		var degrade := Gradient.new()
		degrade.colors = PackedColorArray([Color("#354047"), Color("#1a2128"), Color("#11171e")])
		degrade.offsets = PackedFloat32Array([0.0, 0.64, 1.0])
		var texture_fond := GradientTexture2D.new()
		texture_fond.gradient = degrade
		texture_fond.fill = GradientTexture2D.FILL_RADIAL
		texture_fond.fill_from = Vector2(0.5, 0.46)
		texture_fond.fill_to = Vector2(1.0, 1.0)
		fond.texture = texture_fond
		fond.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	couche.add_child(fond)
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _contour(cadre: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		PROJECTION * cadre.position,
		PROJECTION * Vector2(cadre.end.x, cadre.position.y),
		PROJECTION * cadre.end,
		PROJECTION * Vector2(cadre.position.x, cadre.end.y),
	])

func _contour_mur(case: Vector2i) -> PackedVector2Array:
	return _contour(Rect2(Vector2(case * TAILLE_CASE), Vector2.ONE * TAILLE_CASE).grow(-3.0))

func _dessiner_plateau() -> void:
	var cadre := Rect2(Vector2.ZERO, Vector2(dimensions * TAILLE_CASE))
	var bord := _contour(cadre.grow(5.0))
	_plateau.draw_colored_polygon(_decaler(bord, Vector2(0, HAUTEUR_PLATEAU + 14.0)), Color("#161d22"))
	_dessiner_faces(_plateau, bord, HAUTEUR_PLATEAU, Color("#574b40"), Color("#3b3735"))
	_plateau.draw_colored_polygon(bord, Color("#353633"))
	for y in dimensions.y:
		for x in dimensions.x:
			var dalle := Rect2(Vector2(x, y) * TAILLE_CASE, Vector2.ONE * TAILLE_CASE).grow(-1.2)
			var contour := _contour(dalle)
			var teinte := Color("#a59a84").darkened(float((x * 17 + y * 11) % 5) * 0.024)
			if obstacles.get_cell_source_id(Vector2i(x, y)) != -1:
				teinte = teinte.darkened(0.26)
			_plateau.draw_colored_polygon(contour, teinte)
			if dallage == null:
				_appliquer_pierre(_plateau, contour, Vector2(0.0, 0.5), 0.42)
			else:
				var origine := Vector2(x % 2, y % 2) * 0.5
				_appliquer_pierre(_plateau, contour, origine, 0.68, dallage, Vector2(0.5, 0.5))
			_plateau.draw_line(contour[0], contour[1], Color(0.86, 0.79, 0.64, 0.4), 1.3)

func _dessiner_mur(bloc: Node2D, case: Vector2i) -> void:
	var base := _decaler(_contour_mur(case), -bloc.position)
	var dessus := _decaler(base, Vector2.UP * HAUTEUR_MUR)
	_dessiner_faces(bloc, dessus, HAUTEUR_MUR, Color("#746759"), Color("#4d4b49"))
	bloc.draw_colored_polygon(dessus, Color("#888070"))
	if maconnerie == null:
		_appliquer_pierre(bloc, dessus, Vector2(1.0 / 3.0, 0.5), 0.48)
	else:
		_appliquer_pierre(bloc, dessus, Vector2.ZERO, 0.70, maconnerie, Vector2(0.5, 0.5))
	bloc.draw_polyline(PackedVector2Array([dessus[3], dessus[0], dessus[1]]), Color("#b2a38b"), 2.0)
	bloc.draw_polyline(PackedVector2Array([dessus[1], dessus[2], dessus[3]]), Color("#3d3b37"), 2.0)

func _dessiner_faces(support: Node2D, dessus: PackedVector2Array, hauteur: float,
		gauche: Color, droite: Color) -> void:
	var bas := _decaler(dessus, Vector2.DOWN * hauteur)
	support.draw_colored_polygon(PackedVector2Array([dessus[3], dessus[2], bas[2], bas[3]]), gauche)
	support.draw_colored_polygon(PackedVector2Array([dessus[2], dessus[1], bas[1], bas[2]]), droite)
	var joint := Vector2.DOWN * hauteur * 0.54
	support.draw_polyline(PackedVector2Array([
		dessus[3] + joint, dessus[2] + joint, dessus[1] + joint,
	]), Color(0.14, 0.13, 0.13, 0.42), 2.0)
	support.draw_line(bas[3], bas[2], gauche.darkened(0.28), 2.0)
	support.draw_line(bas[2], bas[1], droite.darkened(0.28), 2.0)

func _appliquer_pierre(support: Node2D, points: PackedVector2Array, origine: Vector2,
		opacite: float, texture: Texture2D = TEXTURE_PIERRE,
		dimensions_uv := Vector2(1.0 / 3.0, 0.5)) -> void:
	var marge := Vector2(0.004, 0.006)
	var taille := dimensions_uv - 2.0 * marge
	origine += marge
	support.draw_polygon(points, PackedColorArray([Color(1.0, 0.99, 0.95, opacite)]), PackedVector2Array([
		origine, origine + Vector2(taille.x, 0.0), origine + taille, origine + Vector2(0.0, taille.y),
	]), texture)

func _decaler(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var resultat := PackedVector2Array()
	for point in points:
		resultat.append(point + offset)
	return resultat
