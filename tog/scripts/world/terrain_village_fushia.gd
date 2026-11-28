@tool
extends "res://scripts/world/terrain_alabasta.gd"

enum Surface { HERBE, PAVE, PLAGE, SENTIER, ROCHE, ARRIERE_PAYS }

const DOMAINE := Rect2i(-8, -11, 42, 47)
const GRANDE_PLACE := Rect2i(9, 7, 12, 9)
const HAUTEUR_PLACE := 96
const HAUTEUR_JARDINS := 168
const HAUTEUR_PORT := 24
const HAUTEUR_ENTREPOTS := 54
const HAUTEUR_QUAI_MARCHAND := 18
const HAUTEUR_PECHE := 8
const TERRASSE_ENTREPOTS := Rect2i(12, 17, 11, 6)
const QUAI_MARCHAND := Rect2i(12, 23, 12, 7)
const COULEUR_LISIERE := Color("#587558")
const PIERRE_COTIERE := preload("res://assets/world/fushia_village/roche_littorale.png")
const HERBE_LITTORALE := preload("res://assets/world/fushia_village/herbe_littorale.png")
const PIN := preload("res://assets/world/kit_cartes/nature/pin_de_montagne.png")
const SHADER_ECUME := preload("res://assets/shaders/ecume_fushia.gdshader")
const TAILLE_MOTIF_ROCHE := Vector2(288, 256)
const COINS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1),
]

# Les profils découpent les rives dans la grille. Les segments droits du
# port correspondent aux quais de pierre et aux raccords des jetées.
const COTE_PORT: Array[Vector2i] = [
	Vector2i(-8, 15), Vector2i(-5, 19), Vector2i(-2, 22), Vector2i(0, 25),
	Vector2i(2, 28), Vector2i(4, 30), Vector2i(8, 30), Vector2i(10, 28),
	Vector2i(11, 25), Vector2i(13, 26), Vector2i(16, 29), Vector2i(21, 29),
	Vector2i(22, 29), Vector2i(24, 25), Vector2i(25, 23), Vector2i(26, 27),
	Vector2i(28, 26), Vector2i(30, 28), Vector2i(31, 28), Vector2i(33, 25), Vector2i(34, 20),
]
const COTE_NORD: Array[Vector2i] = [
	Vector2i(-8, 5), Vector2i(-5, 1), Vector2i(-2, -1), Vector2i(3, -3),
	Vector2i(6, -5), Vector2i(10, -4), Vector2i(13, -8), Vector2i(17, -11),
	Vector2i(21, -10), Vector2i(24, -7), Vector2i(27, -3), Vector2i(30, -2),
	Vector2i(34, 4),
]
const COTE_OUEST: Array[Vector2i] = [
	Vector2i(-11, 10), Vector2i(-6, 4), Vector2i(-3, 0), Vector2i(1, -4),
	Vector2i(5, -6), Vector2i(9, -5), Vector2i(12, -4), Vector2i(16, -6),
	Vector2i(19, -7), Vector2i(22, -4), Vector2i(25, -1), Vector2i(28, 1),
	Vector2i(32, 4), Vector2i(36, 7),
]
const COTE_EST: Array[Vector2i] = [
	Vector2i(-11, 19), Vector2i(-8, 24), Vector2i(-4, 28), Vector2i(1, 31),
	Vector2i(5, 30), Vector2i(8, 29), Vector2i(12, 32), Vector2i(15, 33),
	Vector2i(18, 32), Vector2i(21, 31), Vector2i(24, 33), Vector2i(28, 32),
	Vector2i(32, 27), Vector2i(36, 22),
]
const CRETES_DU_COL := [
	[Vector2(13.5, -6.1), Vector2(3.7, 3.4), 96.0],
	[Vector2(17.1, -8.7), Vector2(4.2, 3.8), 182.0],
	[Vector2(20.2, -5.7), Vector2(4.5, 3.9), 144.0],
]
const LISIERE_DES_TERRES: Array[Vector2i] = [
	Vector2i(-640, 568), Vector2i(-240, 603), Vector2i(150, 646), Vector2i(498, 594),
	Vector2i(824, 692), Vector2i(1116, 745), Vector2i(1450, 705), Vector2i(1902, 744),
	Vector2i(2360, 756), Vector2i(2860, 820), Vector2i(3370, 899), Vector2i(3770, 880),
	Vector2i(4270, 846), Vector2i(4650, 720), Vector2i(4950, 674), Vector2i(5440, 710),
]
var _coins_littoraux: Dictionary[Vector2i, Vector2] = {}

