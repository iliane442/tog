extends Node2D

const CASE := 64
const DIMENSIONS := Vector2i(43, 18)
const PONT: Array[Rect2i] = [Rect2i(6, 3, 2, 2), Rect2i(5, 5, 4, 7)]
const COULOIR := Rect2i(22, 8, 16, 2)
const ECHELLE := Vector2i(29, 8)
const GALIONS := preload("res://scripts/world/ponts_galions.gd")
const FINITIONS := preload("res://scripts/world/finitions_pont.gd")
const PROJECTION_PONT := Transform2D(Vector2(0.82, 0.41), Vector2(-0.82, 0.41), Vector2(832, 96))
const PROJECTION_GALION := Transform2D(Vector2(0.82, 0.41), Vector2(0.82, -0.41), Vector2(-1216, 940))
const PROJECTION_INTERIEUR := Transform2D(Vector2(0.82, 0.41), Vector2(-0.82, 0.41), Vector2(1456, -560))
const HAUTEUR_PONT_GALION := 112.0
const POINTS_PONT_PERSONNEL := {
	"depart": Vector2i(8, 10), "quai": Vector2i(8, 11), "trappe": Vector2i(7, 7), "barre": Vector2i(6, 8),
}
const MATS_PERSONNELS := {
	"lanterne": {Vector2i(7, 6): 166.0},
	"brigantin": {Vector2i(7, 5): 146.0, Vector2i(7, 9): 182.0},
	"grand_large": {Vector2i(7, 4): 145.0, Vector2i(7, 6): 210.0, Vector2i(7, 9): 156.0},
}
const HAUTEURS_MATS_GALION := [0.42, 0.53]
const PIECES := {
	"atelier": {"salle": Rect2i(22, 3, 7, 4), "porte": Vector2i(25, 7), "seuil": Vector2i(25, 8), "poste": Vector2i(25, 5)},
	"cale": {"salle": Rect2i(31, 3, 7, 4), "porte": Vector2i(34, 7), "seuil": Vector2i(34, 8), "poste": Vector2i(34, 5)},
	"cabine": {"salle": Rect2i(22, 11, 7, 4), "porte": Vector2i(25, 10), "seuil": Vector2i(25, 9), "poste": Vector2i(25, 13)},
	"cartes": {"salle": Rect2i(31, 11, 7, 4), "porte": Vector2i(34, 10), "seuil": Vector2i(34, 9), "poste": Vector2i(34, 13)},
}
const MEUBLES := {
	"atelier": {"etabli": Rect2i(2, 0, 3, 1), "tonneaux": Rect2i(0, 1, 1, 1), "caisses": Rect2i(6, 0, 1, 1)},
	"cale": {"coffre": Rect2i(3, 0, 1, 1), "tonneaux": Rect2i(0, 0, 1, 1), "caisses": Rect2i(6, 0, 1, 1)},
	"cabine": {"bureau": Rect2i(2, 3, 3, 1), "bibliotheque": Rect2i(0, 0, 1, 1)},
	"cartes": {"table_cartes": Rect2i(2, 3, 3, 1), "coffre": Rect2i(0, 0, 1, 1)},
	"chambre": {"lit": Rect2i(0, 0, 2, 2), "meuble_chambre": Rect2i(5, 0, 2, 1)},
}
const TONNEAUX := preload("res://assets/world/world-pixellab-decors-v1-tempere-tonneaux.png")
const CAISSES := preload("res://assets/world/world-pixellab-decors-v1-tempere-caisses-empilees.png")
const COFFRE := preload("res://assets/world/world-pixellab-decors-v1-tempere-coffre-de-marin.png")
const TROPHEE := preload("res://assets/items/081_trophee_de_capitaine_pirate.png")
const BOUSSOLE := preload("res://assets/items/073_boussole_de_grand_line_instable.png")
const ACCESSOIRES_ATELIER := {
	"blacksmith": preload("res://assets/items/844_lingot_allie_de_l_ile_foudre.png"),
	"cook": preload("res://assets/items/093_soupe_chaude_de_drum.png"),
	"medic": preload("res://assets/items/potion_de_force.png"),
}
const BOIS_ATELIER := preload("res://assets/items/218_bois_flotte.png")
const SHADER_MER := preload("res://assets/shaders/mer_alabasta.gdshader")
const EAU := preload("res://assets/world/alabasta/terrain/mer.png")

var apercu: Texture2D
var sous_le_pont := false
var _sol: TileMapLayer
var _plan_pont: Dictionary = {}
var _rangees_pont: Array[Rect2i] = []
var _escaliers: Array[Rect2i] = []
var _mobilier_pont: Dictionary = {}
var _mats: Dictionary = {}
var _mer: ColorRect

static func projection_etage(interieur: bool, galion := false) -> Transform2D:
	if interieur:
		return PROJECTION_INTERIEUR
	return PROJECTION_GALION if galion else PROJECTION_PONT

func hauteur_pont(y: float) -> float:
	var hauteur := 0.0
	for escalier in _escaliers:
		hauteur += HAUTEUR_PONT_GALION * clampf(inverse_lerp(escalier.position.y * CASE, escalier.end.y * CASE, y), 0.0, 1.0)
	return hauteur

func position_monde(plan: Vector2) -> Vector2:
	var hauteur := 0.0 if sous_le_pont else hauteur_pont(plan.y)
	return projection_etage(sous_le_pont, est_galion()) * plan + Vector2.UP * hauteur

func position_plan(monde: Vector2, interieur: bool) -> Vector2:
	var plan := projection_etage(interieur, est_galion()).affine_inverse() * monde
	if interieur or not est_galion():
		return plan
	# Avec la poupe vers le fond, la pente des marches allonge l'axe Y projeté.
	# Chaque rampe se retranche en inversant son segment dans le plan aplati.
	var pente := PROJECTION_GALION.x.y - PROJECTION_GALION.y.y
	var rampe := HAUTEUR_PONT_GALION / pente
	var retrait := 0.0
	for escalier in _escaliers:
		var debut := escalier.position.y * CASE + retrait
		var fin := escalier.end.y * CASE + retrait + rampe
		var progression := clampf(inverse_lerp(debut, fin, plan.y), 0.0, 1.0)
		retrait += rampe * progression
		if progression < 1.0:
			break
	return plan + Vector2(retrait, -retrait)

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mer = ColorRect.new()
	_mer.position = Vector2(-1600, -1300)
	_mer.size = Vector2(5400, 4500)
	_mer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mer.show_behind_parent = true
	var reflet := ShaderMaterial.new()
	reflet.shader = SHADER_MER
	reflet.set_shader_parameter("mer", EAU)
	reflet.set_shader_parameter("dimensions", _mer.size)
	reflet.set_shader_parameter("origine", -_mer.position)
	_mer.material = reflet
	add_child(_mer)
	_actualiser_mer()

func est_galion() -> bool:
	return not _plan_pont.is_empty()

func point_pont(id: String) -> Vector2i:
	if est_galion() and id == "barre":
		return Vector2i(GALIONS.AXE, _rangees_pont.back().end.y - 2)
	return _plan_pont[id] if est_galion() else POINTS_PONT_PERSONNEL[id]

func couloir() -> Rect2i:
	return Rect2i(22, 8, 88, 2) if Navires.modele_a_bord() == "vie" else COULOIR

