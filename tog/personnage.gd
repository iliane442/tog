# personnage.gd — autoload : stats, race, classe et sorts du héros
extends Node

const CHEMIN_PERSO := "user://perso.cfg"

var nom: String = "Héros"
var niveau: int = 1
var xp: int = 0
var vie: int = 100
var vie_max: int = 100
var attaque: int = 0
var defense: int = 0
var vitesse: int = 0
var berry: int = 0  # monnaie du jeu
# points gagnés à chaque niveau, à répartir sur les caractéristiques
var points_statistique: int = 0
# répartition déjà effectuée (cle -> points dépensés), conservée par recalculer_stats
var points_depenses: Dictionary = {}

const POINTS_PAR_NIVEAU := 5

# Race et classe (ids des tables character_races / character_classes)
var race_id: String = "1"
var classe_id: String = "1"
var perso_cree := false

# Caractéristiques (style Dofus)
var caracteristiques: Dictionary = {
	"vitalite": 0,
	"sagesse": 0,
	"force": 0,
	"intelligence": 0,
	"chance": 0,
	"agilite": 0,
}

# Sorts connus (id -> infos) — remplis depuis la table `skills`
var sorts: Dictionary = {
	"tir_puissant": {"nom": "Tir puissant", "type": "attack", "degats": 12, "portee": 5, "recharge": 1, "description": "Inflige de gros dégâts à distance."},
	"soin_leger": {"nom": "Soin Mineur", "type": "heal", "degats": 0, "portee": 1, "recharge": 2, "description": "Restaure quelques points de vie."},
}

# Races et classes connues (id -> infos) — remplies depuis la base
var races: Dictionary = {
	"1": {"nom": "Humain", "description": "Race polyvalente sans bonus ni malus particuliers", "vie": 0},
}
var classes: Dictionary = {
	"1": {"nom": "Épéiste", "categorie": "combat", "description": "Maître de l'épée.", "vie": 0, "attaque": 0, "defense": 0, "sorts_initiaux": []},
}

signal caracteristiques_modifiees

func _ready() -> void:
	# sauvegarde automatique du perso à chaque changement de stats
	caracteristiques_modifiees.connect(_auto_sauvegarder)
	# les données viennent de la base SQLite ; les dictionnaires au-dessus
	# servent de repli si la base est indisponible
	if BaseDonnees.disponible:
		charger_depuis_base()
	charger_perso()

func charger_depuis_base() -> void:
	charger_sorts()
	charger_races()
	charger_classes()

func charger_sorts() -> void:
	sorts.clear()
	var lignes := BaseDonnees.lire(
		"SELECT id, name, description, base_damage, base_cooldown, type, range FROM skills;"
	)
	for ligne in lignes:
		sorts[str(ligne["id"])] = {
			"nom": ligne["name"],
			"type": ligne["type"],
			"degats": int(ligne["base_damage"]),
			"portee": int(ligne["range"]),
			"recharge": int(ligne["base_cooldown"]),
			"description": ligne["description"],
		}

func charger_races() -> void:
	races.clear()
	var lignes := BaseDonnees.lire(
		"SELECT id, display_name, description, base_health_bonus, base_attack_bonus, base_defense_bonus, base_speed_bonus, " +
		"base_strength_bonus, base_intelligence_bonus, base_agility_bonus, base_vitality_bonus, base_wisdom_bonus, base_luck_bonus " +
		"FROM character_races WHERE is_playable = 1;"
	)
	for ligne in lignes:
		races[str(ligne["id"])] = {
			"nom": ligne["display_name"],
			"description": ligne["description"],
			"vie": int(ligne["base_health_bonus"]),
			"attaque": int(ligne["base_attack_bonus"]),
			"defense": int(ligne["base_defense_bonus"]),
			"vitesse": int(ligne["base_speed_bonus"]),
			"force": int(ligne["base_strength_bonus"]),
			"intelligence": int(ligne["base_intelligence_bonus"]),
			"agilite": int(ligne["base_agility_bonus"]),
			"vitalite": int(ligne["base_vitality_bonus"]),
			"sagesse": int(ligne["base_wisdom_bonus"]),
			"chance": int(ligne["base_luck_bonus"]),
		}

func charger_classes() -> void:
	classes.clear()
	var lignes := BaseDonnees.lire(
		"SELECT id, display_name, description, category, starting_skills_json, base_health, base_attack, base_defense, base_speed, " +
		"base_strength, base_intelligence, base_agility, base_vitality, base_wisdom, base_luck " +
		"FROM character_classes WHERE is_active = 1;"
	)
	for ligne in lignes:
		classes[str(ligne["id"])] = {
			"nom": ligne["display_name"],
			"categorie": ligne["category"],
			"description": ligne["description"],
			"vie": int(ligne["base_health"]),
			"attaque": int(ligne["base_attack"]),
			"defense": int(ligne["base_defense"]),
			"vitesse": int(ligne["base_speed"]),
			"force": int(ligne["base_strength"]),
			"intelligence": int(ligne["base_intelligence"]),
			"agilite": int(ligne["base_agility"]),
			"vitalite": int(ligne["base_vitality"]),
			"sagesse": int(ligne["base_wisdom"]),
			"chance": int(ligne["base_luck"]),
			"sorts_initiaux": BaseDonnees.json_tableau(ligne["starting_skills_json"]),
		}

func nom_race() -> String:
	return races.get(race_id, {}).get("nom", race_id)

func nom_classe() -> String:
	return classes.get(classe_id, {}).get("nom", classe_id)