func _init() -> void:
	origine = Vector2(2496, 368)
	taille_monde = Vector2(4800, 2560)
	dallage = DALLAGE
	maconnerie = MUR_CALCAIRE
	escaliers = [
		[Vector2(16, 2.9), HAUTEUR_JARDINS, Vector2(16, 5.8), HAUTEUR_PLACE, 1.22],
		[Vector2(15, 14.5), HAUTEUR_PLACE, Vector2(15, 18.3), HAUTEUR_ENTREPOTS, 1.60],
		[Vector2(24, 14.8), HAUTEUR_PLACE, Vector2(24, 17.8), HAUTEUR_PORT, 1.08],
		[Vector2(14.5, 21.8), HAUTEUR_ENTREPOTS, Vector2(14.5, 24.4), HAUTEUR_QUAI_MARCHAND, 1.15],
		[Vector2(28.6, 21.3), HAUTEUR_PORT, Vector2(28.6, 24.4), HAUTEUR_PECHE, 0.88],
	]
	# Les rampes utilisent aussi l'emprise de navigation des liaisons d'Alabasta.
	ponts = [
		[Vector2(6, 14.2), HAUTEUR_PLACE, Vector2(6, 18.6), HAUTEUR_PORT, 1.35],
		[Vector2(20.7, 21.4), HAUTEUR_ENTREPOTS, Vector2(20.7, 25.0), HAUTEUR_QUAI_MARCHAND, 1.14],
	]
	# Les tabliers s'appuient sur la terre à leurs accès. La dernière
	# liaison franchit l'anse entre le quai marchand et la plage.
	quais = [
		[Vector2(6, 29.8), HAUTEUR_PORT, Vector2(6, 36.2), 8, 1.42],
		[Vector2(26.7, 26.4), HAUTEUR_PECHE, Vector2(26.7, 29.3), 3, 0.62],
		[Vector2(30.7, 27.7), HAUTEUR_PECHE, Vector2(30.7, 31.4), 2, 0.77],
		[Vector2(22.8, 26.25), HAUTEUR_QUAI_MARCHAND, Vector2(26.55, 26.25), HAUTEUR_PECHE, 0.72],
	]

func _bord_de_mer(u: int) -> int:
	return _limite_cote(u, COTE_PORT)

func _preparer_dalles() -> void:
	if not _carreaux.is_empty():
		return
	var cadre := Rect2(Vector2.ZERO, taille_monde).grow(520.0)
	for u in range(-37, 49):
		for v in range(-39, 48):
			var cellule := Vector2i(u, v)
			if cadre.has_point(_projeter(cellule, HAUTEUR_JARDINS)):
				_carreaux_ajouter(cellule)
	_ordre = _carreaux.keys()
	_ordre.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x + a.y == b.x + b.y else a.x + a.y < b.x + b.y)

func _limite_cote(valeur: int, profil: Array[Vector2i]) -> int:
	for indice in range(1, profil.size()):
		var fin := profil[indice]
		if valeur <= fin.x:
			var debut := profil[indice - 1]
			var fraction := clampf(float(valeur - debut.x) / (fin.x - debut.x), 0.0, 1.0)
			return roundi(lerpf(debut.y, fin.y, fraction))
	return profil.back().y

