@tool
extends "res://scripts/world/terrain_alabasta.gd"

const TEXTURE_CANAL := preload(ASSETS_ALABASTA + "terrain/canal.png")
const VILLE := Rect2i(4, 5, 22, 20)
const TERRASSE_CASINO := Rect2i(8, 5, 9, 7)
const CANAUX := [Rect2i(8, 19, 16, 2), Rect2i(22, 21, 2, 4)]
const NIVEAU_CANAL := -36
const MURS_ENTREE := [Vector2(5.35, 13.36), Vector2(16.51, 24.8)]
const AXE_PORTE := 4.2

func _init() -> void:
	origine = Vector2(1536, -24)
	taille_monde = Vector2(3072, 1856)
	quais = []
	escaliers = [
		[Vector2(12.5, 10.7), 70, Vector2(12.5, 13.0), 0, 1.42],
		[Vector2(15.8, 10.7), 70, Vector2(15.8, 12.7), 0, 0.70],
	]
	ponts = [
		[Vector2(10.8, 18.2), 0, Vector2(10.8, 21.8), 0, 0.69],
		[Vector2(17, 18.2), 0, Vector2(17, 21.8), 0, 0.80],
		[Vector2(21.1, 22.9), 0, Vector2(24.8, 22.9), 0, 0.67],
	]

func _ready() -> void:
	_preparer_dalles()
	var materiau := ShaderMaterial.new()
	materiau.shader = SHADER_MER
	materiau.set_shader_parameter("mer", TEXTURE_CANAL)
	materiau.set_shader_parameter("dimensions", TEXTURE_CANAL.get_size())
	materiau.set_shader_parameter("origine", origine - Vector2(0, DEMI_TUILE.y))
	for canal: Rect2i in CANAUX:
		var a := Vector2(canal.position) - Vector2(0.5, 0.5)
		var b := Vector2(canal.end) - Vector2(0.5, 0.5)
		var eau := Polygon2D.new()
		eau.polygon = PackedVector2Array([
			_projeter(a, NIVEAU_CANAL), _projeter(Vector2(b.x, a.y), NIVEAU_CANAL),
			_projeter(b, NIVEAU_CANAL), _projeter(Vector2(a.x, b.y), NIVEAU_CANAL),
		])
		eau.uv = eau.polygon
		eau.texture = TEXTURE_CANAL
		eau.material = materiau
		eau.z_index = -1
		add_child(eau)
	queue_redraw()

func _bord_de_mer(_u: int) -> int:
	return 61

func _carreaux_ajouter(cellule: Vector2i) -> void:
	for canal: Rect2i in CANAUX:
		if canal.has_point(cellule):
			_carreaux[cellule] = Vector3i(NIVEAU_CANAL, Sol.CANAL, Relief.SOL)
			return
	if TERRASSE_CASINO.has_point(cellule):
		_carreaux[cellule] = Vector3i(70, Sol.DALLAGE, Relief.VILLE)
	elif VILLE.has_point(cellule):
		_carreaux[cellule] = Vector3i(0, Sol.DALLAGE, Relief.VILLE)
	else:
		var route := cellule.x < 4 and absi(cellule.y - 15) <= 1
		var dune := absi(cellule.x - 14) > 13 or absi(cellule.y - 15) > 12
		var relief := sin(cellule.x * 0.25 + cellule.y * 0.19)
		var hauteur := 80 if relief > 0.45 else 60
		if dune and not route:
			_carreaux[cellule] = Vector3i(hauteur, Sol.SABLE, Relief.MESA)
		else:
			_carreaux[cellule] = Vector3i(0, Sol.PISTE if route else Sol.SABLE, Relief.SOL)

func _draw() -> void:
	super._draw()
	for pont in ponts:
		_dessiner_pont(pont)
	for mur: Vector2 in MURS_ENTREE:
		_dessiner_mur(mur)

func _dessiner_mur(limites: Vector2) -> void:
	var hauteur := 75
	var devant := AXE_PORTE + 0.09
	var arriere := AXE_PORTE - 0.13
	var a := _projeter(Vector2(devant, limites.y), hauteur)
	var b := _projeter(Vector2(devant, limites.x), hauteur)
	var c := _projeter(Vector2(arriere, limites.x), hauteur)
	var d := _projeter(Vector2(arriere, limites.y), hauteur)
	var pied := Vector2.DOWN * hauteur
	_dessiner_paroi(PackedVector2Array([d, a, a + pied, d + pied]), 2, true, hauteur)
	_dessiner_paroi(PackedVector2Array([a, b, b + pied, a + pied]), 1, true, hauteur)
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color("#f1c58c"))
	draw_line(a, b, Color("#ffdda8"), 4.0)
	for v in range(ceili(limites.x * 2.0), floori(limites.y * 2.0)):
		var centre := float(v) * 0.5 + 0.23
		var avant := _projeter(Vector2(devant, centre - 0.13), hauteur)
		var apres := _projeter(Vector2(devant, centre + 0.13), hauteur)
		var haut := Vector2(0, -12)
		var profondeur := _projeter(Vector2(arriere - devant, 0), 0) - origine
		draw_colored_polygon(PackedVector2Array([avant + haut, apres + haut, apres + haut + profondeur, avant + haut + profondeur]), Color("#ffe2ab"))
		draw_colored_polygon(PackedVector2Array([avant + haut, apres + haut, apres, avant]), Color("#d3a16e"))
		draw_colored_polygon(PackedVector2Array([apres + haut, apres + haut + profondeur, apres + profondeur, apres]), Color("#b78757"))

func _dessiner_pont(pont: Array) -> void:
	var bords := _extremites(pont, float(pont[4]) + 0.13)
	var tablier := Vector2(0, 13)
	_dessiner_paroi(PackedVector2Array([bords[1], bords[3], bords[3] + tablier, bords[1] + tablier]), 2, true, 0)
	_dessiner_paroi(PackedVector2Array([bords[2], bords[3], bords[3] + tablier, bords[2] + tablier]), 1, true, 0)
	var pente := Vector2(pont[2]) - Vector2(pont[0])
	var longueur := pente.length()
	var largeur := (float(pont[4]) + 0.13) * 2.0
	draw_polygon(PackedVector2Array([bords[0], bords[1], bords[3], bords[2]]),
		PackedColorArray([Color.WHITE]), PackedVector2Array([
			Vector2.ZERO, Vector2(largeur, 0), Vector2(largeur, longueur), Vector2(0, longueur),
		]), DALLAGE)
	for cote in 2:
		var debut := bords[cote]
		var fin := bords[cote + 2]
		var dessus := Vector2(0, -14)
		_dessiner_paroi(PackedVector2Array([debut + dessus, fin + dessus, fin, debut]), 2, true, 14)
		draw_line(debut + dessus, fin + dessus, Color("#ffe0a0"), 5.0)
		for proportion in [0.0, 0.33, 0.66, 1.0]:
			var base := debut.lerp(fin, proportion)
			draw_line(base, base + Vector2(0, -24), Color("#aa7547"), 11.0)
			draw_line(base + Vector2(-2, -2), base + Vector2(-2, -24), Color("#f4ce94"), 5.0)
