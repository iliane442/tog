@tool
extends "res://scripts/world/terrain_zone.gd"

const DOSSIER := "res://assets/world/skypiea/terrasses/"
const DALLES: Array[Texture2D] = [
	preload(DOSSIER + "dalle.png"),
	preload(DOSSIER + "dalle_usee.png"),
	preload(DOSSIER + "dalle_mousse.png"),
	preload(DOSSIER + "dalle_doree.png"),
]
const PAREMENT := preload(DOSSIER + "parement.png")
const PAREMENT_MOUSSE := preload(DOSSIER + "parement_mousse.png")
const ESCALIER := preload(DOSSIER + "escalier.png")

const ORIGINE := Vector2(1664, 304)
const DEMI_TUILE := Vector2(64, 32)
const TAILLE_MONDE := Vector2(2312, 1392)
const PAS_NAVIGATION := 16
const HAUTEUR_SOMMET := 96
const HAUT_ESCALIER := Vector2(1504, 608)
const BAS_ESCALIER := Vector2(1376, 768)
const DEMI_ESCALIER := Vector2(32, 16)
const ANCRAGE_ESCALIER := Vector2(184, 41)
const RIVES := [
	[Vector2i.RIGHT, Vector2(64, 0), Vector2(0, 32)],
	[Vector2i.DOWN, Vector2(0, 32), Vector2(-64, 0)],
]
const COULEURS_CARTE := {
	"": Color("#5184af"),
	"V": Color("#ead4a9"),
	"G": Color("#d4bf91"),
	"P": Color("#f4dfaa"),
	"S": Color("#fff0ba"),
	"E": Color("#d9a85c"),
}

var _cases_escalier: Array[Vector2i] = []

func dimensions_monde() -> Vector2:
	return TAILLE_MONDE

func _ready() -> void:
	queue_redraw()

func preparer(sol: TileMapLayer, _falaises: TileMapLayer, _paysage: Node2D) -> void:
	sol.scale = Vector2.ONE * (float(PAS_NAVIGATION) / TAILLE_CASE)
	_cases_escalier.clear()
	var dimensions_carte := Vector2i(ceil(TAILLE_MONDE / PAS_NAVIGATION))
	var carte := Image.create_empty(dimensions_carte.x, dimensions_carte.y, false, Image.FORMAT_RGB8)
	for y in dimensions_carte.y:
		for x in dimensions_carte.x:
			var cellule := Vector2i(x, y)
			var monde := sol.to_global(sol.map_to_local(cellule))
			var terrain := surface_sous(monde)
			carte.set_pixelv(cellule, COULEURS_CARTE[terrain])
			if terrain == "E":
				_cases_escalier.append(cellule)
			elif terrain != "":
				sol.set_cell(cellule, 0, Vector2i.ZERO)
	apercu = ImageTexture.create_from_image(carte)
	queue_redraw()

func ouvrir_escalier(sol: TileMapLayer) -> void:
	for cellule in _cases_escalier:
		sol.set_cell(cellule, 0, Vector2i.ZERO)

func surface_sous(point: Vector2) -> String:
	if _terrain(_cellule_isometrique(point + Vector2(0, HAUTEUR_SOMMET))) == "S":
		return "S"
	var terrain := _terrain(_cellule_isometrique(point))
	if terrain != "" and terrain != "S":
		return terrain
	var marge := (BAS_ESCALIER - HAUT_ESCALIER).normalized() * 12.0
	var marches := PackedVector2Array([
		HAUT_ESCALIER - marge - DEMI_ESCALIER, HAUT_ESCALIER - marge + DEMI_ESCALIER,
		BAS_ESCALIER + marge + DEMI_ESCALIER, BAS_ESCALIER + marge - DEMI_ESCALIER,
	])
	return "E" if Geometry2D.is_point_in_polygon(point, marches) else ""

func _cellule_isometrique(point: Vector2) -> Vector2i:
	var p := (point - ORIGINE) / DEMI_TUILE
	return Vector2i(floor(Vector2(p.x + p.y, p.y - p.x) * 0.5 + Vector2(0.5, 0.5)))

func _centre(cellule: Vector2i, terrain: String) -> Vector2:
	var p := ORIGINE + Vector2(cellule.x - cellule.y, cellule.x + cellule.y) * DEMI_TUILE
	return p - Vector2(0, HAUTEUR_SOMMET) if terrain == "S" else p

func _terrain(cellule: Vector2i) -> String:
	if cellule.y < 0 or cellule.y >= plan.size():
		return ""
	if cellule.x < 0 or cellule.x >= plan[cellule.y].length():
		return ""
	var symbole := plan[cellule.y][cellule.x]
	return symbole if symbole != "." else ""

func _draw() -> void:
	# Les falaises du sommet passent derrière les plateformes plus basses.
	for terrain in ["S", "G", "P", "V"]:
		_dessiner_terrasse(terrain)
	draw_texture(ESCALIER, HAUT_ESCALIER - ANCRAGE_ESCALIER)

func _dessiner_terrasse(terrain: String) -> void:
	var cases: Array[Vector2i] = []
	for y in plan.size():
		for x in plan[y].length():
			if plan[y][x] == terrain:
				cases.append(Vector2i(x, y))
	for cellule in cases:
		_dessiner_rives(cellule, terrain)
	for cellule in cases:
		_dessiner_dalle(cellule, terrain)

func _dessiner_rives(cellule: Vector2i, terrain: String) -> void:
	var centre := _centre(cellule, terrain)
	for index in RIVES.size():
		var rive: Array = RIVES[index]
		var voisin: Vector2i = cellule + rive[0]
		var autre := _terrain(voisin)
		var hauteurs_communes := terrain != "S" and autre != "S"
		if autre == terrain or (autre != "" and hauteurs_communes):
			continue
		var debut: Vector2 = centre + rive[1]
		var fin: Vector2 = centre + rive[2]
		var profondeur := 142.0 if terrain == "S" else 106.0
		if terrain == "P":
			profondeur = 52.0
		var bas_debut := debut + Vector2(0, profondeur + 12.0 * sin(debut.x * 0.07))
		var bas_fin := fin + Vector2(0, profondeur + 12.0 * sin(fin.x * 0.07))
		var contour := PackedVector2Array([debut, fin, bas_fin, bas_debut])
		var claire := Color("#dad5db") if index == 0 else Color("#adb8d0")
		var sombre := Color("#697eae") if index == 0 else Color("#5e78a9")
		var matiere := PAREMENT_MOUSSE if (cellule.x * 3 + cellule.y + index) % 5 == 0 else PAREMENT
		draw_polygon(contour, PackedColorArray([claire, claire, sombre, sombre]),
			PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]), matiere)
		draw_line(debut, fin, Color("#b7a58d"), 2.0)

func _dessiner_dalle(cellule: Vector2i, terrain: String) -> void:
	var centre := _centre(cellule, terrain)
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0, -32), centre + Vector2(64, 0),
		centre + Vector2(0, 32), centre + Vector2(-64, 0),
	]), Color("#b9a388"))
	var variante := (cellule.x * 13 + cellule.y * 7) % 11
	var dalle := DALLES[0]
	if terrain == "P":
		dalle = DALLES[3]
	elif variante < 3:
		dalle = DALLES[1]
	elif variante == 4 and (
			_terrain(cellule + Vector2i.UP).is_empty() or _terrain(cellule + Vector2i.LEFT).is_empty()):
		dalle = DALLES[2]
	draw_texture(dalle, centre - DEMI_TUILE)