func _carreaux_ajouter(cellule: Vector2i) -> void:
	var u := cellule.x
	var v := cellule.y
	var dans_le_village := DOMAINE.has_point(cellule) and v <= _bord_de_mer(u) \
		and v >= _limite_cote(u, COTE_NORD) and u >= _limite_cote(v, COTE_OUEST) and u <= _limite_cote(v, COTE_EST)
	if not dans_le_village:
		_ajouter_arriere_pays(cellule)
		return
	var surplomb := _relief_du_col(cellule)
	if surplomb > 0:
		_carreaux[cellule] = Vector3i(HAUTEUR_JARDINS + surplomb, Surface.ROCHE, Relief.MESA)
		return
	var niveau := HAUTEUR_PORT
	if v <= 3:
		niveau = HAUTEUR_JARDINS
	elif v <= 15:
		niveau = HAUTEUR_PLACE
	elif TERRASSE_ENTREPOTS.has_point(cellule):
		niveau = HAUTEUR_ENTREPOTS
	elif QUAI_MARCHAND.has_point(cellule):
		niveau = HAUTEUR_QUAI_MARCHAND
	elif u >= 26 and v >= 23:
		niveau = HAUTEUR_PECHE
	var chemin_du_col := absi(u - 16) <= 1 and v >= -5 and v < -1
	var chemin_du_bois := v >= 11 and v <= 13 and u <= 1
	var rues := u >= 3 and u <= 25 and v >= 6 and v <= 16
	var parvis_du_ferry := (u >= 3 and u <= 9 and v >= 24) or (u >= 5 and u <= 8 and v >= 17 and v < 24)
	var voie_du_port := (u >= 6 and u <= 12 and v >= 18 and v <= 20) or (u >= 23 and u <= 25 and v <= 22 and v >= 17)
	var zone_du_fret := TERRASSE_ENTREPOTS.has_point(cellule) or QUAI_MARCHAND.has_point(cellule)
	var plage_des_pecheurs := u >= 26 and v >= 23 and (v >= 25 or u >= 30)
	var chemin_des_pecheurs := u >= 26 and u <= 30 and v >= 17 and v <= 24
	var montee := u >= 14 and u <= 17 and v >= -1 and v <= 6
	var rue_du_bois := v >= 11 and v <= 13 and u <= 4
	var sol := Surface.HERBE
	if plage_des_pecheurs or (v >= _bord_de_mer(u) - 1 and (u <= 2 or u >= 26)):
		sol = Surface.PLAGE
	elif chemin_du_col or chemin_du_bois or chemin_des_pecheurs:
		sol = Surface.SENTIER
	elif rues or montee or rue_du_bois or parvis_du_ferry or voie_du_port or zone_du_fret:
		sol = Surface.PAVE
	_carreaux[cellule] = Vector3i(niveau, sol, Relief.VILLE if sol == Surface.PAVE else Relief.SOL)

func _ajouter_arriere_pays(cellule: Vector2i) -> void:
	var point := _projeter(cellule, HAUTEUR_JARDINS)
	var rive := _limite_cote(roundi(point.x), LISIERE_DES_TERRES)
	if point.y > rive:
		return
	_carreaux[cellule] = Vector3i(roundi(_altitude_arriere(point)), Surface.ARRIERE_PAYS, Relief.MESA)

func _altitude_arriere(point: Vector2) -> float:
	var rive := _limite_cote(roundi(point.x), LISIERE_DES_TERRES)
	var retrait := smoothstep(35.0, 560.0, rive - point.y)
	var collines := 0.5 + 0.27 * sin(point.x * 0.007 + point.y * 0.003) \
		+ 0.19 * cos(point.x * 0.004 - point.y * 0.009)
	var bord_ouest := 1.0 - smoothstep(200.0, 1650.0, point.x)
	return HAUTEUR_JARDINS + retrait * collines * 98.0 - bord_ouest * (1.0 - retrait * 0.7) * 51.0

func _relief_du_col(cellule: Vector2i) -> int:
	# L'échancrure entre les éperons reste au niveau du chemin jusqu'au seuil.
	if cellule.y >= -2 or (absi(cellule.x - 16) <= 1 and cellule.y >= -5):
		return 0
	var hauteur := 0.0
	for crete in CRETES_DU_COL:
		var centre: Vector2 = crete[0]
		var rayon: Vector2 = crete[1]
		var distance := ((Vector2(cellule) - centre) / rayon).length()
		hauteur = maxf(hauteur, maxf(0.0, 1.0 - distance) * float(crete[2]))
	return roundi(hauteur / 24.0) * 24

func _couleur_dalle(dalle: Vector3i) -> Color:
	match dalle.y:
		Surface.HERBE:
			return Color("#819959")
		Surface.PLAGE:
			return Color("#dfbc79")
		Surface.SENTIER:
			return Color("#bea175")
		Surface.ROCHE:
			return OBSTACLE
		Surface.ARRIERE_PAYS:
			return COULEUR_LISIERE
		_:
			return Color("#e4ba86") if dalle.x <= HAUTEUR_PORT else Color("#ecd0a4")

func _est_sol(couleur: Color) -> bool:
	return couleur != COULEUR_LISIERE and super._est_sol(couleur)

