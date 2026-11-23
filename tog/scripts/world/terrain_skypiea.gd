@tool
extends "res://scripts/world/terrain_terrasses_celestes.gd"

enum { PORTE_FORET, HAUTE_VILLE, MARCHE, ATELIERS, BASSINS, PORT, QUAI }
# Limites dans la grille iso, altitude, profondeur de la falaise et couleur sur la carte.
const TERRASSES := [
	[Rect2i(-8, 4, 5, 7), 96, 142, Color("#c6c68a")],
	[Rect2i(4, -22, 20, 15), 128, 206, Color("#edd5a0")],
	[Rect2i(0, 0, 20, 17), 0, 154, Color("#efd39f")],
	[Rect2i(23, 0, 18, 17), -56, 187, Color("#ecd09a")],
	[Rect2i(44, 2, 8, 12), -56, 200, Color("#87b05a")],
	[Rect2i(0, 19, 18, 15), -56, 162, Color("#e9c69a")],
	[Rect2i(3, 34, 8, 6), -56, 0, Color("#cb9351")],
]
# Extrémités dans la grille, altitudes et tablier en bois ou en pierre.
const LIAISONS := [
	[Vector2(-3.5, 7), 96, Vector2(-0.5, 7), 0, false],
	[Vector2(11, -7.5), 128, Vector2(11, -5.0), 44, false],
	[Vector2(11, -5.0), 44, Vector2(11, -0.5), 0, true],
	[Vector2(19.5, 8), 0, Vector2(22.5, 8), -56, false],
	[Vector2(40.5, 7), -56, Vector2(43.5, 7), -56, true],
	[Vector2(9, 16.5), 0, Vector2(9, 18.5), -56, false],
]
const CENTRE_PLACE := Vector2(9.5, 8)

func _init() -> void:
	origine = Vector2(3008, 1296)
	taille_monde = Vector2(6576, 3648)
	terrasses = TERRASSES
	liaisons = LIAISONS

func _draw() -> void:
	_dessiner_terrasses()
	_dessiner_place()
	_dessiner_liaisons(self)

func _texture_sol(cellule: Vector2i, secteur: int) -> Texture2D:
	var variante := posmod(cellule.x * 13 + cellule.y * 7, 17)
	if secteur == QUAI:
		return PLANCHES
	var zone: Rect2i = TERRASSES[secteur][0]
	var bord := (cellule.x == zone.position.x or cellule.x == zone.end.x - 1
		or cellule.y == zone.position.y or cellule.y == zone.end.y - 1)
	if secteur == BASSINS and (absi(cellule.y - 7) > 1 and cellule.x != 48):
		return BORD_HERBE if variante < 4 else HERBE
	if bord and variante < 6:
		return HERBE
	return PAVE_MOUSSE if variante < 4 or bord else PAVE

func _dessiner_place() -> void:
	var centre := _projeter(CENTRE_PLACE, 0)
	for rayon in [183.0, 197.0, 269.0, 276.0]:
		var anneau := PackedVector2Array()
		for index in 97:
			var a := TAU * index / 96.0
			anneau.append(centre + Vector2(cos(a), sin(a) * 0.5) * rayon)
		var couleur := Color("#ab813e") if rayon < 200.0 else Color("#ccb07c")
		draw_polyline(anneau, couleur, 2.0, true)

