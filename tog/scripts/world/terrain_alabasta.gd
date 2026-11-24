@tool
extends "res://scripts/world/terrain_terrasses_celestes.gd"

const ASSETS_ALABASTA := "res://assets/world/alabasta/"
const EAUX := preload("res://scripts/world/eaux_alabasta.gd")
const SHADER_MER := preload("res://assets/shaders/mer_alabasta.gdshader")
const MER := preload(ASSETS_ALABASTA + "terrain/mer.png")
const SABLE := preload(ASSETS_ALABASTA + "terrain/sable.png")
const DALLAGE := preload(ASSETS_ALABASTA + "terrain/dallage.png")
const PISTE := preload(ASSETS_ALABASTA + "terrain/route.png")
const ROCHE_ROUGE := preload(ASSETS_ALABASTA + "terrain/roche.png")
const MUR_CALCAIRE := preload(ASSETS_ALABASTA + "terrain/maconnerie.png")

enum Sol { SABLE, DALLAGE, PISTE }
enum Relief { SOL, VILLE, MESA }

const TEXTURES := [SABLE, DALLAGE, PISTE]
const COULEURS_SOL := [Color("#dfaf65"), Color("#f2ce9c"), Color("#edc48a")]
const COULEUR_QUAI := Color("#b97c47")
const COULEUR_MER := Color("#22658a")
const NIVEAU_MER := -46
const VOISINES := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ROUTES := [
	[Vector2(9.6, 21), Vector2(11, 20), Vector2(13, 18), Vector2(17, 17), Vector2(20, 15), Vector2(20, 11)],
	[Vector2(13, 18), Vector2(11, 16), Vector2(8, 16)],
	[Vector2(18, 17), Vector2(21, 19), Vector2(25, 19), Vector2(26, 18)],
]
const MESAS := [
	[Vector2(-0.5, 6), Vector2(5.3, 3.6), 132], [Vector2(4, 7), Vector2(5, 2.7), 85],
	[Vector2(-5, 14), Vector2(4, 5.2), 95], [Vector2(8, 1), Vector2(5.2, 4.2), 150],
	[Vector2(3, -4), Vector2(6.9, 5.2), 132], [Vector2(25, -4), Vector2(10, 3.5), 160],
	[Vector2(32, 3), Vector2(6.1, 5.4), 215], [Vector2(31, 17), Vector2(3.9, 5), 95],
	[Vector2(32, 22), Vector2(6, 4.2), 100], [Vector2(24, 28), Vector2(5, 3.6), 78],
	[Vector2(32, 33), Vector2(6.8, 4), 72], [Vector2(11, 12), Vector2(2.3, 2.6), 52],
	[Vector2(14, 10.5), Vector2(2.6, 2.2), 70], [Vector2(24, 13), Vector2(3.2, 1.9), 62],
]

# Départ dans la grille, altitude, arrivée, altitude, demi-largeur.
const ESCALIERS := [
	[Vector2(9.6, 25.1), 48, Vector2(11.85, 25.1), 0, 0.87],
	[Vector2(9.62, 22.0), 48, Vector2(9.62, 20.45), 0, 0.87],
	[Vector2(8.8, 16), 108, Vector2(12.2, 16), 0, 1.22],
	[Vector2(3, 14.55), 122, Vector2(4.55, 14.55), 108, 0.89],
	[Vector2(20.15, 10.72), 150, Vector2(20.15, 15.55), 0, 1.30],
	[Vector2(19.45, 5.1), 220, Vector2(19.45, 7.35), 150, 1.10],
]
const QUAIS := [
	[Vector2(9.7, 30.00), 0, Vector2(9.7, 32.48), -14, 0.53],
	[Vector2(13.85, 30.03), 0, Vector2(13.85, 32.45), -14, 0.54],
	[Vector2(17.65, 30.00), 0, Vector2(17.65, 32.10), -14, 0.52],
]