func _fond_des_terres() -> PackedVector2Array:
	var fond := PackedVector2Array([Vector2(-640, -560), Vector2(5440, -560)])
	for indice in range(LISIERE_DES_TERRES.size() - 1, -1, -1):
		fond.append(Vector2(LISIERE_DES_TERRES[indice]) - Vector2(0, 120))
	return fond

func _peindre_fond_carte(carte: Image) -> void:
	_peindre_carte(carte, _fond_des_terres(), COULEUR_LISIERE)

func _dessiner_dalle(cellule: Vector2i, dalle: Vector3i, contour: PackedVector2Array) -> void:
	var echelle := 0.68
	var teinte := Color("#fff3dd")
	var texture: Texture2D = DALLAGE
	match dalle.y:
		Surface.HERBE:
			echelle = 1.0
			texture = HERBE_LITTORALE
			teinte = Color("#faffdf")
		Surface.PLAGE:
			echelle = 0.58
			texture = SABLE
			teinte = Color("#ffedc0")
		Surface.SENTIER:
			echelle = 0.72
			texture = PISTE
			teinte = Color("#edcca1")
		Surface.ROCHE:
			texture = PIERRE_COTIERE
			teinte = Color("#ede3d4")
		Surface.ARRIERE_PAYS:
			texture = HERBE_LITTORALE
			teinte = Color("#a5bba0").lerp(Color("#728e7d"), clampf((dalle.x - HAUTEUR_JARDINS) / 108.0, 0.0, 1.0))
		_:
			if GRANDE_PLACE.has_point(cellule):
				teinte = Color("#fff8ea")
			elif dalle.x <= HAUTEUR_PORT:
				teinte = Color("#eacfab")
	var uv := PackedVector2Array()
	var depart := _projeter(Vector2.ZERO, dalle.x)
	for point in contour:
		if dalle.y == Surface.ARRIERE_PAYS:
			uv.append(point / Vector2(128, 86))
			continue
		if dalle.y == Surface.ROCHE:
			uv.append(point / TAILLE_MOTIF_ROCHE)
			continue
		var delta := point - depart
		var coord := Vector2(delta.y / 64.0 + delta.x / 128.0, delta.y / 64.0 - delta.x / 128.0)
		uv.append((coord + Vector2(0.5, 0.5)) * echelle)
	draw_polygon(contour, PackedColorArray([teinte]), uv, texture)

func _ecume_standard(cellule: Vector2i) -> bool:
	return (cellule.x >= 4 and cellule.x <= 8 and cellule.y >= 29) \
		or (cellule.x >= 16 and cellule.x <= 22 and cellule.y >= 28)

func _coin_littoral(coin: Vector2i) -> Vector2:
	if _coins_littoraux.has(coin):
		return _coins_littoraux[coin]
	var point := Vector2(coin) * 0.5
	var cote := Vector2.ZERO
	var voisins := 0
	var quai := false
	for retrait in COINS:
		var cellule := (coin + retrait) / 2
		if _carreaux.has(cellule):
			cote += Vector2(retrait)
			voisins += 1
			quai = quai or _ecume_standard(cellule)
	if not quai:
		if voisins == 1:
			point += cote * 0.25
		elif voisins == 3:
			point -= cote * 0.20
		elif voisins == 2:
			point += cote * sin(coin.x * 0.74 + coin.y * 0.57) * 0.05
	_coins_littoraux[coin] = point
	return point

func _arc_littoral(cellule: Vector2i, altitude: int, cote: int) -> PackedVector2Array:
	var debut := _coin_littoral(cellule * 2 + COINS[cote])
	var fin := _coin_littoral(cellule * 2 + COINS[(cote + 1) % COINS.size()])
	var dalle := _carreaux[cellule]
	var courbe := dalle.y == Surface.ARRIERE_PAYS and altitude == dalle.x
	var arc := PackedVector2Array([_projeter_la_rive(debut, altitude, courbe)])
	if not _carreaux.has(cellule + VOISINES[cote]) and not _ecume_standard(cellule):
		var normale := Vector2(VOISINES[cote])
		for etape in range(1, 5):
			var t := etape / 5.0
			var point := debut.lerp(fin, t)
			var ondulation := sin(point.x * 2.8 + point.y * 2.3) * 0.10 \
				+ sin(point.y * 4.2 - point.x * 1.6) * 0.08
			var avance := sin(t * PI) * (0.10 + ondulation)
			arc.append(_projeter_la_rive(point + normale * avance, altitude, courbe))
	arc.append(_projeter_la_rive(fin, altitude, courbe))
	return arc

