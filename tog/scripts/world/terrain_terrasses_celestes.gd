@tool
extends "res://scripts/world/terrain_zone.gd"

const ASSETS := "res://assets/world/skypiea/ville/"
const PAVE := preload(ASSETS + "pave.png")
const PAVE_MOUSSE := preload(ASSETS + "pave_mousse.png")
const HERBE := preload(ASSETS + "herbe.png")
const BORD_HERBE := preload(ASSETS + "bord_herbe.png")
const PLANCHES := preload(ASSETS + "planches.png")
const BOIS := preload(ASSETS + "bois.png")
const GRES := preload(ASSETS + "gres.png")
const FALAISE := preload(ASSETS + "falaise.png")
const ROCHE := preload("res://assets/world/skypiea/terrasses/parement.png")

const DEMI_TUILE := Vector2(64, 32)
const PAS_NAVIGATION := 16
const DEMI_DIAMANT := [Vector2(0, -32), Vector2(64, 0), Vector2(0, 32), Vector2(-64, 0)]
const FACES_AVANT := [Vector2i.RIGHT, Vector2i.DOWN]
const UV_QUAD := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
const CIEL := Color("#4f8ece")
const OBSTACLE := Color("#9a7e60")
const DEMI_LIAISON := 1.37

var origine := Vector2.ZERO
var taille_monde := Vector2.ZERO
var terrasses: Array = []
var liaisons: Array = []
var couleurs_bloquees: Array[Color] = [CIEL, OBSTACLE]
var _dalles: Dictionary[Vector2i, int] = {}

func dimensions_monde() -> Vector2:
	return taille_monde

func _ready() -> void:
	if _dalles.is_empty():
		_preparer_dalles()
	queue_redraw()

func preparer(sol: TileMapLayer, _falaises: TileMapLayer, paysage: Node2D) -> void:
	_preparer_dalles()
	sol.scale = Vector2.ONE * (float(PAS_NAVIGATION) / TAILLE_CASE)
	var taille := Vector2i(taille_monde / PAS_NAVIGATION)
	var carte := Image.create_empty(taille.x, taille.y, false, Image.FORMAT_RGB8)
	carte.fill(CIEL)
	for cellule in _dalles:
		var secteur := _dalles[cellule]
		var centre := _projeter(cellule, terrasses[secteur][1])
		_peindre_carte(carte, _contour_dalle(centre), terrasses[secteur][3])
	_peindre_eau_carte(carte)
	for liaison in liaisons:
		var bords := _extremites(liaison, DEMI_LIAISON - 0.20, 12.0)
		_peindre_carte(carte, PackedVector2Array([bords[0], bords[1], bords[3], bords[2]]),
			Color("#be9055") if liaison[4] else Color("#e7cda0"))
	for decor in paysage.get_children():
		if not decor.has_meta("emprise"):
			continue
		var emprise: Vector2 = decor.get_meta("emprise")
		var centre: Vector2 = decor.position
		var dx := Vector2(emprise.x, emprise.x * 0.5)
		var dy := Vector2(-emprise.y, emprise.y * 0.5)
		_peindre_carte(carte, PackedVector2Array([
			centre - dx - dy, centre + dx - dy, centre + dx + dy, centre - dx + dy,
		]), OBSTACLE)
	_filtrer_cases_isolees(carte)
	for y in taille.y:
		for x in taille.x:
			var couleur := carte.get_pixel(x, y)
			if couleur not in couleurs_bloquees:
				sol.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	apercu = ImageTexture.create_from_image(carte)
	queue_redraw()

func _preparer_dalles() -> void:
	_dalles.clear()
	for secteur in terrasses.size():
		var zone: Rect2i = terrasses[secteur][0]
		for y in range(zone.position.y, zone.end.y):
			for x in range(zone.position.x, zone.end.x):
				var marge := Vector2i(x, y) - zone.position
				var coins := marge.min(zone.size - Vector2i.ONE - marge)
				if not _est_quai(secteur) and coins.x + coins.y < 2:
					continue
				_dalles[Vector2i(x, y)] = secteur

func _projeter(cellule: Vector2, altitude: float) -> Vector2:
	var decalage := Vector2(cellule.x - cellule.y, cellule.x + cellule.y) * DEMI_TUILE
	return origine + decalage - Vector2(0, altitude)

func _contour_dalle(centre: Vector2) -> PackedVector2Array:
	var contour := PackedVector2Array()
	for sommet: Vector2 in DEMI_DIAMANT:
		contour.append(centre + sommet)
	return contour