var escaliers: Array = ESCALIERS
var quais: Array = QUAIS
var _carreaux: Dictionary[Vector2i, Vector3i] = {}
var _ordre: Array[Vector2i] = []

func _init() -> void:
	origine = Vector2(1600, 104)
	taille_monde = Vector2(3200, 1856)
	dallage = DALLAGE
	maconnerie = ROCHE_ROUGE

func _ready() -> void:
	_preparer_dalles()
	_creer_mer()
	queue_redraw()

func preparer(sol: TileMapLayer, _falaises: TileMapLayer, paysage: Node2D) -> void:
	_preparer_dalles()
	sol.clear()
	sol.scale = Vector2.ONE * (float(PAS_NAVIGATION) / TAILLE_CASE)
	var taille := Vector2i(taille_monde / PAS_NAVIGATION)
	var carte := Image.create_empty(taille.x, taille.y, false, Image.FORMAT_RGB8)
	carte.fill(COULEUR_MER)

	for cellule in _ordre:
		var dalle := _carreaux[cellule]
		var contour := _contour_dalle(_projeter(cellule, dalle.x))
		for direction in [1, 2]:
			var face := _face(cellule, dalle.x, contour, direction)
			if not face.is_empty():
				_peindre_carte(carte, face, OBSTACLE)
		var couleur: Color = COULEURS_SOL[dalle.y] if dalle.z != Relief.MESA else OBSTACLE
		_peindre_carte(carte, contour, couleur)
		if dalle.z != Relief.MESA:
			_bloquer_bords_de_terrasse(carte, cellule, dalle.x, contour)
	for escalier in escaliers:
		_peindre_escalier(carte, escalier)
	for quai in quais:
		_peindre_carte(carte, _polygone_liaison(quai, 12.0), COULEUR_QUAI)
	for decor in paysage.get_children():
		if decor.has_meta("emprise"):
			_bloquer_emprise(carte, decor)
	var joueur: Node2D = get_parent().get_node("player")
	_garder_sol_accessible(carte, joueur.position)
	for y in taille.y:
		for x in taille.x:
			var couleur := carte.get_pixel(x, y)
			if _est_sol(couleur):
				sol.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	apercu = ImageTexture.create_from_image(carte)

func _preparer_dalles() -> void:
	if not _carreaux.is_empty():
		return
	var cadre := Rect2(Vector2.ZERO, taille_monde).grow(424.0)
	for u in range(-28, 63):
		for v in range(-30, 62):
			var cellule := Vector2i(u, v)
			if v > _bord_de_mer(u) or not cadre.has_point(_projeter(cellule, 0)):
				continue
			_carreaux_ajouter(cellule)
	_ordre = _carreaux.keys()
	_ordre.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x + a.y == b.x + b.y else a.x + a.y < b.x + b.y)

func _carreaux_ajouter(cellule: Vector2i) -> void:
	if _sur_terrasse(Rect2i(7, 22, 12, 9), cellule):
		var haute_ville := _sur_terrasse(Rect2i(7, 22, 4, 7), cellule)
		_carreaux[cellule] = Vector3i(48 if haute_ville else 0, Sol.DALLAGE, Relief.VILLE)
	elif _sur_terrasse(Rect2i(-1, 11, 11, 12), cellule):
		var casino := _sur_terrasse(Rect2i(0, 12, 4, 6), cellule)
		_carreaux[cellule] = Vector3i(122 if casino else 108, Sol.DALLAGE, Relief.VILLE)
	elif _sur_terrasse(Rect2i(14, 1, 13, 11), cellule):
		var palais := _sur_terrasse(Rect2i(15, 2, 8, 4), cellule)
		_carreaux[cellule] = Vector3i(220 if palais else 150, Sol.DALLAGE, Relief.VILLE)
	else:
		var piste := _distance_piste(Vector2(cellule) + Vector2(0.5, 0.5))
		var hauteur := 0 if piste < 1.2 else _altitude_mesa(cellule)
		var sol := Sol.PISTE if piste < 0.93 else Sol.SABLE
		_carreaux[cellule] = Vector3i(hauteur, sol, Relief.MESA if hauteur > 0 else Relief.SOL)

