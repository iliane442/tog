@tool
extends "res://scripts/world/terrain_terrasses_celestes.gd"

const EAU := preload("res://assets/shaders/eau_upper_yard.gdshader")
const COULEUR_EAU := Color("#29a8c9")
const SYMBOLES := "smhaoep"
const ORIGINE_PLAN := Vector2i(-3, -2)
const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
# L’ordre suit le dessin, du haut des falaises au palier d’entrée.
const TERRASSES := [
	[Rect2i(), 150, 185, Color("#8cb554")],
	[Rect2i(), 72, 184, Color("#84ae50")],
	[Rect2i(), 72, 202, Color("#91b557")],
	[Rect2i(), 126, 224, Color("#8bb250")],
	[Rect2i(), 0, 203, Color("#94b95e")],
	[Rect2i(), 0, 211, Color("#9cba5c")],
	[Rect2i(), -24, 132, Color("#d0be82")],
]
const LIAISONS := [
	[Vector2(11.2, 4.5), 150, Vector2(11.2, 5.5), 72, false],
	[Vector2(14.5, 8.2), 72, Vector2(17.5, 8.2), 72, true],
	[Vector2(11.1, 12.5), 72, Vector2(11.1, 13.5), 0, false],
	[Vector2(21.0, 12.5), 72, Vector2(21.0, 13.5), 0, false],
	[Vector2(27.0, 12.5), 72, Vector2(27.0, 13.5), 0, false],
	[Vector2(6.5, 19), 126, Vector2(8.5, 19), 0, false],
	[Vector2(14.5, 21.5), 0, Vector2(17.5, 21.5), 0, true],
	[Vector2(31.5, 19.5), 0, Vector2(34.5, 19.5), -24, true],
]
const RIVE_GAUCHE := 14.5
const RIVE_DROITE := 17.5
const PROFONDEUR_EAU := 10.0
# Début, seuil aval et niveau des trois tronçons du ruisseau.
const RUISSEAU := [Vector3(0.5, 4.5, 150), Vector3(4.5, 12.5, 72), Vector3(12.5, 28.5, 0)]

var _paves: Dictionary[Vector2i, bool] = {}

func _init() -> void:
	origine = Vector2(2304, 480)
	taille_monde = Vector2(4528, 2656)
	terrasses = TERRASSES
	liaisons = LIAISONS
	couleurs_bloquees.append(COULEUR_EAU)

func _ready() -> void:
	super._ready()
	var blanc := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	blanc.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(blanc)
	for troncon: Vector3 in RUISSEAU:
		_ajouter_eau(_surface(troncon), texture, 0)
	for index in RUISSEAU.size():
		var troncon: Vector3 = RUISSEAU[index]
		if index + 1 < RUISSEAU.size():
			var aval: Vector3 = RUISSEAU[index + 1]
			_ajouter_chute(troncon, aval.z, texture)
		else:
			_ajouter_chute(troncon, -285.0, texture, true)
	var tabliers := Node2D.new()
	tabliers.name = "PontsEtEscaliers"
	add_child(tabliers)
	tabliers.draw.connect(_dessiner_liaisons.bind(tabliers))

func _draw() -> void:
	_dessiner_terrasses()
	var centre := _projeter(Vector2(25.7, 8.5), 72)
	for index in 28:
		var angle := float(index) / 28.0 * TAU
		var direction := Vector2(cos(angle), sin(angle) * 0.5)
		if index % 5 != 2:
			draw_line(centre + direction * 145.0, centre + direction * 154.0, Color("#d1c59a"), 4.0)

func _preparer_dalles() -> void:
	_dalles.clear()
	_paves.clear()
	for y in plan.size():
		for x in plan[y].length():
			var symbole := plan[y][x]
			var secteur := SYMBOLES.find(symbole.to_lower())
			if secteur == -1:
				continue
			var cellule := Vector2i(x, y) + ORIGINE_PLAN
			_dalles[cellule] = secteur
			if symbole == symbole.to_upper():
				_paves[cellule] = true

func _texture_sol(cellule: Vector2i, _secteur: int) -> Texture2D:
	var variante := posmod(cellule.x * 19 + cellule.y * 11, 17)
	if _paves.has(cellule):
		return PAVE if variante > 5 else PAVE_MOUSSE
	var pres_du_sentier := _paves.has(cellule + Vector2i.RIGHT) or _paves.has(cellule + Vector2i.DOWN)
	return BORD_HERBE if pres_du_sentier and variante < 10 else HERBE

func _surface(troncon: Vector3) -> PackedVector2Array:
	var altitude := troncon.z - PROFONDEUR_EAU
	return PackedVector2Array([
		_projeter(Vector2(RIVE_GAUCHE, troncon.x), altitude),
		_projeter(Vector2(RIVE_DROITE, troncon.x), altitude),
		_projeter(Vector2(RIVE_DROITE, troncon.y), altitude),
		_projeter(Vector2(RIVE_GAUCHE, troncon.y), altitude),
	])

func _peindre_eau_carte(carte: Image) -> void:
	for troncon: Vector3 in RUISSEAU:
		_peindre_carte(carte, _surface(troncon), COULEUR_EAU)

func _filtrer_cases_isolees(carte: Image) -> void:
	# Les angles entre un tronc et une rive peuvent laisser des cases sans accès.
	var entree: Marker2D = get_node("../Arrivees/DepuisSkypiea")
	var depart := Vector2i(entree.position / PAS_NAVIGATION)
	var limites := Rect2i(Vector2i.ZERO, carte.get_size())
	var visitees := {depart: true}
	var file: Array[Vector2i] = [depart]
	var indice := 0
	while indice < file.size():
		for direction: Vector2i in DIRECTIONS:
			var case_sol := file[indice] + direction
			if limites.has_point(case_sol) and not visitees.has(case_sol) \
					and carte.get_pixelv(case_sol) not in couleurs_bloquees:
				visitees[case_sol] = true
				file.append(case_sol)
		indice += 1
	for y in limites.size.y:
		for x in limites.size.x:
			var case_sol := Vector2i(x, y)
			if not visitees.has(case_sol) and carte.get_pixelv(case_sol) not in couleurs_bloquees:
				carte.set_pixelv(case_sol, OBSTACLE)

func _ajouter_chute(troncon: Vector3, niveau_aval: float, texture: Texture2D, libre := false) -> void:
	var eau := _surface(troncon)
	var denivele := Vector2(0, troncon.z - niveau_aval)
	_ajouter_eau(PackedVector2Array([eau[3], eau[2], eau[2] + denivele, eau[3] + denivele]), texture, 1, libre)
	var centre := (eau[3] + eau[2]) * 0.5 + denivele
	var large := Vector2(113, 54)
	var long := Vector2(-34, 17) if not libre else Vector2(-34, 26)
	_ajouter_eau(PackedVector2Array([
		centre - large - long, centre + large - long,
		centre + large + long, centre - large + long,
	]), texture, 2)

func _ajouter_eau(contour: PackedVector2Array, texture: Texture2D, style: int, libre := false) -> void:
	var eau := Polygon2D.new()
	eau.polygon = contour
	eau.uv = PackedVector2Array(UV_QUAD)
	eau.texture = texture
	eau.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var matiere := ShaderMaterial.new()
	matiere.shader = EAU
	matiere.set_shader_parameter("dimensions", Vector2(
		contour[0].distance_to(contour[1]), contour[0].distance_to(contour[3])))
	matiere.set_shader_parameter("surface", style)
	matiere.set_shader_parameter("chute_libre", libre)
	eau.material = matiere
	add_child(eau)