# Applique les bonus de la race et de la classe sur les stats de base,
# puis réapplique les points de caractéristiques dépensés
func recalculer_stats() -> void:
	vie_max = 100
	attaque = 0
	defense = 0
	vitesse = 0
	for cle in caracteristiques:
		caracteristiques[cle] = 0
	for donnees in [races.get(race_id, {}), classes.get(classe_id, {})]:
		vie_max += int(donnees.get("vie", 0))
		attaque += int(donnees.get("attaque", 0))
		defense += int(donnees.get("defense", 0))
		vitesse += int(donnees.get("vitesse", 0))
		for cle in caracteristiques:
			caracteristiques[cle] += int(donnees.get(cle, 0))
	for cle in points_depenses:
		var montant := int(points_depenses[cle])
		if cle == "vitalite":
			# 1 point de vitalité = 5 points de vie
			vie_max += 5 * montant
		elif caracteristiques.has(cle):
			caracteristiques[cle] += montant
	vie_max = maxi(vie_max, 1)
	# bonus de points de vie accumulés par les niveaux gagnés
	vie_max += 5 * maxi(niveau - 1, 0)
	vie = vie_max
	caracteristiques_modifiees.emit()

# Création définitive du personnage (depuis l'interface de création)
func creer(nouveau_nom: String, nouvelle_race: String, nouvelle_classe: String) -> void:
	nom = nouveau_nom
	race_id = nouvelle_race
	classe_id = nouvelle_classe
	niveau = 1
	xp = 0
	berry = 0
	points_statistique = 0
	points_depenses = {}
	recalculer_stats()
	_ecrire_fichier_perso()

func sauvegarder() -> void:
	_ecrire_fichier_perso()

# connecté à caracteristiques_modifiees : le perso existant se sauvegarde
# tout seul à chaque changement (XP, Berry, points, vie...)
func _auto_sauvegarder() -> void:
	if perso_cree:
		_ecrire_fichier_perso()

func _ecrire_fichier_perso() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("perso", "nom", nom)
	cfg.set_value("perso", "race", race_id)
	cfg.set_value("perso", "classe", classe_id)
	cfg.set_value("perso", "berry", berry)
	cfg.set_value("perso", "niveau", niveau)
	cfg.set_value("perso", "xp", xp)
	cfg.set_value("perso", "vie", vie)
	cfg.set_value("perso", "points_statistique", points_statistique)
	cfg.set_value("perso", "points_depenses", points_depenses)
	perso_cree = cfg.save(CHEMIN_PERSO) == OK

func charger_perso() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PERSO) != OK:
		return
	nom = str(cfg.get_value("perso", "nom", "Héros"))
	race_id = str(cfg.get_value("perso", "race", "1"))
	classe_id = str(cfg.get_value("perso", "classe", "1"))
	berry = int(cfg.get_value("perso", "berry", 0))
	points_statistique = int(cfg.get_value("perso", "points_statistique", 0))
	var depenses = cfg.get_value("perso", "points_depenses", {})
	if depenses is Dictionary:
		points_depenses = depenses
	niveau = int(cfg.get_value("perso", "niveau", 1))
	xp = int(cfg.get_value("perso", "xp", 0))
	recalculer_stats()
	vie = clampi(int(cfg.get_value("perso", "vie", vie_max)), 0, vie_max)
	perso_cree = true

func supprimer_perso() -> void:
	perso_cree = false
	nom = "Héros"
	race_id = "1"
	classe_id = "1"
	niveau = 1
	xp = 0
	berry = 0
	points_statistique = 0
	points_depenses = {}
	recalculer_stats()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_PERSO))

func xp_prochain_niveau() -> int:
	return niveau * 100

func gagner_xp(montant: int) -> void:
	xp += montant
	while xp >= xp_prochain_niveau():
		xp -= xp_prochain_niveau()
		niveau += 1
		vie_max += 5
		vie = vie_max
		points_statistique += POINTS_PAR_NIVEAU
	caracteristiques_modifiees.emit()

# Dépense un point de caractéristique ; renvoie true si réussi
func depenser_point(cle: String) -> bool:
	if points_statistique <= 0 or not caracteristiques.has(cle):
		return false
	points_statistique -= 1
	points_depenses[cle] = int(points_depenses.get(cle, 0)) + 1
	if cle == "vitalite":
		vie_max += 5
		vie += 5
	else:
		caracteristiques[cle] += 1
	caracteristiques_modifiees.emit()
	return true

# Applique une répartition validée (cle -> nombre de points) et sauvegarde
func appliquer_points(repartition: Dictionary) -> void:
	for cle in repartition:
		var montant := int(repartition[cle])
		if montant <= 0 or not caracteristiques.has(cle):
			continue
		montant = mini(montant, points_statistique)
		if montant <= 0:
			continue
		points_statistique -= montant
		points_depenses[cle] = int(points_depenses.get(cle, 0)) + montant
		if cle == "vitalite":
			vie_max += 5 * montant
			vie += 5 * montant
		else:
			caracteristiques[cle] += montant
	sauvegarder()
	caracteristiques_modifiees.emit()

func soigner(montant: int) -> void:
	vie = clampi(vie + montant, 0, vie_max)
	caracteristiques_modifiees.emit()

func ajouter_berry(montant: int) -> void:
	berry += montant
	caracteristiques_modifiees.emit()

func blesser(montant: int) -> void:
	vie = clampi(vie - montant, 0, vie_max)
	caracteristiques_modifiees.emit()