func _projeter_la_rive(point: Vector2, altitude: int, courbe: bool) -> Vector2:
	var hauteur := _altitude_arriere(_projeter(point, HAUTEUR_JARDINS)) if courbe else float(altitude)
	return _projeter(point, hauteur)

func _contour_surface(cellule: Vector2i, dalle: Vector3i, _contour: PackedVector2Array) -> PackedVector2Array:
	var contour := PackedVector2Array()
	for cote in COINS.size():
		var arc := _arc_littoral(cellule, dalle.x, cote)
		contour.append_array(arc.slice(0, arc.size() - 1))
	return contour

func _dessiner_paroi(face: PackedVector2Array, cote: int, taillee: bool, altitude: float) -> void:
	var teinte := Color("#b2a1a4") if cote == 1 else Color("#d5c3b0")
	var texture := MUR_CALCAIRE if taillee else PIERRE_COTIERE
	var uv := PackedVector2Array()
	if taillee:
		var motif := texture.get_size()
		var gauche := Vector2(face[0].x, -altitude) / motif
		var droite := Vector2(face[1].x, -altitude) / motif
		uv = PackedVector2Array([gauche, droite,
			droite + Vector2.DOWN * (face[2].y - face[1].y) / motif.y,
			gauche + Vector2.DOWN * (face[3].y - face[0].y) / motif.y])
	else:
		for point in face:
			uv.append(point / TAILLE_MOTIF_ROCHE)
	draw_polygon(face, PackedColorArray([teinte, teinte, teinte.darkened(0.20), teinte.darkened(0.20)]),
		uv, texture)

func _draw() -> void:
	var fond := _fond_des_terres()
	var uv_fond := PackedVector2Array()
	for point in fond:
		uv_fond.append(point / Vector2(128, 86))
	draw_polygon(fond, PackedColorArray([Color("#a2b395")]), uv_fond, HERBE_LITTORALE)
	for cellule in _ordre:
		var dalle := _carreaux[cellule]
		for cote in [1, 2]:
			_dessiner_rebord(cellule, dalle, cote)
		_dessiner_dalle(cellule, dalle, _contour_surface(cellule, dalle, PackedVector2Array()))
	for escalier in escaliers:
		_dessiner_escalier(escalier)
	for rampe in ponts:
		_dessiner_rampe(rampe)
	_dessiner_bordure_place()
	for quai in quais:
		_dessiner_appontement(quai)

func _dessiner_rebord(cellule: Vector2i, dalle: Vector3i, cote: int) -> void:
	var voisine: Vector3i = _carreaux.get(cellule + VOISINES[cote], Vector3i(NIVEAU_MER, 0, 0))
	if dalle.x <= voisine.x or (dalle.y == Surface.ARRIERE_PAYS and voisine.y == Surface.ARRIERE_PAYS):
		return
	var arc := _arc_littoral(cellule, dalle.x, cote)
	var pied := _arc_littoral(cellule, voisine.x, cote)
	var maconnee := dalle.z == Relief.VILLE and (_carreaux.has(cellule + VOISINES[cote]) or _ecume_standard(cellule))
	for indice in range(1, arc.size()):
		var gauche := arc[indice - 1]
		var droite := arc[indice]
		var bas_gauche := pied[indice - 1]
		var bas_droite := pied[indice]
		if absf(gauche.x - droite.x) < 0.05 or (bas_gauche.y <= gauche.y and bas_droite.y <= droite.y):
			continue
		# Une pente peut croiser le niveau voisin à une extrémité.
		bas_gauche.y = maxf(bas_gauche.y, gauche.y + 0.15)
		bas_droite.y = maxf(bas_droite.y, droite.y + 0.15)
		var face := PackedVector2Array([gauche, droite, bas_droite, bas_gauche])
		_dessiner_paroi(face, cote, maconnee, dalle.x)

func _ready() -> void:
	super._ready()
	var ecume := Node2D.new()
	ecume.name = "EcumeLittorale"
	ecume.z_index = -1
	var materiau := ShaderMaterial.new()
	materiau.shader = SHADER_ECUME
	ecume.material = materiau
	ecume.draw.connect(_dessiner_ecume_littorale.bind(ecume))
	add_child(ecume)
	_planter_lisiere()

