@tool
extends "res://scripts/world/terrain_alabasta.gd"

func _init() -> void:
	origine = Vector2(1536, 0)
	taille_monde = Vector2(3072, 1856)
	escaliers = [
		[Vector2(12.6, 15.8), 104, Vector2(14.8, 15.8), 48, 1.12],
		[Vector2(12.6, 9.5), 104, Vector2(14.8, 9.5), 48, 0.68],
		[Vector2(12.6, 21.2), 104, Vector2(14.8, 21.2), 48, 0.78],
		[Vector2(20.6, 16.3), 48, Vector2(22.8, 16.3), 0, 1.20],
		[Vector2(20.6, 10.8), 48, Vector2(22.8, 10.8), 0, 0.74],
		[Vector2(20.6, 21.6), 48, Vector2(22.8, 21.6), 0, 0.80],
	]
	quais = [
		[Vector2(28, 12), 0, Vector2(31, 12), -8, 0.52],
		[Vector2(28, 17), 0, Vector2(31, 17), -8, 0.52],
		[Vector2(28, 21), 0, Vector2(31, 21), -8, 0.52],
	]

# La côte tourne au pied du phare et se termine par une grève au sud.
func _bord_de_mer(u: int) -> int:
	if u <= 20:
		return 29 + roundi(1.5 * sin(u * 0.45))
	return 29 - maxi(0, u - 24)

func _carreaux_ajouter(cellule: Vector2i) -> void:
	var limite_quai := 28
	if cellule.y < 8:
		limite_quai -= ceili((8 - cellule.y) * 0.56)
	elif cellule.y > 22:
		limite_quai -= floori((cellule.y - 22) * 0.53)
	if cellule.x > limite_quai:
		return
	var hauteur := 104 if cellule.x <= 13 else (48 if cellule.x <= 21 else 0)
	var en_ville := cellule.y >= 6 and cellule.y <= 23 and cellule.x >= 3
	if en_ville:
		_carreaux[cellule] = Vector3i(hauteur, Sol.DALLAGE, Relief.VILLE)
		return
	var route := cellule.x < 3 and absi(cellule.y - 16) <= 1
	var arriere_pays := cellule.x < 2 or cellule.y < 4 or (cellule.y > 25 and cellule.x < 17)
	if arriere_pays and not route:
		var crete := sin(cellule.x * 0.30) + cos(cellule.y * 0.35)
		var dune := 92 if crete > 1.2 else 64
		_carreaux[cellule] = Vector3i(hauteur + dune, Sol.SABLE, Relief.MESA)
	else:
		_carreaux[cellule] = Vector3i(hauteur, Sol.PISTE if route else Sol.SABLE, Relief.SOL)
