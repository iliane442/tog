extends Node2D

const CASE := 64
const DIMENSIONS := Vector2i(43, 18)
const PONT := [Rect2i(6, 3, 2, 2), Rect2i(5, 5, 4, 7)]
const COULOIR := Rect2i(22, 8, 16, 2)
const PIECES := {
	"atelier": {"salle": Rect2i(22, 3, 7, 4), "porte": Vector2i(25, 7), "seuil": Vector2i(25, 8), "poste": Vector2i(25, 5)},
	"cale": {"salle": Rect2i(31, 3, 7, 4), "porte": Vector2i(34, 7), "seuil": Vector2i(34, 8), "poste": Vector2i(34, 5)},
	"cabine": {"salle": Rect2i(22, 11, 7, 4), "porte": Vector2i(25, 10), "seuil": Vector2i(25, 9), "poste": Vector2i(25, 13)},
	"cartes": {"salle": Rect2i(31, 11, 7, 4), "porte": Vector2i(34, 10), "seuil": Vector2i(34, 9), "poste": Vector2i(34, 13)},
}
const COQUE := preload("res://assets/world/navires-generation-v1-coque-explorateur.png")
const BOIS := preload("res://assets/world/kit_cartes/sols.png")
const TONNEAUX := preload("res://assets/world/world-pixellab-decors-v1-tempere-tonneaux.png")
const CAISSES := preload("res://assets/world/world-pixellab-decors-v1-tempere-caisses-empilees.png")
const COFFRE := preload("res://assets/world/world-pixellab-decors-v1-tempere-coffre-de-marin.png")
const TROPHEE := preload("res://assets/items/081_trophee_de_capitaine_pirate.png")
const BOUSSOLE := preload("res://assets/items/073_boussole_de_grand_line_instable.png")

var apercu: Texture2D
var sous_le_pont := false
var _sol: TileMapLayer

func dimensions_monde() -> Vector2:
	return Vector2(DIMENSIONS * CASE)

func preparer(sol: TileMapLayer, _falaises: TileMapLayer, _paysage: Node2D) -> void:
	_sol = sol
	actualiser_pieces()

func actualiser_pieces() -> void:
	_sol.clear()
	for rectangle in PONT:
		_ouvrir_sol(rectangle)
	_ouvrir_sol(COULOIR)
	for id in Personnage.pieces_navire_ouvertes:
		var piece: Dictionary = PIECES[id]
		_ouvrir_sol(piece["salle"])
		_sol.set_cell(piece["porte"], 0, Vector2i.ZERO)
	var image := Image.create_empty(DIMENSIONS.x, DIMENSIONS.y, false, Image.FORMAT_RGB8)
	image.fill(Color("#183546"))
	for case_sol in _sol.get_used_cells():
		image.set_pixelv(case_sol, Color("#bc8a59"))
	if apercu == null:
		apercu = ImageTexture.create_from_image(image)
	else:
		(apercu as ImageTexture).update(image)
	queue_redraw()

func _ouvrir_sol(zone: Rect2i) -> void:
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			_sol.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)

func montrer_interieur(etat: bool) -> void:
	sous_le_pont = etat
	queue_redraw()

func _draw() -> void:
	if sous_le_pont:
		_dessiner_interieur()
	else:
		_dessiner_pont()

func _dessiner_pont() -> void:
	draw_rect(Rect2(-1600, -1300, 5400, 3900), Color("#143f51"))
	for y in range(-10, 23):
		for x in range(-17, 24):
			var debut := Vector2(x * 115 + (y % 2) * 56, y * 60)
			var couleur := Color("#215468") if (x + y) % 3 != 0 else Color("#286076")
			draw_polyline(PackedVector2Array([debut, debut + Vector2(12, -2), debut + Vector2(28, 0)]), couleur, 2.0)
	_dessiner_plancher(Rect2(590, 721, 150, 54), Color("#9d7e69"))
	draw_texture(COQUE, Vector2(-176, -32))

func _dessiner_interieur() -> void:
	draw_rect(Rect2(-800, -1300, 5600, 3900), Color("#101821"))
	var couloir := Rect2(COULOIR.position * CASE, COULOIR.size * CASE)
	draw_style_box(_bordure(Color("#1e2a2f"), Color("#513a2f"), 12), couloir.grow(15))
	_dessiner_plancher(couloir, Color("#ac8165"))
	for id in PIECES:
		var piece: Dictionary = PIECES[id]
		var salle: Rect2i = piece["salle"]
		var rect := Rect2(salle.position * CASE, salle.size * CASE)
		var ouverte: bool = id in Personnage.pieces_navire_ouvertes
		draw_style_box(_bordure(Color("#181b23"), Color("#704d36"), 9), rect.grow(9))
		if ouverte:
			_dessiner_plancher(rect, Color("#cfad84"))
			_dessiner_plancher(Rect2(Vector2(piece["porte"] * CASE), Vector2(CASE, CASE)), Color("#ad8161"))
			_dessiner_mobilier(id, _centre(piece["poste"]))
		else:
			var porte := _centre(piece["porte"])
			draw_style_box(_bordure(Color("#513427"), Color("#8c6545"), 5), Rect2(porte - Vector2(25, 21), Vector2(50, 43)))
			draw_circle(porte + Vector2(13, 0), 4.0, Color("#d2a261"))
			for x in [-17, -5, 7]:
				draw_line(porte + Vector2(x, -15), porte + Vector2(x, 15), Color("#654431"), 2.0)