func _sur_terrasse(cadre: Rect2i, cellule: Vector2i) -> bool:
	if not cadre.has_point(cellule):
		return false
	var angle_x := cellule.x == cadre.position.x or cellule.x == cadre.end.x - 1
	var angle_y := cellule.y == cadre.position.y or cellule.y == cadre.end.y - 1
	return not (angle_x and angle_y)

func _bord_de_mer(u: int) -> int:
	if u < 4:
		return 23 + floori(u * 0.21) + roundi(sin(u * 0.7))
	if u <= 16:
		return 30 - maxi(0, roundi((7 - u) * 0.7))
	return 30 + floori((u - 16) * 0.62 + sin(u * 0.7))

func _distance_piste(point: Vector2) -> float:
	var distance := INF
	for route in ROUTES:
		for index in range(1, route.size()):
			var proche := Geometry2D.get_closest_point_to_segment(point, route[index - 1], route[index])
			distance = minf(distance, point.distance_to(proche))
	return distance

func _altitude_mesa(cellule: Vector2i) -> int:
	var hauteur := 0
	var bruit := (float(posmod(hash(cellule), 1000)) / 1000.0 - 0.5) * 0.19
	for mesa in MESAS:
		var centre: Vector2 = mesa[0]
		var rayon: Vector2 = mesa[1]
		var contour := ((Vector2(cellule) - centre) / rayon).length() + bruit
		if contour < 0.98:
			var niveau := 1.0 if contour < 0.52 else 0.50 + (1.0 - contour) * 0.45
			hauteur = maxi(hauteur, roundi(mesa[2] * niveau / 16.0) * 16)
	return hauteur

func _est_sol(couleur: Color) -> bool:
	return couleur != COULEUR_MER and couleur != OBSTACLE

func _bloquer_bords_de_terrasse(carte: Image, cellule: Vector2i, altitude: int, contour: PackedVector2Array) -> void:
	var centre := _projeter(cellule, altitude)
	for index in VOISINES.size():
		var voisine: Vector3i = _carreaux.get(cellule + VOISINES[index], Vector3i(NIVEAU_MER, 0, 0))
		if altitude <= voisine.x:
			continue
		var debut := contour[index]
		var fin := contour[(index + 1) % 4]
		_peindre_carte(carte, PackedVector2Array([debut, fin, fin.lerp(centre, 0.44), debut.lerp(centre, 0.44)]), OBSTACLE)

func _bloquer_emprise(carte: Image, decor: Node2D) -> void:
	var emprise: Vector2 = decor.get_meta("emprise")
	var centre := decor.position
	var dx := Vector2(emprise.x, emprise.x * 0.5)
	var dy := Vector2(-emprise.y, emprise.y * 0.5)
	_peindre_carte(carte, PackedVector2Array([centre - dx - dy, centre + dx - dy, centre + dx + dy, centre - dx + dy]), OBSTACLE)

func _garder_sol_accessible(carte: Image, depart: Vector2) -> void:
	var taille := carte.get_size()
	var visite := PackedByteArray()
	visite.resize(taille.x * taille.y)
	var origine_case := Vector2i(depart / PAS_NAVIGATION)
	if not _est_sol(carte.get_pixelv(origine_case)):
		return
	var file: Array[Vector2i] = [origine_case]
	var index := 0
	visite[origine_case.y * taille.x + origine_case.x] = 1
	while index < file.size():
		var case_sol := file[index]
		index += 1
		for direction: Vector2i in VOISINES:
			var voisine := case_sol + direction
			if voisine.x < 0 or voisine.y < 0 or voisine.x >= taille.x or voisine.y >= taille.y:
				continue
			var adresse := voisine.y * taille.x + voisine.x
			if visite[adresse] == 0 and _est_sol(carte.get_pixelv(voisine)):
				visite[adresse] = 1
				file.append(voisine)
	for y in taille.y:
		for x in taille.x:
			if visite[y * taille.x + x] == 0 and _est_sol(carte.get_pixel(x, y)):
				carte.set_pixel(x, y, OBSTACLE)

