extends Node2D

var cases_grille: Array[Vector2i] = []
var cases_deplacement: Array[Vector2i] = []
var cases_sort: Array[Vector2i] = []
var _sol: TileMapLayer

func _ready() -> void:
	_sol = get_parent().get_node_or_null("ground") as TileMapLayer
	z_index = 10

func afficher_grille(cases: Array[Vector2i]) -> void:
	cases_grille = cases.duplicate()
	queue_redraw()

func masquer_grille() -> void:
	cases_grille.clear()
	queue_redraw()

func afficher(cases: Array[Vector2i]) -> void:
	cases_deplacement = cases.duplicate()
	cases_sort.clear()
	queue_redraw()

func afficher_sort(cases: Array[Vector2i]) -> void:
	cases_sort = cases.duplicate()
	queue_redraw()

func effacer() -> void:
	cases_deplacement.clear()
	cases_sort.clear()
	queue_redraw()

func _draw() -> void:
	if _sol == null or _sol.tile_set == null:
		return
	var taille := Vector2(_sol.tile_set.tile_size)
	_dessiner_cases(cases_grille, Color(0.0, 0.0, 0.0, 0.25), Color(1.0, 1.0, 1.0, 0.55), taille, 1.0)
	_dessiner_cases(cases_deplacement, Color(0.2, 0.5, 1.0, 0.4), Color(0.5, 0.8, 1.0, 0.85), taille)
	_dessiner_cases(cases_sort, Color(1.0, 0.1, 0.1, 0.4), Color(1.0, 0.4, 0.4, 0.9), taille)

func _dessiner_cases(cases: Array[Vector2i], remplissage: Color, bordure: Color, taille: Vector2, epaisseur: float = 2.0) -> void:
	for case in cases:
		var centre := to_local(_sol.to_global(_sol.map_to_local(case)))
		var rectangle := Rect2(centre - taille / 2.0, taille)
		draw_rect(rectangle, remplissage)
		draw_rect(rectangle, bordure, false, epaisseur)