func pieces_bord() -> Dictionary:
	var modele := Navires.modele_a_bord()
	match modele:
		"ateliers":
			return {"atelier": PIECES["atelier"], "cale": PIECES["cale"], "cabine": PIECES["cabine"]}
		"stockage":
			return {"cale": PIECES["cale"]}
		"navigation":
			return {"atelier": PIECES["atelier"]}
		"vie":
			var indice := Navires.indice_chambre()
			var x := 22 + (indice % 10) * 9
			var y := 3 if indice < 10 else 11
			return {"chambre": {"salle": Rect2i(x, y, 7, 4), "porte": Vector2i(x + 3, 7 if indice < 10 else 10),
				"seuil": Vector2i(x + 3, 8 if indice < 10 else 9), "poste": Vector2i(x + 3, y + 2)}}
	var pieces := {}
	if Navires.est_pilote():
		for id in Personnage.pieces_possibles_navire():
			pieces[id] = PIECES[id]
	return pieces

func indice_atelier(id: String) -> int:
	return ["atelier", "cale", "cabine"].find(id)

func metier_atelier(id: String) -> String:
	var ateliers: Dictionary = Navires.donnees_a_bord().get("ateliers", {})
	return str(ateliers.get(str(indice_atelier(id)), ""))

func est_ouverte(id: String) -> bool:
	match Navires.modele_a_bord():
		"ateliers":
			return Navires.peut_utiliser_galion() and metier_atelier(id) != ""
		"stockage", "navigation", "vie":
			return Navires.peut_utiliser_galion()
	return Navires.est_pilote() and id in Personnage.pieces_navire_ouvertes

func dimensions_monde() -> Vector2:
	var hauteur: int = GALIONS.PROUE + _rangees_pont.size() + 2 if est_galion() else DIMENSIONS.y
	return Vector2(maxi(DIMENSIONS.x, couloir().end.x + 2), hauteur) * CASE

func cadre_interieur() -> Rect2:
	var plan := couloir()
	for piece: Dictionary in pieces_bord().values():
		plan = plan.merge(piece["salle"])
	var coins := _coins(Rect2(plan.position * CASE, plan.size * CASE))
	var cadre := Rect2(PROJECTION_INTERIEUR * coins[0], Vector2.ZERO)
	for coin in coins:
		cadre = cadre.expand(PROJECTION_INTERIEUR * coin)
	return cadre.grow(240.0)

func cadre_galion() -> Rect2:
	var contour := _contour_pont()
	var cadre := Rect2(position_monde(contour[0]), Vector2.ZERO)
	for point in contour:
		cadre = cadre.expand(position_monde(point))
		cadre = cadre.expand(PROJECTION_GALION * point + Vector2.DOWN * 102)
	for cellule: Vector2i in _mats:
		cadre = cadre.expand(position_monde(_centre(cellule)) + Vector2.UP * (float(_mats[cellule]) + 25.0))
	return cadre.grow(102.0)

func preparer(sol: TileMapLayer, _falaises: TileMapLayer, _paysage: Node2D) -> void:
	_sol = sol
	actualiser_pieces()

func actualiser_pieces() -> void:
	var modele := Navires.modele_a_bord()
	_plan_pont = GALIONS.PLANS.get(modele, {})
	_rangees_pont.clear()
	_escaliers.clear()
	_mobilier_pont.clear()
	_mats.clear()
	if est_galion():
		_rangees_pont = GALIONS.rangees(_plan_pont)
		_escaliers = GALIONS.escaliers(_plan_pont)
		_mobilier_pont = _plan_pont["mobilier"].duplicate(true)
		var cellules: Array = _mobilier_pont["mat"]
		var longueur := _rangees_pont.size() * CASE
		for i in cellules.size():
			_mats[cellules[i]] = longueur * HAUTEURS_MATS_GALION[i]
		var limite: int = _rangees_pont.back().position.x
		var milieu := _escaliers[0].end.y + 1
		_mobilier_pont["banc"] = [Vector2i(limite + 1, milieu), Vector2i(limite + 1, milieu + 1)]
		_mobilier_pont["table_pont"] = [Vector2i(limite + 4, milieu + 1)]
		var barre := point_pont("barre")
		_mobilier_pont["table_cartes"] = [barre + Vector2i(-3, 0)]
		var lanternes: Array = _mobilier_pont.get("lanterne", [])
		lanternes.append_array([Vector2i(limite, milieu), Vector2i(limite, barre.y),
			Vector2i(GALIONS.AXE * 2 - limite, barre.y)])
		_mobilier_pont["lanterne"] = lanternes
	else:
		_mats = MATS_PERSONNELS.get(modele, MATS_PERSONNELS["lanterne"]).duplicate()
		for zone in PONT:
			for y in range(zone.position.y, zone.end.y):
				_rangees_pont.append(Rect2i(zone.position.x, y, zone.size.x, 1))
	_sol.clear()
	for rectangle in _rangees_pont:
		var surface := rectangle
		for escalier in _escaliers:
			if rectangle.position.y >= escalier.position.y and rectangle.position.y < escalier.end.y:
				surface = rectangle.intersection(escalier)
		_ouvrir_sol(surface)
	if est_galion():
		for groupe: Array in _mobilier_pont.values():
			for case_sol: Vector2i in groupe:
				_sol.erase_cell(case_sol)
	else:
		for cellule: Vector2i in _mats:
			_sol.erase_cell(cellule)
	var arrivee := get_parent().get_node("Arrivees/DepuisQuai") as Marker2D
	arrivee.position = _sol.map_to_local(point_pont("depart"))
	_ouvrir_sol(couloir())
	var pieces := pieces_bord()
	for id in pieces:
		if not est_ouverte(id):
			continue
		var piece: Dictionary = pieces[id]
		_ouvrir_sol(piece["salle"])
		_sol.set_cell(piece["porte"], 0, Vector2i.ZERO)
		for zone: Rect2i in _mobilier_plan(id, piece["salle"]).values():
			for y in range(zone.position.y, zone.end.y):
				for x in range(zone.position.x, zone.end.x):
					_sol.erase_cell(Vector2i(x, y))
	var dimensions := Vector2i(dimensions_monde() / CASE)
	var image := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGB8)
	image.fill(Color("#183546"))
	for case_sol in _sol.get_used_cells():
		var teinte := hauteur_pont(_sol.map_to_local(case_sol).y) if case_sol.x < COULOIR.position.x else 0.0
		image.set_pixelv(case_sol, Color("#bc8a59").lightened(teinte / (HAUTEUR_PONT_GALION * 5.0)))
	if apercu == null or Vector2i(apercu.get_size()) != dimensions:
		apercu = ImageTexture.create_from_image(image)
	else:
		(apercu as ImageTexture).update(image)
	_actualiser_mer()
	queue_redraw()

func _ouvrir_sol(zone: Rect2i) -> void:
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			_sol.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)

func montrer_interieur(etat: bool) -> void:
	sous_le_pont = etat
	_actualiser_mer()
	queue_redraw()

func _actualiser_mer() -> void:
	if is_instance_valid(_mer):
		_mer.visible = not sous_le_pont

func _draw() -> void:
	if sous_le_pont:
		_dessiner_interieur()
	else:
		_dessiner_pont()

