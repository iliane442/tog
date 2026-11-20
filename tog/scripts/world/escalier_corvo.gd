@tool
extends Node2D

const PROFONDEUR := 30.0
const TUILES := preload("res://assets/world/kit_cartes/sols.png")
const PIERRE := Color("#ac9c83")
const JOINT := Color("#3c403d")
const MOUSSE := Color("#747b4a")

@export_range(112.0, 256.0, 2.0) var largeur := 224.0:
	set(valeur):
		largeur = valeur
		queue_redraw()

@export_range(4, 14) var nombre_marches := 11:
	set(valeur):
		nombre_marches = valeur
		queue_redraw()

@export_range(-48.0, 48.0, 2.0) var decalage_bas := 0.0:
	set(valeur):
		decalage_bas = valeur
		queue_redraw()


func _draw() -> void:
	var hasard := RandomNumberGenerator.new()
	hasard.seed = roundi(largeur) * 31 + nombre_marches
	var demi_largeur := largeur * 0.5
	var longueur := nombre_marches * PROFONDEUR
	draw_colored_polygon(PackedVector2Array([
		Vector2(-demi_largeur - 6.0, -6.0),
		Vector2(demi_largeur + 5.0, -4.0),
		Vector2(decalage_bas * 0.42 + demi_largeur + 11.0, longueur * 0.42),
		Vector2(decalage_bas + demi_largeur + 9.0, longueur - 5.0),
		Vector2(decalage_bas + demi_largeur - 4.0, longueur + 7.0),
		Vector2(decalage_bas - demi_largeur + 3.0, longueur + 7.0),
		Vector2(decalage_bas - demi_largeur - 7.0, longueur - 9.0),
	]), Color(0.15, 0.17, 0.14, 0.42))

	# Les rangées aux extrémités sont des paliers pavés sans contremarches.
	for rang in range(-3, nombre_marches + 2):
		var marche := rang >= 0 and rang < nombre_marches
		var progression := clampf(float(rang) / float(nombre_marches - 1), 0.0, 1.0)
		var centre := snappedf(decalage_bas * progression, 2.0)
		var bord_gauche := centre - demi_largeur + 2.0 * hasard.randi_range(-2, 2)
		var bord_droit := centre + demi_largeur + 2.0 * hasard.randi_range(-2, 2)
		if rang == -3 or rang == nombre_marches + 1:
			bord_gauche += 14.0
			bord_droit -= 12.0
		var cadre := Rect2(bord_gauche, rang * PROFONDEUR, bord_droit - bord_gauche, PROFONDEUR)
		_dessiner_rangee(cadre, marche, hasard)


func _dessiner_rangee(cadre: Rect2, marche: bool, hasard: RandomNumberGenerator) -> void:
	var gauche := cadre.position.x
	var droite := cadre.end.x
	var haut := cadre.position.y
	var nez := cadre.end.y - (9.0 if marche else 2.0)
	if marche:
		draw_colored_polygon(PackedVector2Array([
			Vector2(gauche + 4.0, nez - 2.0), Vector2(droite - 3.0, nez - 2.0),
			Vector2(droite, nez + 2.0), Vector2(droite - 2.0, cadre.end.y - 1.0),
			Vector2(gauche + 5.0, cadre.end.y - 1.0), Vector2(gauche, nez + 2.0),
		]), JOINT)

	var nombre_dalles := maxi(3, roundi(cadre.size.x / 54.0))
	var debut := gauche + 2.0
	for dalle in range(nombre_dalles):
		var fin := lerpf(gauche, droite - 2.0, float(dalle + 1) / nombre_dalles)
		if dalle < nombre_dalles - 1:
			fin += 2.0 * hasard.randi_range(-5, 5)
		var pierre := PIERRE.lightened(hasard.randf_range(0.0, 0.13))
		pierre = pierre.darkened(hasard.randf_range(0.0, 0.19))
		_dessiner_dalle(debut, fin, haut, nez, pierre, marche, hasard)
		if marche:
			var contremarche := pierre.lerp(Color("#3b434b"), 0.58)
			draw_rect(Rect2(debut + 2.0, nez + 2.0, fin - debut - 3.0, 5.0), contremarche)
		debut = fin + 2.0

	if marche and hasard.randf() < 0.7:
		var cote := gauche + 3.0 if hasard.randf() < 0.5 else droite - 21.0
		draw_rect(Rect2(cote, haut + 6.0, 14.0, 6.0), MOUSSE)
		draw_rect(Rect2(cote + 4.0, haut + 4.0, 6.0, 4.0), MOUSSE.lightened(0.12))
		draw_rect(Rect2(cote + 12.0, haut + 10.0, 5.0, 3.0), MOUSSE.darkened(0.18))


func _dessiner_dalle(gauche: float, droite: float, haut: float, bas: float,
		pierre: Color, marche: bool, hasard: RandomNumberGenerator) -> void:
	var eclat := 2.0 * hasard.randi_range(1, 3)
	var contour := PackedVector2Array([
		Vector2(gauche, haut + eclat), Vector2(gauche + eclat, haut + 1.0),
		Vector2(droite - 5.0, haut + 1.0), Vector2(droite, haut + 5.0),
		Vector2(droite - 1.0, bas - 3.0), Vector2(droite - eclat, bas),
		Vector2(gauche + 4.0, bas), Vector2(gauche, bas - 4.0),
	])
	draw_colored_polygon(contour, pierre)

	# L'ardoise des marches et les pavés des paliers reprennent les sols de Fushia.
	var origine := Vector2(gauche, haut)
	var motif := Vector2(64.0 if marche else 0.0, 64.0)
	motif += Vector2(hasard.randi_range(1, 7), hasard.randi_range(1, 30))
	var uv := PackedVector2Array()
	for point in contour:
		uv.append((motif + (point - origine) * Vector2(0.65, 0.9)) / TUILES.get_size())
	draw_polygon(contour, PackedColorArray([Color(1.0, 0.98, 0.91, 0.55)]), uv, TUILES)
	if marche:
		var longueur_nez := (droite - gauche - 10.0) * hasard.randf_range(0.7, 1.0)
		draw_rect(Rect2(gauche + 5.0, bas - 3.0, longueur_nez, 2.0), pierre.lightened(0.18))