func _peindre_carte(carte: Image, contour: PackedVector2Array, couleur: Color) -> void:
	var cadre := Rect2(contour[0], Vector2.ZERO)
	for sommet in contour:
		cadre = cadre.expand(sommet)
	var debut := Vector2i(floor(cadre.position / PAS_NAVIGATION)).max(Vector2i.ZERO)
	var fin := Vector2i(ceil(cadre.end / PAS_NAVIGATION)).min(carte.get_size())
	for y in range(debut.y, fin.y):
		for x in range(debut.x, fin.x):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) * PAS_NAVIGATION
			if Geometry2D.is_point_in_polygon(point, contour):
				carte.set_pixel(x, y, couleur)

func _extremites(liaison: Array, demi_largeur: float, recouvrement: float = 0.0) -> PackedVector2Array:
	var depart: Vector2 = liaison[0]
	var arrivee: Vector2 = liaison[2]
	var axe := Vector2.RIGHT if is_equal_approx(depart.x, arrivee.x) else Vector2.DOWN
	var bord := Vector2(axe.x - axe.y, 1) * DEMI_TUILE * demi_largeur
	var haut := _projeter(depart, liaison[1])
	var bas := _projeter(arrivee, liaison[3])
	var marge := (bas - haut).normalized() * recouvrement
	return PackedVector2Array([haut - marge - bord, haut - marge + bord, bas + marge - bord, bas + marge + bord])

func _draw() -> void:
	_dessiner_terrasses()
	_dessiner_liaisons(self)

func _peindre_eau_carte(_carte: Image) -> void:
	pass

func _filtrer_cases_isolees(_carte: Image) -> void:
	pass

func _est_quai(secteur: int) -> bool:
	return terrasses[secteur][2] == 0

func _dessiner_terrasses() -> void:
	for secteur in terrasses.size():
		for cellule in _dalles:
			if _dalles[cellule] == secteur:
				_dessiner_falaise(cellule, secteur)
		for cellule in _dalles:
			if _dalles[cellule] == secteur:
				_dessiner_sol(cellule, secteur)

func _dessiner_liaisons(calque: Node2D) -> void:
	for liaison in liaisons:
		_dessiner_liaison(calque, liaison)

func _dessiner_falaise(cellule: Vector2i, secteur: int) -> void:
	var hauteur: int = terrasses[secteur][1]
	var centre := _projeter(cellule, hauteur)
	for index in FACES_AVANT.size():
		var autre: int = _dalles.get(cellule + FACES_AVANT[index], -1)
		if autre >= 0 and terrasses[autre][1] == hauteur:
			continue
		var debut: Vector2 = centre + DEMI_DIAMANT[index + 1]
		var fin: Vector2 = centre + DEMI_DIAMANT[index + 2]
		if _est_quai(secteur):
			_dessiner_rive_quai(debut, fin, posmod(cellule.x + cellule.y, 2) == 0)
			continue
		var profondeur: float = terrasses[secteur][2]
		var pied_a := debut + Vector2(0, profondeur + sin(debut.x * 0.038) * 19.0)
		var pied_b := fin + Vector2(0, profondeur + sin(fin.x * 0.038) * 19.0)
		var ombre := Color("#9caac5") if index else Color("#ced4e0")
		_dessiner_parement(debut, fin, pied_a, pied_b, ombre, profondeur)

func _dessiner_parement(debut: Vector2, fin: Vector2, pied_a: Vector2, pied_b: Vector2,
		lumiere: Color, profondeur: float) -> void:
	var rebord := Vector2(0, 57)
	var haut_a := debut + rebord
	var haut_b := fin + rebord
	var ombre := Color("#6d88b2")
	_quad(self, PackedVector2Array([debut, fin, haut_b, haut_a]), FALAISE,
		lumiere, lumiere.lerp(ombre, 0.21))
	var bandes := ceili((profondeur - rebord.y) / 64.0)
	for bande in bandes:
		var t := float(bande) / bandes
		var u := float(bande + 1) / bandes
		var contour := PackedVector2Array([
			haut_a.lerp(pied_a, t), haut_b.lerp(pied_b, t),
			haut_b.lerp(pied_b, u), haut_a.lerp(pied_a, u),
		])
		_quad(self, contour, ROCHE, lumiere.lerp(ombre, 0.21 + t * 0.79),
			lumiere.lerp(ombre, 0.21 + u * 0.79))