func _dessiner_pont() -> void:
	if _rangees_pont.is_empty():
		return
	var finition := Navires.finition_pont()
	var style := FINITIONS.fiche(finition)
	var texture := FINITIONS.texture(finition)
	var bordage: Color = style["bordage"]
	var moulure: Color = style["moulure"]
	var contour_plan := _contour_pont()
	var projection := projection_etage(false, est_galion())
	var contour := _projeter(contour_plan, Vector2.ZERO, 0.0)
	var centre := projection * _centre_coque()
	var profondeur := Vector2(0, 86 if est_galion() else 44)
	var fond := PackedVector2Array()
	var ombre := PackedVector2Array()
	for point in contour:
		var bas := point + profondeur - Vector2(0.0, (point.y - centre.y) * 0.04)
		fond.append(bas)
		ombre.append(bas + (point - centre) * 0.025 + Vector2(9, 9))
	draw_colored_polygon(ombre, Color("#0a2d43a0"))
	_dessiner_flancs(contour, fond, bordage)
	_surface_boisee(contour_plan, texture, Color.WHITE, 0.0)

	var liseret := contour.duplicate()
	liseret.append(liseret[0])
	draw_polyline(liseret, bordage.darkened(0.46), 11.0, true)
	draw_polyline(liseret, moulure, 3.0, true)

	var quai := _centre(point_pont("quai"))
	var sortie := _sortie_passerelle(contour_plan, quai)
	var longueur := sortie.x - quai.x + (51.0 if est_galion() else 41.0)
	var passerelle := Rect2(quai + Vector2(12, -19), Vector2(longueur, 38))
	_peindre_rect_plan(passerelle.grow(3.0), bordage.darkened(0.35))
	_surface_boisee(_coins(passerelle), texture, Color("#dfc199"))
	_dessiner_rambarde(contour, projection * sortie, bordage, moulure)
	if est_galion():
		_dessiner_ponts_superieurs(contour_plan, texture, bordage, moulure)

	_dessiner_trappe(_centre(point_pont("trappe")), texture, bordage, moulure)
	_dessiner_barre(position_monde(_centre(point_pont("barre"))), bordage, moulure)
	if est_galion():
		for element: String in _mobilier_pont:
			if element == "mat":
				continue
			for cellule: Vector2i in _mobilier_pont[element]:
				_dessiner_mobilier_galion(element, _centre(cellule), bordage, moulure)
	var ordre_mats := _mats.keys()
	ordre_mats.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return position_monde(_centre(a)).y < position_monde(_centre(b)).y)
	for cellule: Vector2i in ordre_mats:
		var bande := _rangees_pont[cellule.y - _rangees_pont[0].position.y]
		_dessiner_mat(_centre(cellule), _mats[cellule], bande, bordage, moulure)

func _dessiner_barre(barre: Vector2, bordage: Color, moulure: Color) -> void:
	var roue := barre + Vector2(0, -25)
	draw_line(roue, barre + Vector2(0, 8), bordage.darkened(0.21), 13.0)
	draw_arc(roue, 20.0, 0.0, TAU, 32, bordage.darkened(0.48), 7.0, true)
	draw_arc(roue, 19.0, 0.0, TAU, 32, moulure, 3.0, true)
	for i in range(8):
		var rayon := Vector2.from_angle(i * TAU / 8.0)
		draw_line(roue + rayon * 4.0, roue + rayon * 24.0, bordage.darkened(0.34), 5.0, true)
		draw_line(roue + rayon * 5.0, roue + rayon * 24.0, moulure, 2.0, true)
	draw_circle(roue, 6.0, moulure)

func _projeter(points: PackedVector2Array, decalage := Vector2.ZERO, hauteur_fixe := -1.0) -> PackedVector2Array:
	var projetes := PackedVector2Array()
	var projection := projection_etage(sous_le_pont, est_galion())
	for point in points:
		var position := projection * point + Vector2.UP * hauteur_fixe if hauteur_fixe >= 0.0 else position_monde(point)
		projetes.append(position + decalage)
	return projetes

func _surface_boisee(points: PackedVector2Array, texture: Texture2D, teinte: Color, hauteur_fixe := -1.0) -> void:
	var uv := PackedVector2Array()
	for point in points:
		uv.append(point / texture.get_size())
	draw_polygon(_projeter(points, Vector2.ZERO, hauteur_fixe), PackedColorArray([teinte]), uv, texture)