func _polygone_liaison(liaison: Array, recouvrement: float = 0.0) -> PackedVector2Array:
	var bords := _extremites(liaison, liaison[4], recouvrement)
	return PackedVector2Array([bords[0], bords[1], bords[3], bords[2]])

# L'accès commence sur le palier. La première marche part de l'arête
# commune à la dernière dalle haute et à sa voisine en contrebas.
func _volee_escalier(liaison: Array) -> Array:
	var depart: Vector2 = liaison[0]
	var pied: Vector2 = liaison[2]
	var axe := (pied - depart).normalized()
	var cellule := Vector2i((depart + Vector2(0.5, 0.5)).floor())
	while _carreaux.has(cellule) and _carreaux[cellule].x == liaison[1]:
		var distance_bord := (Vector2(cellule) - depart).dot(axe) + 0.5
		if distance_bord >= depart.distance_to(pied):
			break
		cellule += Vector2i(axe.sign())
		if _carreaux.has(cellule) and _carreaux[cellule].x < liaison[1]:
			return [depart + axe * distance_bord, liaison[1], pied, liaison[3], liaison[4]]
	return liaison

func _peindre_escalier(carte: Image, liaison: Array) -> void:
	var volee := _volee_escalier(liaison)
	var bords := _extremites(volee, volee[4])
	var support := bords[1] + Vector2.DOWN * (float(volee[1]) - float(volee[3]))
	_peindre_carte(carte, PackedVector2Array([bords[1], bords[3], support]), OBSTACLE)
	if volee[0] != liaison[0]:
		var palier := [liaison[0], liaison[1], volee[0], liaison[1], liaison[4]]
		_peindre_carte(carte, _polygone_liaison(palier, 14.0), COULEURS_SOL[Sol.DALLAGE])
	_peindre_carte(carte, _polygone_liaison(volee, 14.0), COULEURS_SOL[Sol.DALLAGE])

func _face(cellule: Vector2i, altitude: int, contour: PackedVector2Array, index: int) -> PackedVector2Array:
	var voisine: Vector3i = _carreaux.get(cellule + VOISINES[index], Vector3i(NIVEAU_MER, 0, 0))
	if altitude <= voisine.x:
		return PackedVector2Array()
	var debut := contour[index]
	var fin := contour[index + 1]
	var descente := Vector2(0, altitude - voisine.x)
	return PackedVector2Array([debut, fin, fin + descente, debut + descente])

func _draw() -> void:
	for cellule in _ordre:
		var dalle := _carreaux[cellule]
		var contour := _contour_dalle(_projeter(cellule, dalle.x))
		for direction in [1, 2]:
			var face := _face(cellule, dalle.x, contour, direction)
			if not face.is_empty():
				_dessiner_paroi(face, direction, dalle.z == Relief.VILLE, dalle.x)
		_dessiner_dalle(cellule, dalle, contour)
	for escalier in escaliers:
		_dessiner_escalier(escalier)

func _dessiner_dalle(cellule: Vector2i, dalle: Vector3i, contour: PackedVector2Array) -> void:
	var echelle := 0.29 if dalle.y == Sol.SABLE else 1.0
	var debut := Vector2(cellule) * echelle
	var teinte := Color.WHITE.lightened(0.035) if dalle.z == Relief.MESA else Color.WHITE
	draw_polygon(contour, PackedColorArray([teinte]), PackedVector2Array([
		debut, debut + Vector2(echelle, 0), debut + Vector2.ONE * echelle, debut + Vector2(0, echelle),
	]), TEXTURES[dalle.y])

