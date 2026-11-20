# cartes_tresor.gd — autoload : croix de trésor posées sur la carte
#
# « Utiliser » une carte au trésor (items de sous-type carte_tresor)
# plante une croix sur la carte du monde, à une case de sol aléatoire,
# assez loin du joueur. Cliquer la croix décerne le trésor selon la
# rareté de la carte qui l'a dessinée :
#   1 : Berry + parfois un consommable commun
#   2 : Berry + une pièce d'équipement rare
#   3 : Berry + une pièce d'équipement épique
#   4 : Berry + une pièce d'équipement légendaire, avec une chance
#       sur mille d'y trouver un objet unique : un fruit du démon ou
#       une lame unique (introuvables ailleurs que dans les coffres)
#
# Les croix non fouillées survivent à la fermeture du jeu.
extends Node

signal croix_modifiees

const CHEMIN_ETAT := "user://cartes_tresor.cfg"
const SCRIPT_CROIX := preload("res://scripts/croix_tresor.gd")
const CARTE_DEPART := "res://scenes/fushia.tscn"

# distance minimale (en cases) entre le joueur et la croix : la chasse
# demande un peu de marche
const DISTANCE_MIN_CASES := 6
# trésor légendaire : chance d'un objet unique (fruit du démon ou lame)
const PROBA_UNIQUE := 0.001

# vrai quand le compte est connecté : les croix sont personnelles, la
# sauvegarde du perso vit sur le serveur ; le fichier local n'est plus
# lu ni écrit — il redevient la référence en repassant hors ligne
var en_ligne := false

# croix actives par scène : { "scene": String, "case_sol": Vector2i, "rarete": int }
var _croix: Array = []

func _ready() -> void:
	_charger()

func _charger() -> void:
	_croix = []
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_ETAT) != OK:
		return
	for donnees in cfg.get_value("cartes", "croix", []):
		if donnees is Dictionary:
			_croix.append({
				"scene": str(donnees.get("scene", CARTE_DEPART)),
				"case_sol": Vector2i(int(donnees.get("x", 0)), int(donnees.get("y", 0))),
				"rarete": clampi(int(donnees.get("rarete", 1)), 1, 4),
			})

func _sauver() -> void:
	# en ligne, la sauvegarde du perso vit sur le serveur : les croix le
	# suivent (voir croix_serialisables dans reseau.serialiser_perso) —
	# ne jamais polluer le fichier local (celui du mode hors ligne)
	if en_ligne:
		return
	var cfg := ConfigFile.new()
	var lu := []
	for croix in _croix:
		lu.append({
			"scene": croix["scene"],
			"x": int(croix["case_sol"].x),
			"y": int(croix["case_sol"].y),
			"rarete": int(croix["rarete"]),
		})
	cfg.set_value("cartes", "croix", lu)
	cfg.save(CHEMIN_ETAT)
	croix_modifiees.emit()

# persistance en ligne : les croix sont des données du perso, elles
# partent immédiatement avec lui sur le serveur
func _persister() -> void:
	if en_ligne:
		Reseau.sauvegarder_perso_immediat()
	else:
		_sauver()

# compte connecté : les croix locales vident la mémoire (pas le
# fichier) — le perso du serveur (et ses croix) suivent
func basculer_en_ligne() -> void:
	en_ligne = true
	_croix = []

# retour hors ligne : la sauvegarde locale redevient la référence
func recharger_etat_local() -> void:
	en_ligne = false
	_charger()
	croix_modifiees.emit()
	_redessiner_marqueurs_scene()

# croix en format sérialisable (texte/nombres) pour la sauvegarde
# serveur du perso : [{"scene", "x", "y", "rarete"}, ...]
func croix_serialisables() -> Array:
	var croix_sauvees: Array = []
	for croix in _croix:
		croix_sauvees.append({
			"scene": str(croix["scene"]),
			"x": int(croix["case_sol"].x),
			"y": int(croix["case_sol"].y),
			"rarete": int(croix["rarete"]),
		})
	return croix_sauvees

# croix reçues du serveur (reprisées de la sauvegarde du perso) :
# elles remplacent l'état en mémoire, les marqueurs suivent
func appliquer_croix_serveur(croix_recues: Variant) -> void:
	var liste: Array = croix_recues if croix_recues is Array else []
	_croix = []
	for croix in liste:
		if croix is Dictionary:
			_croix.append({
				"scene": str(croix.get("scene", CARTE_DEPART)),
				"case_sol": Vector2i(int(croix.get("x", 0)), int(croix.get("y", 0))),
				"rarete": clampi(int(croix.get("rarete", 1)), 1, 4),
			})
	_redessiner_marqueurs_scene()
	croix_modifiees.emit()

# retire les marqueurs de la scène courante puis redessine les croix
# connues de cette scène
func _redessiner_marqueurs_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for marqueur in get_tree().get_nodes_in_group("croix_tresor"):
		marqueur.queue_free()
	for croix in _croix:
		if croix["scene"] == scene.scene_file_path:
			scene.add_child(_creer_marqueur(croix["case_sol"], int(croix["rarete"])))