func _coins(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func _peindre_rect_plan(rect: Rect2, couleur: Color) -> void:
	draw_colored_polygon(_projeter(_coins(rect)), couleur)

func _dessiner_flancs(contour: PackedVector2Array, fond: PackedVector2Array, bois: Color) -> void:
	var teintes := PackedColorArray()
	for i in contour.size():
		var avant := contour[posmod(i - 1, contour.size())]
		var apres := contour[(i + 1) % contour.size()]
		var pente := (apres - avant).normalized().y
		teintes.append(bois.darkened(0.25 + pente * 0.13))
	for i in contour.size():
		var suivant := (i + 1) % contour.size()
		var a := contour[i]
		var b := contour[suivant]
		if b.x - a.x < 0.015:
			continue
		var bas_a := fond[i]
		var bas_b := fond[suivant]
		var gauche := teintes[i]
		var droite := teintes[suivant]
		draw_polygon(PackedVector2Array([a, b, bas_b, bas_a]),
			PackedColorArray([gauche, droite, droite.darkened(0.35), gauche.darkened(0.35)]))
		var sombre := gauche.lerp(droite, 0.5)
		for niveau in [0.24, 0.49, 0.74]:
			var debut := a.lerp(bas_a, niveau)
			var fin := b.lerp(bas_b, niveau)
			draw_line(debut, fin, sombre.darkened(0.36), 2.0, true)
			draw_line(debut + Vector2.DOWN * 2, fin + Vector2.DOWN * 2, sombre.lightened(0.10), 1.0, true)
		draw_line(bas_a, bas_b, sombre.darkened(0.48), 4.0, true)
		draw_line(bas_a + Vector2.DOWN * 4, bas_b + Vector2.DOWN * 4, Color("#ccedf188"), 2.0, true)

func _sortie_passerelle(contour: PackedVector2Array, quai: Vector2) -> Vector2:
	var bord := quai.x
	for i in contour.size():
		var a := contour[i]
		var b := contour[(i + 1) % contour.size()]
		if (a.y <= quai.y) == (b.y <= quai.y):
			continue
		bord = maxf(bord, lerpf(a.x, b.x, (quai.y - a.y) / (b.y - a.y)))
	return Vector2(bord, quai.y)

func _dessiner_rambarde(contour: PackedVector2Array, sortie: Vector2, bordage: Color, moulure: Color, ouverture := 25.0) -> void:
	var segment := 0
	var proche := INF
	for i in contour.size():
		var point := Geometry2D.get_closest_point_to_segment(sortie, contour[i], contour[(i + 1) % contour.size()])
		var distance := point.distance_squared_to(sortie)
		if distance < proche:
			segment = i
			proche = distance
	var chemin := Curve2D.new()
	chemin.add_point(sortie)
	for i in range(1, contour.size() + 1):
		chemin.add_point(contour[(segment + i) % contour.size()])
	chemin.add_point(sortie)
	var haut := Vector2.UP * 23
	var longueur := chemin.get_baked_length() - ouverture * 2.0
	var pas := ceili(longueur / 5.0)
	var rail := PackedVector2Array()
	for i in range(pas + 1):
		rail.append(chemin.sample_baked(ouverture + longueur * float(i) / pas) + haut)
	var poteaux := ceili(longueur / (82.0 if est_galion() else 64.0))
	for i in range(poteaux + 1):
		var a := chemin.sample_baked(ouverture + longueur * float(i) / poteaux)
		draw_line(a + Vector2.DOWN * 3, a + haut, bordage.darkened(0.40), 8.0)
		draw_line(a + Vector2.DOWN * 2, a + haut, bordage, 5.0)
	draw_polyline(rail, bordage.darkened(0.42), 10.0, true)
	draw_polyline(rail, bordage, 6.0, true)
	for i in rail.size():
		rail[i] += Vector2.UP * 2
	draw_polyline(rail, moulure, 2.0, true)

func _contour_apres(contour: PackedVector2Array, y: float) -> PackedVector2Array:
	var section := PackedVector2Array()
	for i in contour.size():
		var a := contour[i]
		var b := contour[(i + 1) % contour.size()]
		if a.y >= y:
			section.append(a)
		if (a.y < y and b.y > y) or (b.y < y and a.y > y):
			section.append(a.lerp(b, inverse_lerp(a.y, b.y, y)))
	return section

func _dessiner_ponts_superieurs(contour: PackedVector2Array, texture: Texture2D, bois: Color, moulure: Color) -> void:
	for i in _escaliers.size():
		var escalier := _escaliers[i]
		var bas := HAUTEUR_PONT_GALION * i
		var haut := bas + HAUTEUR_PONT_GALION
		var section := _contour_apres(contour, escalier.end.y * CASE)
		var socle := _projeter(section, Vector2.ZERO, bas)
		var plancher := _projeter(section, Vector2.ZERO, haut)
		for cote in section.size():
			var suivant := (cote + 1) % section.size()
			var a := socle[cote]
			var b := socle[suivant]
			if b.x - a.x > 0.015:
				_dessiner_cloison_poupe(a, b, bois, moulure)
		_surface_boisee(section, texture, Color("#e5cab0"), haut)
		var liseret := plancher.duplicate()
		liseret.append(liseret[0])
		draw_polyline(liseret, bois.darkened(0.46), 11.0, true)
		draw_polyline(liseret, moulure, 3.0, true)
		var haut_escalier := Vector2((escalier.position.x + escalier.size.x * 0.5) * CASE, escalier.end.y * CASE)
		var sortie := PROJECTION_GALION * haut_escalier + Vector2.UP * haut
		var demi_ouverture := escalier.size.x * CASE * PROJECTION_GALION.x.length() * 0.5
		_dessiner_rambarde(plancher, sortie, bois, moulure, demi_ouverture)
		_dessiner_escalier(_rect_monde(escalier), bas, texture, bois, moulure)

func _dessiner_cloison_poupe(a: Vector2, b: Vector2, bois: Color, moulure: Color) -> void:
	var levee := Vector2.UP * HAUTEUR_PONT_GALION
	var sombre := bois.darkened(0.24 - (b - a).normalized().y * 0.09)
	draw_polygon(PackedVector2Array([a, b, b + levee, a + levee]),
		PackedColorArray([sombre.darkened(0.44), sombre.darkened(0.44), sombre, sombre]))
	for i in range(1, 7):
		var ligne := levee * float(i) / 7.0
		draw_line(a + ligne, b + ligne, sombre.darkened(0.20), 2.0, true)
	var poteaux := floori(a.distance_to(b) / 114.0)
	for i in range(poteaux):
		var debut := a.lerp(b, float(i) / poteaux)
		var fenetre := a.lerp(b, (i + 0.5) / poteaux) + levee * 0.53
		draw_line(debut, debut + levee, sombre.darkened(0.52), 8.0)
		draw_line(debut + Vector2.RIGHT * 2.0, debut + levee + Vector2.RIGHT * 2.0, moulure.darkened(0.34), 2.0)
		_dessiner_hublot(fenetre, (b - a).normalized(), moulure)

func _dessiner_escalier(rect: Rect2, bas: float, texture: Texture2D, bois: Color, moulure: Color) -> void:
	var levee := Vector2.UP * HAUTEUR_PONT_GALION
	var base := Vector2.UP * bas
	for x in [rect.position.x, rect.end.x]:
		var pied := PROJECTION_GALION * Vector2(x, rect.position.y) + base
		var fond := PROJECTION_GALION * Vector2(x, rect.end.y) + base
		draw_colored_polygon(PackedVector2Array([pied, fond, fond + levee]), bois.darkened(0.38))
		draw_line(pied, fond + levee, moulure.darkened(0.24), 8.0)
	const MARCHES := 10
	var profondeur := rect.size.y / MARCHES
	for i in range(MARCHES - 1, -1, -1):
		var y := rect.position.y + profondeur * i
		var hauteur := bas + HAUTEUR_PONT_GALION * (i + 1) / MARCHES
		var pos := Vector2(rect.position.x, y)
		var gauche := PROJECTION_GALION * pos + Vector2.UP * hauteur
		var droite := PROJECTION_GALION * Vector2(rect.end.x, y) + Vector2.UP * hauteur
		var nez := Vector2.DOWN * (HAUTEUR_PONT_GALION / MARCHES)
		draw_colored_polygon(PackedVector2Array([gauche, droite, droite + nez, gauche + nez]), bois.darkened(0.32))
		_surface_boisee(_coins(Rect2(pos, Vector2(rect.size.x, profondeur))), texture, Color("#edd6b8"), hauteur)
		draw_line(gauche, droite, moulure, 2.5, true)
	for x in [rect.position.x, rect.end.x]:
		var a := PROJECTION_GALION * Vector2(x, rect.position.y) + base
		var b := PROJECTION_GALION * Vector2(x, rect.end.y) + base + levee
		var main_courante := Vector2.UP * 27.0
		for i in range(5):
			var poteau := a.lerp(b, i * 0.25)
			draw_line(poteau, poteau + main_courante, bois.darkened(0.22), 8.0)
			draw_circle(poteau + main_courante, 5.0, moulure)
		draw_line(a + main_courante, b + main_courante, bois.darkened(0.32), 8.0, true)
		draw_line(a + main_courante, b + main_courante, moulure, 2.0, true)

func _dessiner_mobilier_galion(element: String, plan: Vector2, bois: Color, moulure: Color) -> void:
	var rect := Rect2(plan - Vector2(22, 25), Vector2(44, 50))
	match element:
		"banc":
			_dessiner_table(rect, 24.0, bois, moulure)
			var dossier := Rect2(rect.position, Vector2(8, rect.size.y))
			_volume_mobilier(dossier, 47.0, bois.darkened(0.06), moulure, 24.0)
			_volume_mobilier(rect.grow(-6.0), 29.0, Color("#bc946e"), Color("#ddbd95"), 24.0)
		"table_pont":
			_peindre_rect_plan(rect.grow(10.0), Color("#94583e"))
			_peindre_rect_plan(rect.grow(7.0), Color("#c29b6b"))
			_peindre_rect_plan(rect.grow(4.0), Color("#814c37"))
			_dessiner_table(rect, 35.0, bois, moulure)
			var dessus := position_monde(plan) + Vector2.UP * 36.0
			draw_circle(dessus + Vector2(-6, 1), 6.0, Color("#b7975e"))
			draw_circle(dessus + Vector2(5, -3), 5.0, Color("#d9c1a0"))
		"table_cartes", "cartes":
			_dessiner_bureau(rect, true, bois, moulure)
		"caisses", "tonneaux", "coffre":
			var sprite: Texture2D = {"caisses": CAISSES, "tonneaux": TONNEAUX, "coffre": COFFRE}[element]
			_poser_sprite(sprite, plan, Vector2(72, 64))
		"salon":
			_poser_sprite(COFFRE, plan, Vector2(66, 52))
		"jardiniere":
			_volume_mobilier(rect, 17.0, bois.darkened(0.14), moulure)
			var terre := position_monde(plan) + Vector2.UP * 17.0
			for i in range(5):
				var feuille := terre + Vector2.from_angle(i * TAU / 5.0) * Vector2(15, 8) + Vector2.UP * 4.0
				draw_circle(feuille, 9.0, Color("#3c5234"))
				draw_circle(feuille + Vector2(-2, -4), 6.0, Color("#63804a"))
				draw_circle(feuille + Vector2(-1, -6), 3.0, Color("#cb9b80"))
		"lanterne":
			_dessiner_lanterne_pont(position_monde(plan), bois, moulure)
		_:
			_dessiner_element_pont(element, position_monde(plan), bois, moulure)

func _dessiner_lanterne_pont(pied: Vector2, bois: Color, moulure: Color) -> void:
	var sommet := pied + Vector2.UP * 55.0
	var lampe := sommet + Vector2(10, 20)
	draw_line(pied, sommet, bois.darkened(0.44), 7.0)
	draw_line(pied + Vector2.LEFT, sommet + Vector2.LEFT, moulure, 2.0)
	draw_arc(sommet + Vector2(5, 3), 6.0, PI, TAU, 12, moulure, 4.0, true)
	draw_line(lampe + Vector2.UP * 18.0, lampe + Vector2.UP * 10.0, moulure, 3.0)
	draw_circle(lampe, 19.0, Color("#f7bd5827"))
	draw_rect(Rect2(lampe - Vector2(7, 10), Vector2(14, 18)), bois.darkened(0.42))
	draw_rect(Rect2(lampe - Vector2(4, 6), Vector2(8, 11)), Color("#f6cd7a"))
	draw_line(lampe + Vector2(-8, -9), lampe + Vector2(8, -9), moulure, 3.0)
	draw_line(lampe + Vector2(-7, 8), lampe + Vector2(7, 8), moulure, 2.0)

func _dessiner_trappe(centre: Vector2, texture: Texture2D, bordage: Color, moulure: Color) -> void:
	var rect := Rect2(centre - Vector2(26, 24), Vector2(52, 48))
	_peindre_rect_plan(rect.grow(4.0), bordage.darkened(0.42))
	_peindre_rect_plan(rect, moulure.darkened(0.14))
	_surface_boisee(_coins(rect.grow(-5.0)), texture, Color("#c1a079"))
	for x in [11, 34]:
		_peindre_rect_plan(Rect2(rect.position + Vector2(x, 1), Vector2(7, 13)), Color("#534b41"))
	var poignee := PackedVector2Array()
	for index in 14:
		var angle := float(index) / 13.0 * TAU
		poignee.append(centre + Vector2.from_angle(angle) * 8.0)
	draw_polyline(_projeter(poignee), Color("#c18d4d"), 3.0)

func _dessiner_mat(plan: Vector2, hauteur: float, bande: Rect2i, bois: Color, moulure: Color) -> void:
	var galion := est_galion()
	var projection := projection_etage(false, galion)
	var pied := projection * plan
	var rayon := hauteur * 0.04 if galion else 10.0
	var echelle := rayon / 13.0 if galion else 1.0
	var tete := pied + Vector2(-3.0 * echelle, -hauteur)
	var greement := pied.lerp(tete, 0.76)
	var barreaux := 17 if galion else 7
	for x in [bande.position.x * CASE + 13.0, bande.end.x * CASE - 13.0]:
		var avant := projection * Vector2(x, plan.y - 20)
		var arriere := projection * Vector2(x, plan.y + 24)
		for attache in [avant, arriere]:
			draw_line(attache, greement, Color("#473626"), 3.0 * echelle, true)
			var reflet := Vector2.LEFT * echelle
			draw_line(attache + reflet, greement + reflet, Color("#aa885e"), echelle, true)
			draw_circle(attache, 4.0 * echelle, bois.darkened(0.34))
		for i in range(1, barreaux + 1):
			var niveau := 0.70 * i / barreaux
			draw_line(avant.lerp(greement, niveau), arriere.lerp(greement, niveau), Color("#8d6e4e"), 1.5 * echelle, true)

	draw_set_transform(pied, 0.0, Vector2(1.0, 0.52))
	draw_circle(Vector2(2, 4), rayon + 8.0, bois.darkened(0.57))
	draw_circle(Vector2.ZERO, rayon + 6.0, moulure.darkened(0.24))
	draw_circle(Vector2.ZERO, rayon + 2.0, bois.darkened(0.36))
	draw_set_transform(Vector2.ZERO)

	# Le tronc se rétrécit vers la tête et le bois clair suit sa courbure.
	var sommet := rayon * 0.48
	var tranche := PackedVector2Array([
		pied + Vector2(-rayon, -2), pied + Vector2(rayon, -2),
		tete + Vector2(sommet, 0), tete - Vector2(sommet, 0),
	])
	draw_polygon(tranche, PackedColorArray([
		bois.lightened(0.17), bois.darkened(0.47), bois.darkened(0.21), moulure.darkened(0.21),
	]))
	draw_line(pied - Vector2(rayon * 0.52, 4), tete - Vector2(sommet * 0.36, 1),
		moulure.darkened(0.13), 3.0 * echelle, true)
	for niveau in [0.08, 0.76, 0.94]:
		var milieu := pied.lerp(tete, niveau)
		var largeur := lerpf(rayon, sommet, niveau)
		draw_line(milieu - Vector2(largeur, 0), milieu + Vector2(largeur, 0), bois.darkened(0.51), 5.0 * echelle)
		draw_line(milieu - Vector2(largeur, echelle), milieu + Vector2(largeur, -echelle), moulure.darkened(0.23), 2.0 * echelle)
	var demi_largeur_vergue := minf(hauteur * 0.34, bande.size.x * CASE * 0.43)
	var vent := -projection.y.normalized()
	_dessiner_vergue(pied.lerp(tete, 0.66), demi_largeur_vergue, hauteur * 0.38, vent, echelle, bois, moulure)
	if galion:
		_dessiner_vergue(pied.lerp(tete, 0.89), demi_largeur_vergue * 0.65, hauteur * 0.19, vent, echelle, bois, moulure)
	draw_circle(tete, sommet, moulure.darkened(0.08))
	var fanion := PackedVector2Array([Vector2.ZERO, Vector2(27, 5), Vector2(38, 3),
		Vector2(30, 13), Vector2(36, 17), Vector2(17, 18), Vector2(0, 13)])
	for i in fanion.size():
		fanion[i] = tete + fanion[i] * echelle
	draw_colored_polygon(fanion, Color("#8a3931"))
	draw_line(tete, tete + Vector2.DOWN * 12.0 * echelle, moulure.darkened(0.26), 3.0 * echelle)

func _dessiner_vergue(milieu: Vector2, demi_largeur: float, hauteur_voile: float, vent: Vector2,
		echelle: float, bois: Color, moulure: Color) -> void:
	var bras := PROJECTION_PONT.basis_xform(Vector2(demi_largeur, 0))
	_dessiner_voile(milieu, bras, hauteur_voile, vent, echelle)
	var a := milieu - bras
	var b := milieu + bras
	var decor := Vector2.DOWN * echelle
	draw_line(a, b, bois.darkened(0.49), 9.0 * echelle, true)
	draw_line(a - decor * 2.0, b - decor * 2.0, moulure.darkened(0.21), 3.0 * echelle, true)
	for i in range(-2, 3):
		var noeud := milieu + bras * i * 0.42
		draw_line(noeud - decor * 3.0, noeud + decor * 7.0, Color("#b99968"), 2.5 * echelle, true)

func _point_voile(milieu: Vector2, bras: Vector2, hauteur: float, vent: Vector2, u: float, v: float) -> Vector2:
	var centre := sin(u * PI)
	var ventre := sin(v * PI * 0.79) * (0.20 + 0.80 * centre)
	var largeur := 0.91 + 0.12 * sin(v * PI * 0.72)
	return milieu + bras * (u * 2.0 - 1.0) * largeur \
		+ Vector2.DOWN * hauteur * v * (1.0 - 0.14 * centre) + vent * hauteur * (0.26 * ventre)

func _dessiner_voile(milieu: Vector2, bras: Vector2, hauteur: float, vent: Vector2, echelle: float) -> void:
	const COLONNES := 24
	const RANGS := 7
	var clair := Color("#f6ead1")
	var ombre := Color("#9d8058")
	var bas := PackedVector2Array()
	for i in range(COLONNES + 1):
		var u := float(i) / COLONNES
		bas.append(_point_voile(milieu, bras, hauteur, vent, u, 1.0))
	for i in COLONNES:
		var bande := PackedVector2Array()
		var nuances := PackedColorArray()
		for bord in [i, i + 1]:
			var u := float(bord) / COLONNES
			for j in range(RANGS + 1):
				var v := float(j if bord == i else RANGS - j) / RANGS
				var pli := (1.0 - cos((u * 5.0 + v * 0.20) * TAU)) * 0.07
				var nuance := 0.06 + u * 0.13 + (1.0 - v) * 0.15 + v * v * 0.31 + pli
				bande.append(_point_voile(milieu, bras, hauteur, vent, u, v))
				nuances.append(clair.lerp(ombre, nuance))
		draw_polygon(bande, nuances)

	for i in range(7):
		var couture := PackedVector2Array()
		for j in range(RANGS + 1):
			couture.append(_point_voile(milieu, bras, hauteur, vent, float(i) / 6.0, float(j) / RANGS))
		var bord := i == 0 or i == 6
		draw_polyline(couture, Color("#8a6c49") if bord else Color("#a387635b"), echelle * (2.7 if bord else 1.3), true)
	draw_polyline(bas, Color("#8a6c49"), 2.7 * echelle, true)

func _centre_coque() -> Vector2:
	var premiere: Rect2i = _rangees_pont.front()
	var derniere: Rect2i = _rangees_pont.back()
	return Vector2(premiere.position.x + premiere.size.x * 0.5, (premiere.position.y + derniere.end.y) * 0.5) * CASE

func _contour_pont() -> PackedVector2Array:
	var bord := PackedVector2Array()
	var premiere: Rect2i = _rangees_pont.front()
	var derniere: Rect2i = _rangees_pont.back()
	var axe := _centre_coque().x
	var arrondi := 120.0 if est_galion() else 70.0
	bord.append(Vector2(axe, premiere.position.y * CASE - arrondi))
	bord.append(Vector2(axe, derniere.end.y * CASE + 54.0))
	# L'enveloppe des rangées garde les cases à l'intérieur du pont.
	for bande in _rangees_pont:
		var arriere := 64.0 if est_galion() and bande == derniere else 0.0
		var rectangle := Rect2(bande.position * CASE, bande.size * CASE).grow_individual(27.0, 0.0, 27.0, arriere)
		bord.append_array(_coins(rectangle))
	var contour := Geometry2D.convex_hull(bord)
	contour.remove_at(contour.size() - 1)
	if ((contour[1] - contour[0]).cross(contour[2] - contour[1]) > 0.0) != est_galion():
		contour.reverse()
	for _passe in range(3):
		var lisse := PackedVector2Array()
		for i in contour.size():
			var a := contour[i]
			var b := contour[(i + 1) % contour.size()]
			# Limite le retrait au milieu des longs bordages.
			var fraction := minf(0.25, arrondi / a.distance_to(b))
			lisse.append(a.lerp(b, fraction))
			lisse.append(b.lerp(a, fraction))
		contour = lisse
	return contour

func _dessiner_element_pont(element: String, point: Vector2, bordage: Color, moulure: Color) -> void:
	var cadre := Rect2(point - Vector2(30, 28), Vector2(60, 56))
	match element:
		"forge":
			draw_style_box(_bordure(Color("#503e33"), Color("#a86c43"), 5), cadre.grow(4))
			draw_circle(point + Vector2(0, 6), 18, Color("#d77531"))
			draw_circle(point + Vector2(0, 6), 10, Color("#ffe180"))
			draw_rect(Rect2(point + Vector2(-9, -35), Vector2(18, 22)), Color("#794632"))
		"etabli":
			draw_style_box(_bordure(Color("#8d5b37"), moulure, 4), cadre)
			draw_rect(cadre.grow(-9), Color("#cfa66d"))
			draw_line(point + Vector2(-17, -9), point + Vector2(12, 13), Color("#5b534b"), 7.0)
		"alambic":
			draw_style_box(_bordure(Color("#614333"), moulure, 4), cadre)
			draw_circle(point + Vector2(-5, 8), 17, Color("#d2864e"))
			draw_polyline(PackedVector2Array([point, point + Vector2(0, -18), point + Vector2(18, -18), point + Vector2(18, 5)]),
				Color("#f0ae6a"), 6.0)
		"astrolabe":
			draw_style_box(_bordure(bordage, moulure, 4), cadre)
			draw_arc(point, 20.0, 0.0, TAU, 16, moulure, 4.0)
			draw_line(point + Vector2(-12, 12), point + Vector2(12, -12), moulure, 4.0)
		"grue":
			draw_style_box(_bordure(bordage, moulure, 4), cadre)
			draw_line(point + Vector2(-9, 16), point + Vector2(35, -31), Color("#5a3824"), 11.0)
			draw_line(point + Vector2(-9, 12), point + Vector2(35, -35), Color("#ba8250"), 6.0)
			draw_line(point + Vector2(35, -31), point + Vector2(35, -5), Color("#ddbc82"), 3.0)
			draw_texture_rect(CAISSES, Rect2(point + Vector2(20, -6), Vector2(32, 32)), false)

func _mobilier_plan(id: String, salle: Rect2i) -> Dictionary:
	var ateliers := Navires.modele_a_bord() == "ateliers"
	var plan: Dictionary = MEUBLES["atelier" if ateliers else id]
	var mobilier := {}
	for nom: String in plan:
		var zone: Rect2i = plan[nom]
		if ateliers and id == "cabine":
			zone.position.y = salle.size.y - zone.end.y
		mobilier[nom] = Rect2i(salle.position + zone.position, zone.size)
	return mobilier

func _dessiner_interieur() -> void:
	draw_rect(cadre_interieur().grow(1550.0), Color("#101821"))
	var finition := Navires.finition_pont()
	var style := FINITIONS.fiche(finition)
	var texture := FINITIONS.texture(finition)
	var bordage: Color = style["bordage"]
	var moulure: Color = style["moulure"]
	var passage := _rect_monde(couloir())
	var pieces := pieces_bord()
	_dessiner_soubassement(passage, bordage)
	for piece: Dictionary in pieces.values():
		var salle: Rect2i = piece["salle"]
		var seconde_rangee := Rect2i(salle.position.x, piece["porte"].y, salle.size.x, 1)
		_dessiner_soubassement(_rect_monde(salle.merge(seconde_rangee)), bordage)
	_surface_boisee(_coins(passage), texture, Color("#c7b9a6"))
	for id: String in pieces:
		var teinte := Color("#e7dacf") if est_ouverte(id) else Color("#8b8073")
		_surface_boisee(_coins(_rect_monde(pieces[id]["salle"])), texture, teinte)
		_surface_boisee(_coins(_rect_monde(Rect2i(pieces[id]["porte"], Vector2i.ONE))), texture, teinte.darkened(0.08))

	_dessiner_poutres_couloir(passage, pieces, bordage, moulure)
	_dessiner_echelle(bordage, moulure)
	for id: String in pieces:
		var piece: Dictionary = pieces[id]
		var rect := _rect_monde(piece["salle"])
		var ouverte := est_ouverte(id)
		var decor := _decor_chambre() if id == "chambre" else {}
		var peinture: Color = bordage.lightened(0.18)
		if id == "chambre":
			var murs := [peinture, Color("#466a58"), Color("#504e70"), Color("#843f36")]
			peinture = murs[clampi(int(decor.get("murs", 0)), 0, murs.size() - 1)]
		_dessiner_cloisons(rect, piece["porte"], ouverte, peinture, moulure)
		if ouverte:
			_dessiner_mobilier_interieur(id, piece["salle"], decor, bordage, moulure)

func _rect_monde(zone: Rect2i) -> Rect2:
	return Rect2(zone.position * CASE, zone.size * CASE)

func _dessiner_soubassement(rect: Rect2, bordage: Color) -> void:
	var coins := _coins(rect)
	draw_colored_polygon(_projeter(coins, Vector2(0, 28)), Color("#080e13"))
	var devant := _projeter(coins)
	for i in [1, 2]:
		var a := devant[i]
		var b := devant[i + 1]
		var epaisseur := Vector2(0, 20)
		draw_colored_polygon(PackedVector2Array([a, b, b + epaisseur, a + epaisseur]), bordage.darkened(0.43 + 0.07 * i))
		draw_line(a + epaisseur * 0.32, b + epaisseur * 0.32, bordage.darkened(0.24), 2.0)
	draw_colored_polygon(devant, bordage.darkened(0.40))

func _dessiner_cloisons(rect: Rect2, porte: Vector2i, ouverte: bool, bois: Color, moulure: Color) -> void:
	var haut_gauche := rect.position
	var haut_droite := Vector2(rect.end.x, rect.position.y)
	var bas_gauche := Vector2(rect.position.x, rect.end.y)
	_dessiner_pan(haut_gauche, bas_gauche, 75.0, bois.darkened(0.12), moulure, true)
	_dessiner_pan(haut_droite, rect.end, 12.0, bois.darkened(0.18), moulure)

	var porte_en_bas := porte.y * CASE >= int(rect.end.y)
	var y := rect.end.y if porte_en_bas else rect.position.y
	var hauteur := 12.0 if porte_en_bas else 75.0
	var debut_porte := Vector2(porte.x * CASE, y)
	var fin_porte := debut_porte + Vector2(CASE, 0)
	_dessiner_pan(Vector2(rect.position.x, y), debut_porte, hauteur, bois, moulure)
	_dessiner_pan(fin_porte, Vector2(rect.end.x, y), hauteur, bois, moulure)
	var autre_y := rect.position.y if porte_en_bas else rect.end.y
	_dessiner_pan(Vector2(rect.position.x, autre_y), Vector2(rect.end.x, autre_y),
		75.0 if porte_en_bas else 12.0, bois, moulure, porte_en_bas)
	_dessiner_ouverture(debut_porte, fin_porte, ouverte, bois, moulure)

func _dessiner_pan(debut: Vector2, fin: Vector2, hauteur: float, bois: Color, moulure: Color, hublot := false) -> void:
	var a := PROJECTION_INTERIEUR * debut
	var b := PROJECTION_INTERIEUR * fin
	var levee := Vector2.UP * hauteur
	draw_colored_polygon(PackedVector2Array([a, b, b + levee, a + levee]), bois)
	for y in [0.22, 0.45, 0.70]:
		draw_line(a + levee * y, b + levee * y, bois.darkened(0.31), 2.0)
	draw_line(a, b, bois.darkened(0.51), 4.0)
	draw_line(a + levee, b + levee, moulure, 3.0)
	draw_line(a, a + levee, moulure.darkened(0.16), 7.0)
	draw_line(b, b + levee, bois.darkened(0.28), 5.0)
	if hublot:
		var centre := a.lerp(b, 0.53) + levee * 0.60
		_dessiner_hublot(centre, (b - a).normalized(), moulure)

func _dessiner_hublot(centre: Vector2, axe: Vector2, moulure: Color) -> void:
	var cercle := PackedVector2Array()
	for pas in 16:
		var rayon := Vector2.from_angle(float(pas) / 16.0 * TAU)
		cercle.append(centre + axe * (rayon.x * 17.0) + Vector2.UP * (rayon.y * 18.0))
	draw_colored_polygon(cercle, Color("#1d434c"))
	cercle.append(cercle[0])
	draw_polyline(cercle, moulure.darkened(0.15), 4.0)
	draw_line(centre - axe * 9 + Vector2.UP * 3, centre + axe * 5 + Vector2.UP * 8, Color("#8cc4bd"), 2.0)

func _dessiner_ouverture(debut: Vector2, fin: Vector2, ouverte: bool, bois: Color, moulure: Color) -> void:
	var a := PROJECTION_INTERIEUR * debut
	var b := PROJECTION_INTERIEUR * fin
	var levee := Vector2.UP * 67.0
	if not ouverte:
		draw_colored_polygon(PackedVector2Array([a, b, b + levee, a + levee]), bois.darkened(0.30))
		for fraction in [0.18, 0.36, 0.54, 0.72, 0.88]:
			var ligne := a.lerp(b, fraction)
			draw_line(ligne, ligne + levee, bois.darkened(0.56), 2.0)
		draw_line(a + levee * 0.2, b + levee * 0.2, moulure.darkened(0.40), 6.0)
		draw_line(a + levee * 0.73, b + levee * 0.73, moulure.darkened(0.40), 6.0)
		draw_circle(a.lerp(b, 0.76) + levee * 0.46, 4.0, Color("#c6a36b"))
	for base in [a, b]:
		draw_line(base, base + levee, bois.darkened(0.48), 10.0)
		draw_line(base + Vector2.RIGHT, base + levee + Vector2.RIGHT, moulure, 3.0)
	draw_line(a + levee, b + levee, bois.darkened(0.44), 10.0)
	draw_line(a + levee + Vector2.UP * 3, b + levee + Vector2.UP * 3, moulure, 3.0)

func _dessiner_poutres_couloir(rect: Rect2, pieces: Dictionary, bordage: Color, moulure: Color) -> void:
	for x in range(couloir().position.x + 1, couloir().end.x, 3):
		for y in [rect.position.y, rect.end.y]:
			var point := Vector2((x + 0.5) * CASE, y)
			var touche_piece := false
			for piece: Dictionary in pieces.values():
				var salle := _rect_monde(piece["salle"]).grow(float(CASE))
				if salle.has_point(point):
					touche_piece = true
					break
			if touche_piece:
				continue
			var ancrage := PROJECTION_INTERIEUR * point
			draw_line(ancrage, ancrage + Vector2.UP * 66, bordage.darkened(0.21), 9.0)
			draw_line(ancrage + Vector2.RIGHT * 2, ancrage + Vector2(2, -66), moulure.darkened(0.18), 2.0)
			if y == rect.position.y:
				var lanterne := ancrage + Vector2(0, -50)
				draw_circle(lanterne, 20.0, Color("#efb45c23"))
				draw_rect(Rect2(lanterne - Vector2(6, 8), Vector2(12, 16)), Color("#ffc66f"))
				draw_rect(Rect2(lanterne - Vector2(6, 8), Vector2(12, 16)), Color("#5f3a25"), false, 2.0)

func _dessiner_echelle(bordage: Color, moulure: Color) -> void:
	var base := _centre(ECHELLE)
	_peindre_rect_plan(Rect2(base - Vector2(24, 19), Vector2(48, 38)), bordage.darkened(0.42))
	var gauche := PROJECTION_INTERIEUR * (base - Vector2(14, 0))
	var droite := PROJECTION_INTERIEUR * (base + Vector2(14, 0))
	for point in [gauche, droite]:
		draw_line(point, point + Vector2.UP * 82, bordage.darkened(0.44), 10.0)
		draw_line(point + Vector2.RIGHT * 2, point + Vector2(2, -82), moulure, 3.0)
	for marche in range(1, 6):
		var haut := Vector2.UP * (marche * 14)
		draw_line(gauche + haut, droite + haut, bordage.darkened(0.31), 7.0)
		draw_line(gauche + haut - Vector2(0, 2), droite + haut - Vector2(0, 2), moulure, 2.0)

func _decor_chambre() -> Dictionary:
	return Navires.donnees_a_bord().get("chambres", {}).get(Personnage.nom, {})

func _dessiner_mobilier_interieur(id: String, salle: Rect2i, decor: Dictionary, bois: Color, moulure: Color) -> void:
	var tapis := [Color("#b4916b"), Color("#385a7a"), Color("#783b54"), Color("#597747")]
	var teinte: Color = tapis[clampi(int(decor.get("tapis", 0)), 0, tapis.size() - 1)]
	if id == "chambre":
		var origine := Vector2(salle.position * CASE)
		var rect := Rect2(origine + Vector2(130, 91), Vector2(184, 118))
		_peindre_rect_plan(rect, teinte.darkened(0.29))
		_peindre_rect_plan(rect.grow(-6.0), teinte)
		_peindre_rect_plan(Rect2(rect.get_center() - Vector2(32, 18), Vector2(64, 36)), teinte.lightened(0.18))
	var mobilier := _mobilier_plan(id, salle)
	for element: String in mobilier:
		var plan: Rect2i = mobilier[element]
		var rect := _rect_monde(plan).grow(-9.0)
		match element:
			"lit":
				_dessiner_lit(rect, teinte, bois)
			"meuble_chambre":
				match int(decor.get("mobilier", 0)):
					1: _dessiner_bureau(rect, false, bois, moulure)
					2: _dessiner_bibliotheque(rect, bois, moulure)
					_: _poser_sprite(COFFRE, rect.get_center(), Vector2(84, 64))
			"bibliotheque":
				_dessiner_bibliotheque(rect, bois, moulure)
			"bureau", "table_cartes":
				_dessiner_bureau(rect, element == "table_cartes", bois, moulure)
			"etabli":
				match Navires.modele_a_bord():
					"navigation": _dessiner_bureau(rect, true, bois, moulure)
					"ateliers": _dessiner_etabli(rect, metier_atelier(id), bois, moulure)
					_: _dessiner_etabli(rect, Personnage.metier_perso(), bois, moulure)
			_:
				var sprite: Texture2D = {"tonneaux": TONNEAUX, "caisses": CAISSES, "coffre": COFFRE}[element]
				_poser_sprite(sprite, rect.get_center(), Vector2(70, 60))

func _volume_mobilier(rect: Rect2, hauteur: float, bois: Color, moulure: Color, base := 0.0) -> void:
	var bas := _projeter(_coins(rect), Vector2.UP * base)
	var haut := _projeter(_coins(rect), Vector2.UP * hauteur)
	for i in [1, 2]:
		draw_colored_polygon(PackedVector2Array([bas[i], bas[i + 1], haut[i + 1], haut[i]]),
			bois.darkened(0.27 if i == 1 else 0.42))
	draw_colored_polygon(haut, bois)
	haut.append(haut[0])
	draw_polyline(haut, moulure, 2.0)

func _poser_sprite(sprite: Texture2D, plan: Vector2, taille: Vector2, hauteur := 0.0) -> void:
	var base := position_monde(plan) + Vector2.UP * hauteur
	draw_texture_rect(sprite, Rect2(base - Vector2(taille.x * 0.5, taille.y * 0.79), taille), false)

func _dessiner_lit(rect: Rect2, drap: Color, bois: Color) -> void:
	_volume_mobilier(rect, 16.0, bois, bois.lightened(0.2))
	var matelas := rect.grow(-7.0)
	_volume_mobilier(matelas, 23.0, Color("#ded0b3"), Color("#f3e6cb"), 16.0)
	var couverture := Rect2(matelas.position + Vector2(2, matelas.size.y * 0.43), Vector2(matelas.size.x - 4, matelas.size.y * 0.55))
	_volume_mobilier(couverture, 25.0, drap, drap.lightened(0.21), 23.0)
	var oreiller := Rect2(matelas.position + Vector2(13, 6), Vector2(matelas.size.x - 26, 24))
	_volume_mobilier(oreiller, 28.0, Color("#f0e4cc"), Color("#d6bf9e"), 23.0)

func _dessiner_table(rect: Rect2, hauteur: float, bois: Color, moulure: Color) -> void:
	for coin in _coins(rect.grow(-6.0)):
		var pied := Rect2(coin - Vector2(4, 4), Vector2(8, 8))
		_volume_mobilier(pied, hauteur - 8.0, bois.darkened(0.23), moulure)
	_volume_mobilier(rect, hauteur, bois, moulure, hauteur - 8.0)

func _dessiner_bureau(rect: Rect2, cartes: bool, bois: Color, moulure: Color) -> void:
	_dessiner_table(rect, 42.0, bois, moulure)
	var papier := Rect2(rect.position + Vector2(17, 8), Vector2(minf(67.0, rect.size.x * 0.55), rect.size.y - 16))
	draw_colored_polygon(_projeter(_coins(papier), Vector2.UP * 43), Color("#ddc79b"))
	for i in range(3):
		var ligne := papier.position + Vector2(12, 6 + 6 * i)
		draw_line(position_monde(ligne) + Vector2.UP * 43,
			position_monde(ligne + Vector2(21 + 7 * i, 0)) + Vector2.UP * 43, Color("#ac9273"), 1.5)
	if cartes:
		_poser_sprite(BOUSSOLE, papier.end.lerp(papier.position, 0.25), Vector2(32, 28), 43.0)
	elif Inventaire.dans_sac_ou_cale(Personnage.trophee_navire):
		_poser_sprite(_icone_objet(Personnage.trophee_navire, TROPHEE), rect.end - Vector2(17, 14), Vector2(38, 38), 42.0)

func _dessiner_bibliotheque(rect: Rect2, bois: Color, moulure: Color) -> void:
	_volume_mobilier(rect, 67.0, bois.darkened(0.15), moulure)
	var a := PROJECTION_INTERIEUR * Vector2(rect.position.x, rect.end.y)
	var b := PROJECTION_INTERIEUR * rect.end
	for i in range(1, 7):
		var point := a.lerp(b, float(i) / 7.0)
		var couleur: Color = [Color("#796346"), Color("#713e34"), Color("#586656")][i % 3]
		draw_line(point + Vector2.UP * 23, point + Vector2.UP * 53, couleur, 6.0)
	draw_line(a + Vector2.UP * 21, b + Vector2.UP * 21, moulure.darkened(0.21), 4.0)

func _dessiner_etabli(rect: Rect2, metier: String, bois: Color, moulure: Color) -> void:
	var code := str(Personnage.professions().get(metier, {}).get("code", ""))
	_dessiner_table(rect, 38.0, Color("#62544a") if code in ["cook", "blacksmith"] else bois, moulure)
	var icone: Texture2D = ACCESSOIRES_ATELIER.get(code, BOIS_ATELIER)
	_poser_sprite(icone, rect.get_center(), Vector2(39, 35), 38.0)
	if code in ["cook", "blacksmith"]:
		var braise := PROJECTION_INTERIEUR * (rect.position + Vector2(23, rect.size.y * 0.5)) + Vector2.UP * 40
		draw_circle(braise, 14, Color("#372927"))
		draw_circle(braise, 8, Color("#ce7e46"))

func _icone_objet(id: String, defaut: Texture2D) -> Texture2D:
	var icone := str(Inventaire.details_objet(id).get("chemin_icone", ""))
	return load(icone) as Texture2D if not icone.is_empty() and ResourceLoader.exists(icone) else defaut

func _centre(case_sol: Vector2i) -> Vector2:
	return Vector2(case_sol * CASE) + Vector2.ONE * CASE * 0.5

func _bordure(fond: Color, ligne: Color, largeur: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fond
	style.border_color = ligne
	style.set_border_width_all(largeur)
	style.set_corner_radius_all(7)
	return style
