extends "res://scripts/map.gd"

@export var fond_etiquette: StyleBox

@onready var _sentinelles: Array[Node] = [
	$Rencontres/SentinelleVestibule, $Rencontres/VeilleurVestibule,
	$Rencontres/SentinelleGalerie, $Rencontres/VeilleurGalerie,
]

func _enter_tree() -> void:
	super._enter_tree()
	# Un ancien point de reprise du temple souterrain peut tomber dans le ciel.
	if $TerrainZone.surface_sous($player.global_position).is_empty():
		$player.position = $Arrivees/DepuisSkypiea.position

func _ready() -> void:
	super._ready()
	for rencontre in $Rencontres.get_children():
		var etiquette := rencontre.get_node_or_null("EtiquetteMob") as Label
		if etiquette != null:
			etiquette.add_theme_stylebox_override("normal", fond_etiquette)
			etiquette.reset_size()
			etiquette.position.x = -etiquette.size.x * 0.5
			etiquette.position.y -= 5.0
	# Une reprise de sauvegarde dans la salle du trône doit laisser
	# le passage ouvert pour pouvoir revenir au vestibule.
	var surface: String = $TerrainZone.surface_sous($player.global_position)
	if surface == "S" or surface == "E":
		_ouvrir_sceau()

func _physics_process(_delta: float) -> void:
	if $CombatManager.en_combat:
		return
	for sentinelle in _sentinelles:
		if is_instance_valid(sentinelle) and int(sentinelle.get("pv")) > 0:
			return
	# Ce contrôle couvre aussi les victoires relayées par le serveur,
	# qui masquent les rencontres sans émettre leur signal local.
	_ouvrir_sceau()
	afficher_info_fushia("Les Dials se taisent. La salle du trône est ouverte.")

func _ouvrir_sceau() -> void:
	set_physics_process(false)
	$Sceau.hide()
	$TerrainZone.ouvrir_escalier($ground)
	$player._preparer_navigation()
