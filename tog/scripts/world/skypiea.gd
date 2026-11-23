extends "res://scripts/map.gd"

func _enter_tree() -> void:
	super._enter_tree()
	var sol: TileMapLayer = $ground
	var position_joueur: Vector2 = $player.position
	# Les sauvegardes de l'ancienne île peuvent placer le joueur hors des terrasses.
	if sol.get_cell_source_id(sol.local_to_map(sol.to_local(position_joueur))) == -1:
		$player.position = $Arrivees/DepuisAlabasta.position
