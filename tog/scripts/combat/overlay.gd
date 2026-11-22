extends Node2D

const HORS_GRILLE := Vector2i(-1, -1)

var cases_deplacement: Array[Vector2i] = []
var cases_sort: Array[Vector2i] = []
# aperçu de la figure du sort de zone autour de la cible survolée
var cases_zone: Array[Vector2i] = []
var _sol: TileMapLayer
var _lire_case_curseur: Callable
# fournit les cases de la figure (croix, barre...) selon la case
# survolée ; recalculées à chaque changement de survol
var _lire_apercu_zone: Callable
var _case_survolee := HORS_GRILLE
var _contour_survol: Node2D

func _ready() -> void:
	z_index = -4
	_contour_survol = Node2D.new()
	# Le contour de sélection reste lisible devant un muret.
	_contour_survol.z_as_relative = false
	_contour_survol.z_index = 1
	_contour_survol.draw.connect(_dessiner_survol)
	add_child(_contour_survol)
	set_process(false)

func definir_sol(sol: TileMapLayer, lire_case_curseur := Callable()) -> void:
	_sol = sol
	_lire_case_curseur = lire_case_curseur
	set_process(_sol != null and _lire_case_curseur.is_valid())
	_maj_survol()
	queue_redraw()

# enregistre la fonction qui calcule l'aperçu de figure du sort
func definir_apercu_zone(lire_apercu: Callable) -> void:
	_lire_apercu_zone = lire_apercu
	_maj_survol()

func afficher(cases: Array[Vector2i]) -> void:
	cases_deplacement = cases.duplicate()
	cases_sort.clear()
	cases_zone.clear()
	_maj_survol()
	queue_redraw()

func afficher_sort(cases: Array[Vector2i]) -> void:
	cases_sort = cases.duplicate()
	cases_zone.clear()
	_maj_survol()
	queue_redraw()

func effacer() -> void:
	cases_deplacement.clear()
	cases_sort.clear()
	cases_zone.clear()
	_maj_survol()
	queue_redraw()

func _process(_delta: float) -> void:
	_maj_survol()

func _maj_survol() -> void:
	var coordonnee := HORS_GRILLE
	if _lire_case_curseur.is_valid() and (not cases_deplacement.is_empty() or not cases_sort.is_empty()):
		var case_curseur: Vector2i = _lire_case_curseur.call()
		if cases_deplacement.has(case_curseur) or cases_sort.has(case_curseur):
			coordonnee = case_curseur
	if coordonnee != _case_survolee:
		_case_survolee = coordonnee
		_contour_survol.queue_redraw()
	# l'aperçu de figure suit le survol : il se recalcule quand la
	# case sous le curseur change
	if _lire_apercu_zone.is_valid():
		var nouvelles: Array[Vector2i] = _lire_apercu_zone.call()
		if nouvelles != cases_zone:
			cases_zone = nouvelles
			queue_redraw()

func _draw() -> void:
	if _sol == null or _sol.tile_set == null:
		return
	var taille := Vector2(_sol.tile_set.tile_size)
	_dessiner_cases(cases_deplacement, Color(0.2, 0.5, 1.0, 0.4), Color(0.5, 0.8, 1.0, 0.85), taille)
	_dessiner_cases(cases_sort, Color(1.0, 0.1, 0.1, 0.4), Color(1.0, 0.4, 0.4, 0.9), taille)
	# la figure de zone recouvre la portée : dorée, pour la distinguer
	_dessiner_cases(cases_zone, Color(1.0, 0.75, 0.2, 0.38), Color(1.0, 0.75, 0.35, 0.9), taille)

func _dessiner_cases(cases: Array[Vector2i], remplissage: Color, bordure: Color, taille: Vector2, epaisseur: float = 2.0) -> void:
	for case in cases:
		var coins := _coins_case(case, taille)
		draw_colored_polygon(coins, remplissage)
		coins.append(coins[0])
		draw_polyline(coins, bordure, epaisseur)

func _dessiner_survol() -> void:
	if _case_survolee == HORS_GRILLE or not is_instance_valid(_sol):
		return
	var coins := _coins_case(_case_survolee, Vector2(_sol.tile_set.tile_size))
	coins.append(coins[0])
	_contour_survol.draw_polyline(coins, Color("#242e37"), 5.0)
	_contour_survol.draw_polyline(coins, Color("#fff1c9"), 2.8)

func _coins_case(case: Vector2i, taille: Vector2) -> PackedVector2Array:
	var centre := _sol.map_to_local(case)
	var demi := taille * 0.5 - Vector2.ONE * 2.0
	return PackedVector2Array([
		to_local(_sol.to_global(centre - demi)),
		to_local(_sol.to_global(centre + Vector2(demi.x, -demi.y))),
		to_local(_sol.to_global(centre + demi)),
		to_local(_sol.to_global(centre + Vector2(-demi.x, demi.y))),
	])