func _dessiner_paroi(face: PackedVector2Array, cote: int, taille: bool, altitude: float) -> void:
	var texture := MUR_CALCAIRE if taille else ROCHE_ROUGE
	var motif := texture.get_size()
	var haut_a := Vector2(face[0].x, -altitude) / motif
	var haut_b := Vector2(face[1].x, -altitude) / motif
	var profondeur := Vector2.DOWN * (face[2].y - face[1].y) / motif.y
	var teinte := Color("#d0b48d") if cote == 1 else Color("#ecd2a6")
	var uv := PackedVector2Array([haut_a, haut_b, haut_b + profondeur, haut_a + profondeur])
	draw_polygon(face, PackedColorArray([teinte, teinte, teinte.darkened(0.18), teinte.darkened(0.18)]), uv, texture)

func _dessiner_escalier(liaison: Array) -> void:
	var volee := _volee_escalier(liaison)
	var depart: Vector2 = volee[0]
	var pied: Vector2 = volee[2]
	var denivele := float(volee[1]) - float(volee[3])
	var nombre := maxi(2, roundi(denivele / 7.0))
	var hauteur := denivele / nombre
	var selon_u := not is_equal_approx(depart.x, pied.x)
	var travers := (Vector2.DOWN if selon_u else Vector2.RIGHT) * float(volee[4])
	var vers_avant := (pied - depart).dot(Vector2.ONE) > 0.0
	var ordre := range(nombre) if vers_avant else range(nombre - 1, -1, -1)
	for index: int in ordre:
		var debut := depart.lerp(pied, float(index) / nombre)
		var fin := depart.lerp(pied, float(index + 1) / nombre)
		var altitude := float(volee[1]) - index * hauteur
		var coins := PackedVector2Array([debut - travers, debut + travers, fin + travers, fin - travers])
		var dessus := PackedVector2Array()
		var uv := PackedVector2Array()
		for coin in coins:
			dessus.append(_projeter(coin, altitude))
			uv.append(coin + Vector2(0.5, 0.5))
		var assise := Vector2.DOWN * (altitude - float(volee[3]))
		var flanc := PackedVector2Array([dessus[1], dessus[2], dessus[2] + assise, dessus[1] + assise])
		_dessiner_paroi(flanc, 2 if selon_u else 1, true, altitude)
		if vers_avant:
			var levee := Vector2.DOWN * hauteur
			var face := PackedVector2Array([dessus[2], dessus[3], dessus[3] + levee, dessus[2] + levee])
			_dessiner_paroi(face, 1 if selon_u else 2, true, altitude)
		draw_polygon(dessus, PackedColorArray([Color.WHITE]), uv, DALLAGE)
		draw_line(dessus[2], dessus[3], Color("#ffdfad"), 1.5)

func _creer_mer() -> void:
	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.size = taille_monde
	fond.z_index = -2
	var materiau := ShaderMaterial.new()
	materiau.shader = SHADER_MER
	materiau.set_shader_parameter("mer", MER)
	materiau.set_shader_parameter("dimensions", taille_monde)
	materiau.set_shader_parameter("origine", origine - Vector2(0, DEMI_TUILE.y))
	fond.material = materiau
	add_child(fond)

	var rive := Node2D.new()
	rive.z_index = -1
	add_child(rive)
	var animations := EAUX.animations_ecume()
	var cadre := Rect2(Vector2.ZERO, taille_monde).grow(100.0)
	for cellule in _ordre:
		var dalle := _carreaux[cellule]
		var contour := _contour_dalle(_projeter(cellule, dalle.x))
		for cote in [1, 2]:
			if _carreaux.has(cellule + VOISINES[cote]):
				continue
			var descente := Vector2(0, dalle.x - NIVEAU_MER)
			var debut := contour[cote] + descente
			var fin := contour[cote + 1] + descente
			if cadre.has_point(debut) or cadre.has_point(fin):
				EAUX.ajouter_ecume(rive, debut, fin, animations[cote - 1])