func _dessiner_mobilier(id: String, poste: Vector2) -> void:
	var meuble := poste + Vector2(0, -65)
	match id:
		"atelier":
			draw_texture_rect(TONNEAUX, Rect2(meuble + Vector2(-168, -32), Vector2(76, 76)), false)
			_dessiner_etabli(meuble)
		"cale":
			draw_texture_rect(COFFRE, Rect2(meuble - Vector2(52, 45), Vector2(104, 88)), false)
			draw_texture_rect(TONNEAUX, Rect2(meuble + Vector2(-151, -39), Vector2(78, 78)), false)
			draw_texture_rect(CAISSES, Rect2(meuble + Vector2(87, -39), Vector2(78, 78)), false)
		"cabine":
			draw_style_box(_bordure(Color("#514233"), Color("#a36d45"), 6), Rect2(meuble - Vector2(77, 26), Vector2(154, 52)))
			draw_rect(Rect2(meuble - Vector2(17, 13), Vector2(32, 23)), Color("#ead092"))
			draw_line(meuble - Vector2(1, 13), meuble + Vector2(-1, 10), Color("#8a6247"), 2.0)
			var trophee := Personnage.trophee_navire
			if Inventaire.dans_sac_ou_cale(trophee):
				draw_texture_rect(_icone_objet(trophee, TROPHEE), Rect2(meuble + Vector2(107, -48), Vector2(65, 65)), false)
		"cartes":
			draw_style_box(_bordure(Color("#986a3e"), Color("#63432d"), 5), Rect2(meuble - Vector2(85, 30), Vector2(170, 61)))
			draw_rect(Rect2(meuble - Vector2(71, 21), Vector2(142, 43)), Color("#e3c794"))
			draw_texture_rect(BOUSSOLE, Rect2(meuble - Vector2(22, 22), Vector2(44, 44)), false)

func _dessiner_etabli(meuble: Vector2) -> void:
	var metier := Personnage.metier_perso()
	var code := str(Personnage.professions().get(metier, {}).get("code", ""))
	var dessus := Color("#68422c")
	match code:
		"cook", "blacksmith":
			dessus = Color("#504a45")
		"medic":
			dessus = Color("#597b69")
	draw_style_box(_bordure(dessus, Color("#bd8b51"), 6), Rect2(meuble - Vector2(82, 24), Vector2(164, 50)))
	match code:
		"cook", "blacksmith":
			draw_circle(meuble + Vector2(-53, 0), 13, Color("#252328"))
			draw_circle(meuble + Vector2(-53, 0), 7, Color("#cb7948"))
		"carpenter":
			draw_rect(Rect2(meuble - Vector2(71, 7), Vector2(45, 13)), Color("#cf9d63"))
		"medic":
			draw_rect(Rect2(meuble - Vector2(66, 13), Vector2(35, 25)), Color("#e2d4b8"))
	var recettes := Personnage.recettes(metier) if not metier.is_empty() else []
	var icone := _icone_objet(str(recettes[0]["item_resultat"]), BOUSSOLE) if not recettes.is_empty() else BOUSSOLE
	draw_texture_rect(icone, Rect2(meuble - Vector2(28, 26), Vector2(56, 47)), false)

func _icone_objet(id: String, defaut: Texture2D) -> Texture2D:
	var icone := str(Inventaire.details_objet(id).get("chemin_icone", ""))
	return load(icone) as Texture2D if not icone.is_empty() and ResourceLoader.exists(icone) else defaut

func _dessiner_plancher(rect: Rect2, teinte: Color) -> void:
	for y in range(int(rect.position.y), int(rect.end.y), CASE):
		for x in range(int(rect.position.x), int(rect.end.x), CASE):
			var taille := Vector2(minf(CASE, rect.end.x - x), minf(CASE, rect.end.y - y))
			draw_texture_rect_region(BOIS, Rect2(Vector2(x, y), taille), Rect2(Vector2(128, 64), taille), teinte)

func _centre(case_sol: Vector2i) -> Vector2:
	return Vector2(case_sol * CASE) + Vector2.ONE * CASE * 0.5

func _bordure(fond: Color, ligne: Color, largeur: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fond
	style.border_color = ligne
	style.set_border_width_all(largeur)
	style.set_corner_radius_all(7)
	return style