# croix actuellement plantées (copie de travail)
func croix_persistantes() -> Array:
	return _croix.duplicate(true)

# dessine sur la carte toutes les croix sauvegardées (appelé par la map
# à son chargement : les marqueurs ne survivent pas au changement de
# scène)
func dessiner_sur_carte() -> void:
	var scene := get_tree().current_scene
	var sol := _sol_de_scene(scene)
	if sol == null:
		return
	var deplacee := false
	for croix in _croix:
		if croix["scene"] != scene.scene_file_path:
			continue
		# Une ancienne sauvegarde peut viser le plateau fermé de Fushia.
		if sol.get_cell_source_id(croix["case_sol"]) == -1:
			var nouvelle_case = _case_aleatoire()
			if nouvelle_case == null:
				continue
			croix["case_sol"] = nouvelle_case
			deplacee = true
		if _marqueur_depuis_case(croix["case_sol"]) == null:
			scene.add_child(_creer_marqueur(croix["case_sol"], int(croix["rarete"])))
	if deplacee:
		_persister()

# « Utiliser » d'une carte : choisit une case et plante la croix —
# personnelle : elle fait partie de la chasse de ce joueur, les autres
# ne la voient pas (et ne peuvent pas en fouiller le trésor)
func creer_croix(niveau_tresor: int) -> bool:
	var scene := get_tree().current_scene
	var case_sol = _case_aleatoire()
	if case_sol == null:
		return false
	var rarete := clampi(niveau_tresor, 1, 4)
	_croix.append({"scene": scene.scene_file_path, "case_sol": case_sol, "rarete": rarete})
	_persister()
	scene.add_child(_creer_marqueur(case_sol, rarete))
	return true

# clic sur une croix : le trésor est décerné, la croix disparaît (de ce
# joueur uniquement — elle est personnelle)
func fouiller(case_sol: Vector2i) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for i in range(_croix.size()):
		if _croix[i]["scene"] == scene.scene_file_path and _croix[i]["case_sol"] == case_sol:
			var rarete := int(_croix[i]["rarete"])
			_croix.remove_at(i)
			_persister()
			var marqueur := _marqueur_depuis_case(case_sol)
			if marqueur != null:
				marqueur.queue_free()
			croix_modifiees.emit()
			_decerner_tresor(rarete)
			return

# tire et attribue le trésor du niveau donné, puis l'annonce
func _decerner_tresor(niveau: int) -> void:
	var gain := _tirer_tresor(niveau)
	if int(gain["berry"]) > 0:
		Personnage.ajouter_berry(int(gain["berry"]))
	for prise in gain["objets"]:
		Inventaire.ajouter_objet(str(prise["id"]), int(prise["qte"]))
	_annancer_tresor(int(gain["berry"]), gain["objets"])

# compose le trésor du niveau : Berry + objets selon la rareté
func _tirer_tresor(niveau: int) -> Dictionary:
	var gain := {"berry": _montant_berry(niveau), "objets": []}
	var prise: Dictionary = {}
	match niveau:
		1:
			if randf() < 0.65:
				prise = _tirer_item("consumable", [1, 5])
		2:
			prise = _tirer_item_equipement([2])
		3:
			prise = _tirer_item_equipement([3])
		4:
			# une chance sur mille de déterrer un objet unique : un fruit
			# du démon ou une lame unique ; sinon du légendaire classique
			if randf() < PROBA_UNIQUE:
				prise = _tirer_item_unique()
			if prise.is_empty():
				prise = _tirer_item_equipement([4])
	if not prise.is_empty():
		gain["objets"].append(prise)
	return gain

func _montant_berry(niveau: int) -> int:
	match niveau:
		1:
			return randi_range(300, 900)
		2:
			return randi_range(800, 2400)
		3:
			return randi_range(2200, 6000)
		_:
			return randi_range(6000, 15000)

# un équipement actif, droppable, des raretés données
func _tirer_item_equipement(raretes: Array) -> Dictionary:
	return _tirer_types("'arme', 'armure', 'accessoire'", raretes)

# un consommable actif, droppable, des raretés données
func _tirer_item(type_sql: String, raretes: Array) -> Dictionary:
	return _tirer_types("'%s'" % type_sql, raretes)

func _tirer_types(type_sql: String, raretes: Array) -> Dictionary:
	if not BaseDonnees.disponible:
		return {}
	var listee := PackedStringArray()
	for r in raretes:
		listee.append(str(int(r)))
	var lignes := BaseDonnees.lire(
		"SELECT id, type FROM items"
		+ " WHERE is_active = 1 AND is_droppable = 1 AND type IN (%s)" % type_sql
		+ " AND rarity_id IN (%s);" % ",".join(listee))
	if lignes.is_empty():
		return {}
	var ligne: Dictionary = lignes[randi() % lignes.size()]
	var qte := 1
	if Coffres.TYPES_EMPILABLES.has(str(ligne.get("type", ""))):
		qte = randi_range(1, 3)
	return {"id": str(ligne["id"]), "qte": qte}

