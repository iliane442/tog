extends "res://scripts/map.gd"

@export var emprise_sceau: Rect2i

@onready var _sentinelles: Array[Node] = [
	$Rencontres/SentinelleVestibule, $Rencontres/VeilleurVestibule,
	$Rencontres/SentinelleGalerie, $Rencontres/VeilleurGalerie,
]

func _enter_tree() -> void:
	var emprises: Array[Rect2i] = $TerrainZone.emprises_decors.duplicate()
	emprises.append(emprise_sceau)
	$TerrainZone.emprises_decors = emprises
	super._enter_tree()

func _ready() -> void:
	super._ready()
	# Une reprise de sauvegarde dans la salle du trône doit laisser
	# le passage ouvert pour pouvoir revenir au vestibule.
	if $player.ma_case().y <= emprise_sceau.position.y:
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
	for y in range(emprise_sceau.position.y, emprise_sceau.end.y):
		for x in range(emprise_sceau.position.x, emprise_sceau.end.x):
			var cellule := Vector2i(x, y)
			$cliffs.erase_cell(cellule)
			$ground.set_cell(cellule, 0, Vector2i.ZERO)
	$player._preparer_navigation()
