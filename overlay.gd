
extends Node2D

var cases_bleues: Array[Vector2i] = []
var cases_rouges: Array[Vector2i] = []

@onready var sol: TileMapLayer = get_tree().current_scene.get_node("ground")


func afficher(nouvelles: Array[Vector2i]) -> void:
	cases_bleues = nouvelles
	queue_redraw()


func afficher_sort(nouvelles: Array[Vector2i]) -> void:
	cases_rouges = nouvelles
	queue_redraw()


func effacer() -> void:
	cases_bleues.clear()
	cases_rouges.clear()
	queue_redraw()


func _draw() -> void:
	var taille: Vector2 = Vector2(sol.tile_set.tile_size)

	# Cases bleues : déplacement
	for c in cases_bleues:
		var pos: Vector2 = to_local(sol.to_global(sol.map_to_local(c))) - taille / 2
		draw_rect(Rect2(pos, taille), Color(0.2, 0.5, 1, 0.4))
		draw_rect(Rect2(pos, taille), Color(0.5, 0.8, 1, 0.8), false, 1.0)

	# Cases rouges : portée des sorts
	for c in cases_rouges:
		var pos: Vector2 = to_local(sol.to_global(sol.map_to_local(c))) - taille / 2
		draw_rect(Rect2(pos, taille), Color(1, 0.1, 0.1, 0.4))
		draw_rect(Rect2(pos, taille), Color(1, 0.4, 0.4, 0.9), false, 1.0)
