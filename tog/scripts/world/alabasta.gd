extends "res://scripts/map.gd"

const EAUX := preload("res://scripts/world/eaux_alabasta.gd")

func _enter_tree() -> void:
	var depart: Vector2 = $player.position
	super._enter_tree()
	# Une sauvegarde de l'ancienne carte peut pointer dans un décor ou dans la mer.
	var joueur: Node2D = $player
	var sol: TileMapLayer = $ground
	if sol.get_cell_source_id(sol.local_to_map(sol.to_local(joueur.position))) == -1:
		joueur.position = depart

func _ready() -> void:
	EAUX.animer_bassins($Paysage)
	if has_node("PuitsDuPlateau"):
		EAUX.animer_bassins($PuitsDuPlateau)
	super._ready()