# une lame unique non détenue, non enfermée dans un coffre du monde
# (un seul exemplaire de chaque lame par monde, comme les coffres)
func _tirer_lame_unique() -> Dictionary:
	return _tirer_unique(
		" WHERE type = 'arme' AND rarity_id = 6 AND is_active = 1"
		+ " AND id IN (SELECT item_id FROM unique_items WHERE is_consumed = 0);")

# un fruit du démon non consommé, non détenu, non enfermé dans un coffre
# (le fruit mangé par le perso n'existe plus que pour lui)
func _tirer_fruit_unique() -> Dictionary:
	return _tirer_unique(
		" WHERE type = 'fruit_demon' AND is_active = 1"
		+ " AND id NOT IN (SELECT item_id FROM unique_items WHERE is_consumed = 1);")

# id d'un objet unique encore libre (aucune requête => {})
func _tirer_unique(filtre: String) -> Dictionary:
	if not BaseDonnees.disponible:
		return {}
	var pris := Coffres.ids_en_coffres()
	var ids: Array[String] = []
	for ligne in BaseDonnees.lire("SELECT id FROM items" + filtre):
		var id := str(ligne["id"])
		if id == Personnage.fruit_id:
			continue
		if not Inventaire.objets.has(id) and not pris.has(id):
			ids.append(id)
	if ids.is_empty():
		return {}
	return {"id": ids[randi() % ids.size()], "qte": 1}

# l'objet unique du trésor légendaire : à pile ou face entre un fruit
# du démon et une lame unique, parmi les exemplaires encore libres ;
# renvoie {} si plus aucun n'est disponible
func _tirer_item_unique() -> Dictionary:
	var libres := []
	for prise in [_tirer_fruit_unique(), _tirer_lame_unique()]:
		if not (prise as Dictionary).is_empty():
			libres.append(prise)
	if libres.is_empty():
		return {}
	return libres[randi() % libres.size()]

# popup de fin de chasse : ce que la croix recélait
func _annancer_tresor(berry: int, objets: Array) -> void:
	var lignes := PackedStringArray()
	if berry > 0:
		lignes.append("%d Berry !" % berry)
	for prise in objets:
		lignes.append("%s x%d !" % [Inventaire.nom_objet(str(prise["id"])), int(prise["qte"])])
	if lignes.is_empty():
		lignes.append("Rien d'exploitable… mieux vaut creuser ailleurs.")
	var scene := get_tree().current_scene
	if scene == null:
		return
	var boite := AcceptDialog.new()
	boite.title = "Trésor déterré !"
	boite.dialog_text = "\n".join(lignes)
	scene.add_child(boite)
	boite.popup_centered()
	boite.visibility_changed.connect(func() -> void:
		if not boite.visible:
			boite.queue_free())

# un marqueur croix pour cette case (apparition immédiate ou au
# chargement de la map) ; la map est à l'origine, position monde = local
func _creer_marqueur(case_sol: Vector2i, rarete: int) -> Area2D:
	var croix := Area2D.new()
	croix.set_script(SCRIPT_CROIX)
	croix.set("case_sol", case_sol)
	croix.set("rarete", rarete)
	var sol := _sol_de_scene(get_tree().current_scene)
	if sol != null:
		croix.position = sol.map_to_local(case_sol)
	return croix

func _marqueur_depuis_case(case_sol: Vector2i) -> Area2D:
	for marqueur in get_tree().get_nodes_in_group("croix_tresor"):
		if marqueur is Area2D and marqueur.get("case_sol") == case_sol:
			return marqueur
	return null

# case de sol aléatoire, sans falaise, loin du joueur ; renvoie null si
# aucune case exploitable
func _case_aleatoire():
	var scene := get_tree().current_scene
	var sol := _sol_de_scene(scene)
	if sol == null:
		return null
	var cases := sol.get_used_cells()
	var falaises: TileMapLayer = null
	if scene != null:
		falaises = scene.get_node_or_null("cliffs") as TileMapLayer
	var joueur := get_tree().get_first_node_in_group("player")
	var case_joueur := Vector2i.ZERO
	var connait_joueur := false
	if joueur != null:
		case_joueur = sol.local_to_map(sol.to_local(joueur.global_position))
		connait_joueur = true
	var occupees := {}
	for croix in _croix:
		if croix["scene"] == scene.scene_file_path:
			occupees[croix["case_sol"]] = true
	cases.shuffle()
	var candidate = null
	for case_essai in cases:
		if falaises != null and falaises.get_cell_source_id(case_essai) != -1:
			continue
		if occupees.has(case_essai):
			continue
		candidate = case_essai
		if not connait_joueur or case_essai.distance_to(case_joueur) >= DISTANCE_MIN_CASES:
			break
	return candidate

func _sol_de_scene(scene) -> TileMapLayer:
	return null if scene == null else scene.get_node_or_null("ground") as TileMapLayer