func _dessiner_ecume_littorale(calque: Node2D) -> void:
	for cellule in _ordre:
		if _ecume_standard(cellule):
			continue
		for cote in [1, 2]:
			if _carreaux.has(cellule + VOISINES[cote]):
				continue
			var arc := _arc_littoral(cellule, NIVEAU_MER - 9, cote)
			calque.draw_polyline(arc, Color("#3cc5b989"), 24.0, true)
			calque.draw_polyline(arc, Color("#c4f2d4bc"), 6.5, true)

func _planter_lisiere() -> void:
	var bois := Node2D.new()
	bois.name = "PinsDesHauteurs"
	add_child(bois)
	for cellule in _ordre:
		var dalle := _carreaux[cellule]
		if dalle.y != Surface.ARRIERE_PAYS:
			continue
		var point := _projeter(cellule, dalle.x)
		var graine := posmod(hash(cellule), 211)
		var groupe_serre := sin(point.x * 0.009 - point.y * 0.017) > -0.2
		if graine % (6 if groupe_serre else 15) != 0:
			continue
		if point.y > _limite_cote(roundi(point.x), LISIERE_DES_TERRES) - 82.0:
			continue
		var arbre := Sprite2D.new()
		arbre.texture = PIN
		arbre.position = point
		arbre.offset.y = -87.0
		arbre.flip_h = graine % 2 == 0
		arbre.scale = Vector2.ONE * (0.45 + (graine % 7) * 0.07)
		arbre.modulate = Color("#99ad95").lerp(Color("#78948e"), 1.0 - smoothstep(20.0, 210.0, point.y))
		bois.add_child(arbre)

func _dessiner_bordure_place() -> void:
	var coin := Vector2(GRANDE_PLACE.position) - Vector2(0.3, 0.3)
	var fin := Vector2(GRANDE_PLACE.end) - Vector2(0.7, 0.7)
	var trace := PackedVector2Array()
	for point in [coin, Vector2(fin.x, coin.y), fin, Vector2(coin.x, fin.y), coin]:
		trace.append(_projeter(point, HAUTEUR_PLACE))
	draw_polyline(trace, Color("#a78464"), 4.0)
	draw_polyline(trace, Color("#e9c296"), 1.0)

func _dessiner_appontement(quai: Array) -> void:
	var demi_largeur: float = quai[4] + 0.18
	var lisiere := _extremites(quai, demi_largeur)
	for cote in 2:
		var sommet := lisiere[cote]
		var pointe := lisiere[cote + 2]
		var supports := maxi(2, ceili(sommet.distance_to(pointe) / 74.0))
		for indice in range(1, supports + 1):
			var poteau := sommet.lerp(pointe, float(indice) / supports)
			draw_line(poteau, poteau + Vector2(0, 40), Color("#563b30"), 12.0)
			draw_line(poteau - Vector2(3, 0), poteau + Vector2(-3, 36), Color("#a7794a"), 4.0)
	_dessiner_liaison(self, [quai[0], quai[1], quai[2], quai[3], true], demi_largeur)

func _dessiner_rampe(liaison: Array) -> void:
	var contour := _polygone_liaison(liaison)
	var denivele := Vector2.DOWN * float(liaison[1] - liaison[3])
	var assise := Vector2(0, 2)
	_dessiner_paroi(PackedVector2Array([contour[0], contour[3], contour[3] + assise, contour[0] + denivele]), 2, true, liaison[1])
	_dessiner_paroi(PackedVector2Array([contour[1], contour[2], contour[2] + assise, contour[1] + denivele]), 1, true, liaison[1])
	var depart: Vector2 = liaison[0]
	var arrivee: Vector2 = liaison[2]
	var largeur := Vector2(float(liaison[4]), 0)
	var uv := PackedVector2Array()
	for coin in [depart - largeur, depart + largeur, arrivee + largeur, arrivee - largeur]:
		uv.append((coin + Vector2(0.5, 0.5)) * 0.68)
	draw_polygon(contour, PackedColorArray([Color("#fae4c4")]), uv, DALLAGE)
	draw_line(contour[0], contour[3], Color("#9d7952"), 4.0)
	draw_line(contour[1], contour[2], Color("#e1c7a0"), 4.0)