func _dessiner_rive_quai(debut: Vector2, fin: Vector2, pilier: bool) -> void:
	if pilier:
		var tete := (debut + fin) * 0.5 + Vector2(0, 4)
		var pied := tete + Vector2(0, 86)
		draw_line(tete, pied, Color("#67482e"), 18.0)
		draw_line(tete - Vector2(4, 0), pied - Vector2(4, 0), Color("#b98147"), 7.0)
		draw_line(pied - Vector2(0, 12), pied, Color("#8d9cb1"), 19.0)
	var epaisseur := Vector2(0, 16)
	_quad(self, PackedVector2Array([debut, fin, fin + epaisseur, debut + epaisseur]), BOIS,
		Color("#e3af64"), Color("#87542e"))

func _dessiner_sol(cellule: Vector2i, secteur: int) -> void:
	var centre := _projeter(cellule, terrasses[secteur][1])
	var dalle := _texture_sol(cellule, secteur)
	draw_colored_polygon(_contour_dalle(centre), terrasses[secteur][3])
	draw_texture(dalle, centre - DEMI_TUILE)

func _texture_sol(_cellule: Vector2i, secteur: int) -> Texture2D:
	return PLANCHES if _est_quai(secteur) else PAVE

func _dessiner_liaison(calque: Node2D, liaison: Array, demi_largeur := DEMI_LIAISON) -> void:
	var bords := _extremites(liaison, demi_largeur)
	var bois: bool = liaison[4]
	var nombre := maxi(5, roundi(bords[0].distance_to(bords[2]) / (15.0 if bois else 26.0)))
	var texture := BOIS if bois else GRES
	var recul := Vector2(0, 0 if bois else 6.0)
	if bois:
		var sous_face := Vector2(0, 10)
		_quad(calque, PackedVector2Array([bords[0], bords[2], bords[2] + sous_face, bords[0] + sous_face]),
			BOIS, Color("#ab743b"), Color("#6d523c"))
		_quad(calque, PackedVector2Array([bords[1], bords[3], bords[3] + sous_face, bords[1] + sous_face]),
			BOIS, Color("#ab743b"), Color("#6d523c"))
	for index in range(nombre - 1, -1, -1):
		var t := float(index) / nombre
		var suivant := float(index + 1) / nombre
		var a := bords[0].lerp(bords[2], t)
		var b := bords[1].lerp(bords[3], t)
		var c := bords[1].lerp(bords[3], suivant)
		var d := bords[0].lerp(bords[2], suivant)
		var teinte := Color.WHITE.lerp(Color("#dcbb86"), (index % 3) * 0.13)
		# Les contremarches restent visibles sur la face en aval.
		if not bois:
			_quad(calque, PackedVector2Array([d - recul, c - recul, c, d]), GRES,
				Color("#b7a591"), Color("#887665"))
		_quad(calque, PackedVector2Array([a, b, c - recul, d - recul]), texture, teinte, teinte)
		calque.draw_line(d - recul, c - recul, Color("#f9dfb7") if not bois else Color("#9c632b"), 2.0)
	for cote in 2:
		_dessiner_garde_corps(calque, bords[cote], bords[cote + 2], bois)

func _dessiner_garde_corps(calque: Node2D, debut: Vector2, fin: Vector2, bois: bool) -> void:
	var nombre := maxi(2, ceili(debut.distance_to(fin) / 68.0))
	var hauteur := Vector2(0, 22 if bois else 16)
	var corde := PackedVector2Array()
	for index in range(nombre * 8 + 1):
		var t := float(index) / (nombre * 8)
		var base := debut.lerp(fin, t) - hauteur
		corde.append(base + Vector2(0, sin(fmod(t * nombre, 1.0) * PI) * (7.0 if bois else 0.0)))
	calque.draw_polyline(corde, Color("#856038") if bois else Color("#9c9076"), 6.0, true)
	calque.draw_polyline(corde, Color("#e3ba68") if bois else Color("#e7d7b2"), 2.0, true)
	for index in range(nombre + 1):
		var base := debut.lerp(fin, float(index) / nombre)
		calque.draw_line(base, base - hauteur, Color("#91612e") if bois else Color("#9c9177"), 10.0)
		calque.draw_line(base - hauteur * 0.12 - Vector2(2, 0), base - hauteur - Vector2(2, 0),
			Color("#edc66f") if bois else Color("#e5d7b7"), 3.0)
		calque.draw_circle(base - hauteur, 5.0, Color("#e8b95b") if bois else Color("#ebe1ca"))

func _quad(calque: Node2D, contour: PackedVector2Array, texture: Texture2D, clair: Color, sombre: Color) -> void:
	calque.draw_polygon(contour, PackedColorArray([clair, clair, sombre, sombre]), UV_QUAD, texture)
