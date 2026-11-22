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
# objets équipés (emplacement -> id d'item) : un par emplacement porté
# arme = arme principale (en accord avec la classe), arme2 = arme
# secondaire (sans restriction)
var equipement: Dictionary = {
	"arme": "", "arme2": "", "corps": "", "tête": "", "visage": "", "cou": "",
	"main": "", "cape": "", "ceinture": "", "pantalon": "", "pieds": "",
	"anneau1": "", "anneau2": "",
}
# métiers appris (id de profession -> {"niveau": int, "xp": int})
var metiers: Dictionary = {}
# pièces installées sur le navire (emplacement -> id d'item) : un
# seul exemplaire par emplacement, l'ancienne pièce rejoint
# l'inventaire quand une nouvelle prend sa place
var bateau: Dictionary = {
	"planche": "", "gouvernail": "", "mat": "", "coque": "", "proue": "",
}
# vocabulaire des pièces installables : mot-clé du nom de l'item -> emplacement
const EMPLACEMENTS_NAVIRE := {
	"Planche renforcée": "planche",
	"Gouvernail": "gouvernail",
	"Mât": "mat",
	"Module de coque": "coque",
	"Figure de proue": "proue",
}

const POINTS_PAR_NIVEAU := 5
const EFFET_REATTRIBUTION := "reset_stats"
# tablette des Flots Calmes : gains du prochain combat doublés
const EFFET_DOUBLE_COMBAT := "prochain_combat_double"

# la bénédiction de la tablette attend le prochain combat gagné :
# XP et Berry versés par les victoires y seront doublés
var prochain_combat_double := false

# impacts des points de caractéristiques (la vitalité donne +5 PV par
# point, cf. recalculer_stats / depenser_point) ; la caractéristique
# « chance » s'affiche « Précision » et « agilite » s'affiche « Vitesse »
# (les clés restent celles de la base et du fichier de sauvegarde)
const DEGATS_PAR_FORCE := 1.0  # tout sort d'attaque
const SOIN_PAR_INTELLIGENCE := 1.0  # sorts de type heal
const BONUS_XP_PAR_SAGESSE := 0.02  # +2% d'XP par point de sagesse
const PRECISION_PAR_CHANCE := 0.01  # +1% de toucher par point de « Précision »
const ESQUIVE_PAR_AGILITE := 0.01  # -1% de précision aux attaques ennemies
const CHANCE_PM_PAR_AGILITE := 0.01  # chance de +1 PM au début du tour (max 50%)
const FUITE_BASE := 0.5  # chance de fuite de base en combat PvE
const FUITE_PAR_AGILITE := 0.03  # bonus de fuite par point d'agilité
const FUITE_MAX := 0.95  # une fuite n'est jamais certaine
const INITIATIVE_BASE := 0.5  # probabilité de base de commencer le combat
const INITIATIVE_PAR_AGILITE := 0.01  # +1% par point de « Vitesse »

# Race et classe (ids des tables character_races / character_classes)
var race_id: String = "1"
var classe_id: String = "12"
# remplacement des classes supprimées du jeu (seeds_classes_nettoyage) :
# une sauvegarde antérieure qui les portait bascule sur la classe la
# plus proche ; défaut : Sabreur
const CLASSES_REMPLACEMENT := {
	"1": "12",  # Épéiste -> Sabreur
	"2": "13",  # Archer -> Tireur
	"3": "14",  # Canonnier -> Combattant
	"4": "12",  # Samouraï -> Sabreur
	"6": "5",   # Infirmière -> Médecin
	"8": "14",  # Timonier -> Combattant
}
var sexe: String = "M"
const VALEURS_SEXES_VALIDES: Array[String] = ["M", "F"]
const APPARENCE_HUMAINE_DEFAUT := "fushia"
const APPARENCES_HUMAINES := {
	"fushia": {"nom": "Aventuriers de Fushia", "M": "humain_pirate", "F": "humaine_pirate"},
	"loguetown": {"nom": "Contrebandiers de Loguetown", "M": "humain_loguetown", "F": "humaine_loguetown"},
	"large": {"nom": "Duellistes du large", "M": "humain_duelliste", "F": "humaine_duelliste"},
}
const VISUELS_AUTRES_RACES := {
	"mink": {"M": "mink_pirate", "F": "mink_pirate_f"},
	"fishman": {"M": "fishman_pirate", "F": "femme_poisson_pirate"},
	"giant": {"M": "geant_pirate", "F": "geante_pirate"},
}
var apparence_humaine := APPARENCE_HUMAINE_DEFAUT
var perso_cree := false
# vrai quand le perso vit sur le serveur (compte connecté) : chaque
# sauvegarde part immédiatement au serveur et le fichier local
# perso.cfg n'est plus lu ni écrit (il ne sert qu'en mode hors ligne)
var en_ligne := false

# Caractéristiques (style Dofus)
var caracteristiques: Dictionary = {
	"vitalite": 0,
	"sagesse": 0,
	"force": 0,
	"intelligence": 0,
	"chance": 0,
	"agilite": 0,
	# réductrice : chaque point absorbe une part croissante des dégâts
	# reçus (dégâts x 100 / (100 + défense), comme une armure)
	"defense": 0,
}

# Barre de sorts du joueur : ids des sorts placés dans les emplacements
# (dans l'ordre) ; seuls les sorts de la classe peuvent y figurer.
# Utilisée par les combats ; composée dans l'onglet Sorts du menu.
const TAILLE_BARRE_SORTS := 10
var barre_sorts: Array[String] = []

# barre d'objets : ids d'items consommables placés par le joueur (dans
# l'ordre) ; seuls les consommables possédés peuvent y figurer, les
# emplacements se vident quand la quantité tombe à zéro
const TAILLE_BARRE_OBJETS := 10
var barre_objets: Array[String] = []

# Fruit du démon mangé (id de l'item, table `items`) ; "" si aucun.
# Manger un fruit est définitif : un seul fruit par personnage.
var fruit_id := ""

# Expérience du fruit mangé : un pouvoir du fruit lancé avec succès en
# combat vaut 1 point. Le niveau du fruit suit (XP_FRUIT_PAR_PALIER x
# n x (n+1) / 2 points pour atteindre le niveau n) : niveau 1 à 100
# lancements, 2 à 300, 3 à 600, 4 (éveil) à 1000 — les pouvoirs se
# débloquent par niveau de fruit, pas par niveau de personnage.
var fruit_xp := 0
# multiplicateur du seuil d'expérience du fruit, ajustable pour la
# progression voulue (100 -> éveil après 1000 lancements)
const XP_FRUIT_PAR_PALIER := 100
# pouvoirs du fruit qui ne sont pas des sorts : capacités hors barre
# et hors combat, lancées depuis l'onglet du fruit (Greffe de Vie)
const POUVOIRS_FRUIT_MENU: Array[String] = ["250"]

# Buffs temporaires des consommables utilisés : [{id: str, effets: {},
# expire: float}] ; expire = temps unix ; les buffs échus sont purgés
# à chaque recalcul de stats.
var buffs: Array = []

# Sorts connus (id -> infos) — remplis depuis la table `skills`
var sorts: Dictionary = {
	"tir_puissant": {"nom": "Tir puissant", "type": "attack", "degats": 12, "portee": 5, "recharge": 1, "description": "Inflige de gros dégâts à distance."},
	"soin_leger": {"nom": "Soin Mineur", "type": "heal", "degats": 0, "portee": 1, "recharge": 2, "description": "Restaure quelques points de vie."},
}
var etats: Dictionary = {}

# Races et classes connues (id -> infos) — remplies depuis la base
var races: Dictionary = {
	"1": {"nom": "Humain", "description": "Race polyvalente sans bonus ni malus particuliers", "vie": 0},
}
var classes: Dictionary = {
	"12": {"nom": "Sabreur", "categorie": "combat", "description": "Bretteur au sabre.", "vie": 0, "attaque": 0, "defense": 0, "sorts_initiaux": []},
}

signal caracteristiques_modifiees
signal metiers_modifies
signal barre_sorts_modifiee
signal barre_objets_modifiee

func _ready() -> void:
	# sauvegarde automatique du perso à chaque changement de stats
	caracteristiques_modifiees.connect(_auto_sauvegarder)
	metiers_modifies.connect(_auto_sauvegarder)
	# inventaire : un consommable vendu ou consommé jusqu'à la dernière
	# unité quitte la barre d'objets
	Inventaire.inventaire_modifie.connect(filtrer_barre_objets)
	# les données viennent de la base SQLite ; les dictionnaires au-dessus
	# servent de repli si la base est indisponible
	if BaseDonnees.disponible:
		charger_depuis_base()
		charger_donnees_metiers()
	charger_perso()

func charger_depuis_base() -> void:
	charger_sorts()
	charger_races()
	charger_classes()

func charger_sorts() -> void:
	sorts.clear()
	etats.clear()
	for ligne in BaseDonnees.lire("SELECT id, name, description, effect_type, is_stackable, max_stacks FROM status_effects;"):
		etats[int(ligne["id"])] = {
			"nom": str(ligne["name"]),
			"description": str(ligne["description"]),
			"type": str(ligne["effect_type"]),
			"empilable": int(ligne["is_stackable"]) == 1,
			"max_stacks": maxi(int(ligne["max_stacks"]), 1),
		}
	var lignes := BaseDonnees.lire(
		"SELECT id, name, description, base_damage, base_cooldown, type, range FROM skills ORDER BY id;"
	)
	for ligne in lignes:
		var effets: Array[Dictionary] = []
		for effet in BaseDonnees.lire(
			"SELECT status_effect_id, chance, duration, value FROM skill_status_effects WHERE skill_id = %d;" % int(ligne["id"])
		):
			effets.append({
				"id": int(effet["status_effect_id"]),
				"chance": float(effet["chance"]),
				"duree": int(effet["duration"]),
				"valeur": float(effet["value"]),
			})
		sorts[str(ligne["id"])] = {
			"id": int(ligne["id"]),
			"nom": ligne["name"],
			"type": ligne["type"],
			"degats": int(ligne["base_damage"]),
			"portee": int(ligne["range"]),
			"cout_pa": maxi(int(ligne["base_cooldown"]), 1),
			"recharge": int(ligne["base_cooldown"]),
			"description": ligne["description"],
			"effets": effets,
		}

func charger_races() -> void:
	races.clear()
	var lignes := BaseDonnees.lire(
		"SELECT id, name, display_name, description, base_health_bonus, base_attack_bonus, base_defense_bonus, base_speed_bonus, " +
		"base_strength_bonus, base_intelligence_bonus, base_agility_bonus, base_vitality_bonus, base_wisdom_bonus, base_luck_bonus " +
		"FROM character_races WHERE is_playable = 1;"
	)
	for ligne in lignes:
		races[str(ligne["id"])] = {
			"id_technique": ligne["name"],
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

func a_une_apparence_humaine(id_race: String) -> bool:
	return str(races.get(id_race, {}).get("id_technique", "human")) == "human"

func normaliser_apparence_humaine(id_race: String, apparence: String) -> String:
	if a_une_apparence_humaine(id_race) and APPARENCES_HUMAINES.has(apparence):
		return apparence
	return APPARENCE_HUMAINE_DEFAUT

func prefixe_visuel(id_race: String, variante_sexe: String, apparence: String) -> String:
	var id_technique := str(races.get(id_race, {}).get("id_technique", "human"))
	var cle_sexe := "F" if variante_sexe == "F" else "M"
	if id_technique == "human":
		return APPARENCES_HUMAINES[normaliser_apparence_humaine(id_race, apparence)][cle_sexe]
	return VISUELS_AUTRES_RACES.get(id_technique, {}).get(cle_sexe, "humain_pirate")

func choisir_apparence_humaine(apparence: String) -> void:
	var choix := normaliser_apparence_humaine(race_id, apparence)
	if choix == apparence_humaine:
		return
	apparence_humaine = choix
	sauvegarder()

func portrait_visuel(prefixe: String) -> AtlasTexture:
	var chemin := "res://assets/sprites/%s/%s_idle.png" % [prefixe, prefixe]
	if not ResourceLoader.exists(chemin):
		return null
	var planche := load(chemin) as Texture2D
	var portrait := AtlasTexture.new()
	portrait.atlas = planche
	portrait.region = Rect2(Vector2.ZERO, planche.get_size() / Vector2(4.0, 4.0))
	portrait.filter_clip = true
	return portrait

func nom_classe() -> String:
	return classes.get(classe_id, {}).get("nom", classe_id)

# ids des sorts de la classe du personnage (uniquement ceux connus) :
# les sorts de base (starting_skills_json) plus ceux débloqués au niveau
# actuel (table class_skills)
func sorts_de_classe() -> Array[String]:
	var ids: Array[String] = []
	for id_sort in classes.get(classe_id, {}).get("sorts_initiaux", []):
		var id := str(id_sort)
		if sorts.has(id) and not ids.has(id):
			ids.append(id)
	# sorts de classe débloqués par le niveau, du plus tôt au plus tard
	if BaseDonnees.disponible and classe_id.is_valid_int():
		for ligne in BaseDonnees.lire(
			("SELECT skill_id FROM class_skills"
			+ " WHERE class_id = %d AND unlock_level <= %d"
			+ " ORDER BY unlock_level;") % [classe_id.to_int(), niveau]):
			var sort_debloque := str(ligne["skill_id"])
			if sorts.has(sort_debloque) and not ids.has(sort_debloque):
				ids.append(sort_debloque)
	return ids

# sorts de la classe pas encore débloqués (table class_skills), du plus
# tôt au plus tard : [{"id": String, "niveau": int}]
func sorts_de_classe_verrouilles() -> Array[Dictionary]:
	var verrouilles: Array[Dictionary] = []
	var connus := sorts_de_classe()
	if not BaseDonnees.disponible or not classe_id.is_valid_int():
		return verrouilles
	for ligne in BaseDonnees.lire(
		("SELECT skill_id, unlock_level FROM class_skills"
		+ " WHERE class_id = %d AND unlock_level > %d"
		+ " ORDER BY unlock_level;") % [classe_id.to_int(), niveau]):
		var id := str(ligne["skill_id"])
		if sorts.has(id) and not connus.has(id):
			connus.append(id)
			verrouilles.append({"id": id, "niveau": int(ligne["unlock_level"])})
	return verrouilles

# niveau actuel du fruit mangé (0 tant qu'il n'a pas été utilisé)
func niveau_fruit() -> int:
	var niveau := 0
	while fruit_xp >= XP_FRUIT_PAR_PALIER * (niveau + 1) * (niveau + 2) / 2:
		niveau += 1
	return niveau

# nom commercial du fruit mangé (table des items) ; vide sans fruit
func nom_fruit() -> String:
	if fruit_id == "" or not fruit_id.is_valid_int() or not BaseDonnees.disponible:
		return ""
	var lignes := BaseDonnees.lire("SELECT name FROM items WHERE id = %d;" % fruit_id.to_int())
	if lignes.is_empty():
		return ""
	return str(lignes[0]["name"])

# seuil cumulé d'XP qu'un niveau de fruit exige (montée en niveau de
# niveau_fruit) : le niveau 0 ne demande rien, le niveau 1 demande
# XP_FRUIT_PAR_PALIER, le 2 en exige le triple cumulé, etc.
func seuil_xp_fruit(niveau: int) -> int:
	return XP_FRUIT_PAR_PALIER * niveau * (niveau + 1) / 2

# ids des pouvoirs du fruit du démon mangé (table `fruit_skills`)
# débloqués au niveau de fruit donné
func _sorts_fruit_niveau(niveau: int) -> Array[String]:
	var ids: Array[String] = []
	if fruit_id == "" or not fruit_id.is_valid_int() or not BaseDonnees.disponible:
		return ids
	for ligne in BaseDonnees.lire(
		("SELECT skill_id FROM fruit_skills"
		+ " WHERE fruit_item_id = %d AND unlock_level <= %d"
		+ " ORDER BY unlock_level;") % [fruit_id.to_int(), niveau]):
		var id := str(ligne["skill_id"])
		if sorts.has(id):
			ids.append(id)
	return ids

# pouvoirs du fruit débloqués à son niveau actuel (4 sorts + 1 éveil),
# hors ceux du menu : les sorts de combat seuls peuplent la barre
func sorts_fruit() -> Array[String]:
	var ids: Array[String] = []
	for id in _sorts_fruit_niveau(niveau_fruit()):
		if not POUVOIRS_FRUIT_MENU.has(id):
			ids.append(id)
	return ids

# pouvoirs de menu du fruit mangé, débloqués à son niveau actuel : ils
# vivent dans l'onglet Fruit du démon, jamais sur la barre de sorts
func pouvoirs_fruit_menu() -> Array[String]:
	var ids: Array[String] = []
	for id in _sorts_fruit_niveau(niveau_fruit()):
		if POUVOIRS_FRUIT_MENU.has(id):
			ids.append(id)
	return ids

# pouvoirs du fruit mangé pas encore débloqués, du plus tôt au plus
# tard : [{"id": String, "niveau": int}]
func sorts_fruit_verrouilles() -> Array[Dictionary]:
	var verrouilles: Array[Dictionary] = []
	if fruit_id == "" or not fruit_id.is_valid_int() or not BaseDonnees.disponible:
		return verrouilles
	for ligne in BaseDonnees.lire(
		("SELECT skill_id, unlock_level FROM fruit_skills"
		+ " WHERE fruit_item_id = %d AND unlock_level > %d"
		+ " ORDER BY unlock_level;") % [fruit_id.to_int(), niveau_fruit()]):
		var id := str(ligne["skill_id"])
		if sorts.has(id):
			verrouilles.append({"id": id, "niveau": int(ligne["unlock_level"])})
	return verrouilles

# true si ce sort est l'un des pouvoirs du fruit mangé (peu importe
# s'il est déjà débloqué)
func sort_est_du_fruit(id_sort: String) -> bool:
	if fruit_id == "" or not fruit_id.is_valid_int() or not BaseDonnees.disponible:
		return false
	if not id_sort.is_valid_int():
		return false
	return not BaseDonnees.lire(
		"SELECT skill_id FROM fruit_skills WHERE fruit_item_id = %d AND skill_id = %d;"
		% [fruit_id.to_int(), id_sort.to_int()]).is_empty()

# Un pouvoir du fruit vient d'être lancé en combat : le fruit gagne de
# l'expérience et franchit parfois un niveau — les pouvoirs fraîchement
# débloqués sont auto-placés dans la barre s'il reste de la place.
# Renvoie la liste des sorts débloqués par ce lancement.
func utiliser_pouvoir_fruit(id_sort: String) -> Array[String]:
	var debloques: Array[String] = []
	if not sort_est_du_fruit(id_sort):
		return debloques
	var niveau_avant := niveau_fruit()
	fruit_xp += 1
	var niveau_apres := niveau_fruit()
	if niveau_apres > niveau_avant:
		var connus := {}
		for id in _sorts_fruit_niveau(niveau_avant):
			connus[id] = true
		for id in _sorts_fruit_niveau(niveau_apres):
			if not connus.has(id):
				debloques.append(id)
				if not sort_dans_barre(id) and not barre_sorts_pleine():
					barre_sorts.append(id)
		caracteristiques_modifiees.emit()
	sauvegarder()
	if not debloques.is_empty():
		barre_sorts_modifiee.emit()
	return debloques

# sorts plaçables dans la barre de combat : ceux de la classe, plus
# les pouvoirs du fruit mangé
func sorts_disponibles() -> Array[String]:
	var ids := sorts_de_classe()
	for id in sorts_fruit():
		if not ids.has(id):
			ids.append(id)
	return ids

func sort_dans_barre(id: String) -> bool:
	return id in barre_sorts

func barre_sorts_pleine() -> bool:
	return barre_sorts.size() >= TAILLE_BARRE_SORTS

# place un sort disponible (classe ou fruit mangé) dans le premier
# emplacement libre de la barre de combat ; renvoie false si le sort
# n'est pas disponible ou si la barre est déjà pleine
func ajouter_sort_barre(id: String) -> bool:
	if not sorts_disponibles().has(id) or sort_dans_barre(id) or barre_sorts_pleine():
		return false
	barre_sorts.append(id)
	sauvegarder()
	barre_sorts_modifiee.emit()
	return true

# retire un sort de la barre de combat ; l'ordre des autres sorts est
# conservé (rien ne se passe s'il n'y figure pas)
func retirer_sort_barre(id: String) -> void:
	if barre_sorts.has(id):
		barre_sorts.erase(id)
		sauvegarder()
		barre_sorts_modifiee.emit()

# garde en barre uniquement les sorts disponibles (classe + fruit mangé)
func _filtrer_barre_sorts() -> void:
	for id_sort in barre_sorts.duplicate():
		if not sorts_disponibles().has(id_sort):
			barre_sorts.erase(id_sort)

# --- barre d'objets (consommables) ---

func objet_dans_barre(id: String) -> bool:
	return id in barre_objets

func barre_objets_pleine() -> bool:
	return barre_objets.size() >= TAILLE_BARRE_OBJETS

# place un consommable possédé dans le premier emplacement libre de
# la barre d'objets ; renvoie false si l'objet ne s'y prête pas (pas
# consommable, pas possédé, déjà placé ou barre pleine)
func ajouter_objet_barre(id: String) -> bool:
	if int(Inventaire.objets.get(id, 0)) <= 0:
		return false
	if str(Inventaire.details_objet(id).get("type", "")) != "consumable":
		return false
	if objet_dans_barre(id) or barre_objets_pleine():
		return false
	barre_objets.append(id)
	sauvegarder()
	barre_objets_modifiee.emit()
	return true

# retire un consommable de la barre d'objets (rien ne se passe s'il
# n'y figure pas)
func retirer_objet_barre(id: String) -> void:
	if barre_objets.has(id):
		barre_objets.erase(id)
		sauvegarder()
		barre_objets_modifiee.emit()

# garde en barre uniquement les consommables encore possédés : vendus,
# consommés jusqu'à la dernière unité ou perdus, un emplacement se
# vide ; les autres quantités rafraîchissent l'affichage
func filtrer_barre_objets() -> void:
	var modification := false
	for id_objet in barre_objets.duplicate():
		if int(Inventaire.objets.get(id_objet, 0)) <= 0:
			barre_objets.erase(id_objet)
			modification = true
	if modification:
		sauvegarder()
		barre_objets_modifiee.emit()

# Mange un fruit du démon de l'inventaire : ses pouvoirs sont débloqués
# définitivement, ses bonus passifs s'appliquent et le fruit ne peut plus
# être trouvé dans le monde (unique_items). Renvoie "" si réussi, sinon
# un message d'erreur expliquant le refus.
func manger_fruit(id_fruit: String) -> String:
	if fruit_id != "":
		return "Un second fruit serait mortel — tu en as déjà mangé un."
	if not Inventaire.objets.has(id_fruit):
		return "Tu ne possèdes pas ce fruit."
	var details := Inventaire.details_objet(id_fruit)
	if str(details.get("type", "")) != "fruit_demon":
		return "Cet objet n'est pas un fruit du démon."
	if not sorts_fruit_disponibles_pour(id_fruit):
		return "Aucun pouvoir n'est rattaché à ce fruit (table fruit_skills)."
	Inventaire.retirer_objet(id_fruit, 1)
	fruit_id = id_fruit
	fruit_xp = 0
	if BaseDonnees.disponible and id_fruit.is_valid_int():
		BaseDonnees.lire(
			"UPDATE unique_items SET is_consumed = 1 WHERE item_id = %d;" % id_fruit.to_int())
	# les pouvoirs du fruit déjà débloqués rejoignent la barre s'il reste
	# de la place ; les suivants suivront au fil des niveaux (gagner_xp)
	var barre_changee := false
	for id in sorts_fruit():
		if sorts.has(id) and not sort_dans_barre(id) and not barre_sorts_pleine():
			barre_sorts.append(id)
			barre_changee = true
	recalculer_stats()
	sauvegarder()
	if barre_changee:
		barre_sorts_modifiee.emit()
	return ""

# ids des sorts de ce fruit en base (sans dépendre du fruit mangé)
func _pouvoirs_fruit(id_fruit: String) -> Array[String]:
	var ids: Array[String] = []
	if not BaseDonnees.disponible or not id_fruit.is_valid_int():
		return ids
	for ligne in BaseDonnees.lire(
		"SELECT skill_id FROM fruit_skills WHERE fruit_item_id = %d;" % id_fruit.to_int()):
		ids.append(str(ligne["skill_id"]))
	return ids

func sorts_fruit_disponibles_pour(id_fruit: String) -> bool:
	return not _pouvoirs_fruit(id_fruit).is_empty()

# Utilise un consommable de l'inventaire : les points de vie sont
# restaurés immédiatement, les autres bonus (attaque, défense...) sont
# actifs pendant `duration` minutes, puis l'objet est retiré. Boire la
# même potion rafraîchit son buff au lieu de le cumuler. Renvoie ""
# si réussi, sinon un message d'erreur expliquant le refus.
func utiliser_objet(id_objet: String) -> String:
	if int(Inventaire.objets.get(id_objet, 0)) <= 0:
		return "Tu ne possèdes pas cet objet."
	var details := Inventaire.details_objet(id_objet)
	if str(details.get("type", "")) != "consumable":
		return "Cet objet ne se consomme pas."
	var effets: Dictionary = details.get("effets", {})
	# les consommables ne se partagent qu'hors combat : potions,
	# buffs et plats attendent la fin de la rencontre
	if _est_en_combat():
		return "Cet objet ne s'utilise pas en combat."
	if bool(effets.get(EFFET_REATTRIBUTION, false)):
		return _utiliser_parchemin_reattribution(id_objet)
	# carte au trésor : elle se déchiffre et plante une croix sur la
	# carte du monde (aucun soin ni buff)
	if str(details.get("sous_type", "")) == "carte_tresor":
		var niveau := clampi(int(effets.get("tresor", 1)), 1, 4)
		if not CartesTresor.creer_croix(niveau):
			return "Aucun emplacement exploitable sur la carte."
		Inventaire.retirer_objet(id_objet, 1)
		sauvegarder()
		return ""
	# tablette des Flots Calmes : elle se brise en une bénédiction —
	# les gains (XP et Berry) du prochain combat gagné seront doublés
	if effets.has(EFFET_DOUBLE_COMBAT):
		prochain_combat_double = true
		Inventaire.retirer_objet(id_objet, 1)
		sauvegarder()
		return ""
	# un consommable amélioré par son métier (cuisinier, médecin) soigne
	# et buffe davantage : le facteur d'amélioration gonfle tout
	var facteur := facteur_amelioration(id_objet)
	var soin := roundi(int(effets.get("heal", 0)) * facteur)
	# clés de bonus durable (hors soin et durée de l'effet)
	var bonus := {}
	for cle in effets:
		if str(cle) != "heal" and str(cle) != "health" and str(cle) != "duration":
			bonus[str(cle)] = roundi(int(effets[cle]) * facteur)
	if soin == 0 and bonus.is_empty():
		return "Cet objet n'a aucun effet."
	Inventaire.retirer_objet(id_objet, 1)
	if soin > 0:
		soigner(soin)
	if not bonus.is_empty():
		var duree_minutes := maxi(int(effets.get("duration", 30)), 1)
		var expire := Time.get_unix_time_from_system() + 60.0 * duree_minutes
		# un même consommable ne se cumule pas : il rafraîchit son buff
		for i in range(buffs.size()):
			if str(buffs[i].get("id", "")) == id_objet:
				buffs.remove_at(i)
				break
		buffs.append({"id": id_objet, "effets": bonus, "expire": expire})
	# recalcul SANS remplir la vie : le soin de l'objet est le seul
	# accordé, la potion ne soigne pas au-delà de sa valeur
	recalculer_stats(false)
	sauvegarder()
	return ""

func points_recuperables() -> int:
	var total := 0
	for cle in caracteristiques:
		total += maxi(int(points_depenses.get(cle, 0)), 0)
	return total

# un combat est-il en cours sur la scène courante (CombatManager actif)
func _est_en_combat() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var combat := scene.get_node_or_null("CombatManager")
	return combat != null and bool(combat.get("en_combat"))

func _utiliser_parchemin_reattribution(id_objet: String) -> String:
	var scene := get_tree().current_scene
	var combat := scene.get_node_or_null("CombatManager") if scene != null else null
	if combat != null and combat.en_combat:
		return "Ce parchemin s’utilise hors combat."
	var points := points_recuperables()
	if points == 0:
		return "Tu n’as aucun point investi à récupérer."
	points_statistique += points
	points_depenses.clear()
	Inventaire.retirer_objet(id_objet, 1)
	recalculer_stats(false)
	return ""

# Applique les bonus de la race et de la classe sur les stats de base,
# puis réapplique les points de caractéristiques dépensés
func recalculer_stats(remplir_vie := true) -> void:
	vie_max = 100
	attaque = 0
	defense = 0
	vitesse = 0
	for cle in caracteristiques:
		caracteristiques[cle] = 0
	for donnees in [races.get(race_id, {}), classes.get(classe_id, {})]:
		vie_max += int(donnees.get("vie", 0))
		attaque += int(donnees.get("attaque", 0))
		# pas de defense ici : la boucle des caracteristiques la prend
		# (clé « defense » présente), elle rejoint le total à la fin
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
	# bonus des objets équipés (effects_json des items) — gonflés par
	# les niveaux d'amélioration de l'atelier du métier
	for emplacement in equipement:
		var id_equipe: String = str(equipement[emplacement])
		if id_equipe == "":
			continue
		_appliquer_effets_objet(_effets_ameliores(id_equipe))
	# bonus passifs du fruit du démon mangé (effects_json de l'item fruit)
	if fruit_id != "":
		_appliquer_effets_objet(Inventaire.details_objet(fruit_id).get("effets", {}))
	# bonus temporaires des consommables utilisés (buffs non échus)
	var maintenant := Time.get_unix_time_from_system()
	var actifs: Array = []
	for buff in buffs:
		if buff is Dictionary and float(buff.get("expire", 0.0)) > maintenant:
			actifs.append(buff)
	buffs = actifs
	for buff in actifs:
		_appliquer_effets_objet(buff.get("effets", {}))
	# le navire soutient son capitaine : sa solidité devient vie et
	# défense (en combat), sa résistance aux tempêtes devient de la
	# vitesse d'exploration (hors combat)
	var navire := stats_bateau()
	vie_max += int(navire["solidite"]) / 20
	vie_max = maxi(vie_max, 1)
	vie = vie_max if remplir_vie else clampi(vie, 0, vie_max)
	# la défense répartie (race, classe, points dépensés) rejoint la
	# défense des objets et des buffs : c'est le total qui absorbe les
	# dégâts dans les combats
	defense += int(caracteristiques.get("defense", 0)) + int(navire["solidite"]) / 200
	caracteristiques_modifiees.emit()

# applique les effets d'un objet (paires clé -> valeur de effects_json)
# sur les stats du personnage
func _appliquer_effets_objet(effets: Dictionary) -> void:
	for cle in effets:
		var valeur := int(effets[cle])
		match cle:
			"attack":
				attaque += valeur
			"defense":
				defense += valeur
			"speed":
				vitesse += valeur
			"vie", "health":
				vie_max += valeur
			"vitalite":
				caracteristiques[cle] += valeur
				vie_max += 5 * valeur
			_:
				if caracteristiques.has(cle):
					caracteristiques[cle] += valeur

# emplacement d'équipement d'un objet selon son type et son sous-type
# ("" si non équipable ; "anneau" est virtuel : résolu en anneau1/anneau2)
func emplacement_equipement(type: String, sous_type: String = "") -> String:
	match type.to_lower():
		"arme":
			return "arme"
		"armure":
			match sous_type.to_lower():
				"cape":
					return "cape"
				"ceinture":
					return "ceinture"
				"pantalon":
					return "pantalon"
				"chaussures", "pieds":
					return "pieds"
				"gants", "mains", "main", "protège-bras", "bracelet", "bouclier":
					return "main"
				_:
					return "corps"
		"accessoire":
			match sous_type.to_lower():
				"tête":
					return "tête"
				"visage", "monocle":
					return "visage"
				"cou":
					return "cou"
				"anneau":
					return "anneau"
				"ceinture":
					return "ceinture"
				"pieds", "chaussures":
					return "pieds"
				"gants", "mains", "main", "bracelet", "boussole", "longue-vue", "sextant", "dial", "instrument":
					return "main"
	return ""

# emplacement réel d'un objet (les anneaux vont sur le premier emplacement libre,
# ou remplacent l'anneau 1 si les deux sont occupés)
func _resoudre_emplacement(details: Dictionary) -> String:
	var emplacement := emplacement_equipement(str(details.get("type", "")), str(details.get("sous_type", "")))
	if emplacement == "anneau":
		if equipement.get("anneau1", "") == "":
			return "anneau1"
		if equipement.get("anneau2", "") == "":
			return "anneau2"
		return "anneau1"
	if emplacement == "arme":
		# l'arme principale est obligatoirement en accord avec la classe :
		# une arme à classe requise qui n'est pas la vôtre ne peut aller
		# qu'en arme secondaire ; une arme accordée prend la place
		# principale si elle est libre
		if not arme_accordee(details):
			return "arme2"
		if equipement.get("arme", "") == "":
			return "arme"
		return "arme2"
	return emplacement

# true si l'arme peut occuper l'emplacement d'arme principale : pas de
# classe requise (libre à tous), ou classe requise = classe du perso
func arme_accordee(details: Dictionary) -> bool:
	var cr: Variant = details.get("classe_requise", "")
	var classe_requise := ("" if cr == null else str(cr)).strip_edges()
	if classe_requise == "" or classe_requise == "<null>":
		return true
	return classe_requise.to_lower() == nom_classe().to_lower()

# emplacement où l'objet est équipé ("" si non porté)
func est_equipe(id: String) -> String:
	for emplacement in equipement:
		if equipement[emplacement] == id:
			return emplacement
	return ""

# Équipe un objet de l'inventaire (l'ancien objet de l'emplacement retourne
# à l'inventaire) ; renvoie false si l'objet n'est pas équipable ou si le
# niveau requis n'est pas atteint
func equiper(id: String) -> bool:
	var details := Inventaire.details_objet(id)
	var emplacement := _resoudre_emplacement(details)
	if emplacement == "" or not Inventaire.objets.has(id):
		return false
	if int(details.get("niveau_min", 1)) > niveau:
		return false
	if equipement[emplacement] == id:
		return true
	if equipement[emplacement] != "":
		Inventaire.ajouter_objet(equipement[emplacement])
	if not Inventaire.objets.has(id) or int(Inventaire.objets[id]) < 1:
		return false
	Inventaire.retirer_objet(id, 1)
	equipement[emplacement] = id
	recalculer_stats()
	return true

# Range l'objet équipé d'un emplacement de retour à l'inventaire
func desequiper(emplacement: String) -> void:
	if not equipement.has(emplacement) or equipement[emplacement] == "":
		return
	Inventaire.ajouter_objet(equipement[emplacement])
	equipement[emplacement] = ""
	recalculer_stats()

# --- navire du personnage ---

# emplacement de navire visé par un item ("" si ce n'est pas une
# pièce de navire) : reconnu au préfixe « Navire : » de sa
# description, puis au mot-clé de son nom
func emplacement_navire(id: String) -> String:
	if id == "" or not str(Inventaire.details_objet(id).get("description", "")).begins_with("Navire :"):
		return ""
	var nom_item := Inventaire.nom_objet(id)
	for mot_cle in EMPLACEMENTS_NAVIRE:
		if nom_item.begins_with(mot_cle):
			return str(EMPLACEMENTS_NAVIRE[mot_cle])
	return ""

# une pièce de navire est-elle déjà installée sur l'emplacement ?
func piece_navire_installee(id: String) -> bool:
	return bateau.values().has(id)

# installe une pièce de navire possédée : l'ancienne pièce de
# l'emplacement rejoint l'inventaire ; renvoie l'emplacement, "" en
# cas de refus
func installer_piece_navire(id: String) -> String:
	var emplacement := emplacement_navire(id)
	if emplacement == "" or emplacement not in bateau or int(Inventaire.objets.get(id, 0)) <= 0:
		return ""
	# une pièce trop exigeante pour le capitaine ne s'installe pas,
	# comme pour l'équipement porté
	var details := Inventaire.details_objet(id)
	if int(details.get("niveau_min", 1)) > niveau:
		return ""
	var ancienne := str(bateau[emplacement])
	Inventaire.retirer_objet(id, 1)
	if ancienne != "":
		Inventaire.ajouter_objet(ancienne, 1)
	bateau[emplacement] = id
	recalculer_stats(false)
	sauvegarder()
	return emplacement

# retire la pièce installée d'un emplacement : elle rejoint
# l'inventaire
func retirer_piece_navire(emplacement: String) -> bool:
	if not bateau.has(emplacement) or str(bateau[emplacement]) == "":
		return false
	Inventaire.ajouter_objet(str(bateau[emplacement]), 1)
	bateau[emplacement] = ""
	recalculer_stats(false)
	sauvegarder()
	return true

# lit la description d'une pièce (« Navire : +25 solidité et +0 % de
# résistance aux tempêtes ») ; non reconnue → 0/0
var _regex_navire: RegEx

func _stats_piece_bateau(id: String) -> Dictionary:
	var stats := {"solidite": 0, "tempete": 0.0}
	var description := str(Inventaire.details_objet(id).get("description", ""))
	if _regex_navire == null:
		_regex_navire = RegEx.new()
		_regex_navire.compile("Navire :\\s*\\+(\\d+) solidité et \\+(\\d+) % de résistance aux tempêtes")
	var analyse := _regex_navire.search(description)
	if analyse != null:
		stats["solidite"] = int(analyse.get_string(1))
		stats["tempete"] = float(analyse.get_string(2))
	# une pièce améliorée par le charpentier encaisse davantage :
	# ses niveaux gonflent la solidité comme les stats d'un équipement
	var facteur := facteur_amelioration(id)
	if facteur != 1.0:
		stats["solidite"] = roundi(float(stats["solidite"]) * facteur)
		stats["tempete"] = float(stats["tempete"]) * facteur
	return stats

# solidité et résistance aux tempêtes du navire : la somme des
# pièces installées
func stats_bateau() -> Dictionary:
	var solidite := 0
	var tempete := 0.0
	for emplacement in bateau:
		var id := str(bateau[emplacement])
		if id == "":
			continue
		var stats := _stats_piece_bateau(id)
		solidite += int(stats["solidite"])
		tempete += float(stats["tempete"])
	return {"solidite": solidite, "tempete": tempete}

# bonus de vitesse d'exploration (hors combat) conféré par le
# navire : +1% par point de résistance aux tempêtes, plafonné
func bonus_vitesse_navire() -> float:
	return clampf(stats_bateau()["tempete"] * 0.01, 0.0, 0.30)

# attaque totale affichée : la base (race, classe, équipement, buffs)
# plus la contribution de la Force — c'est exactement ce que chaque
# coup reçoit dans la formule de dégâts (attaque + bonus de Force)
func attaque_effective() -> int:
	return attaque + int(caracteristiques.get("force", 0))

# --- améliorations d'équipement (atelier du métier) ---

# chaque niveau d'amélioration gonfle les stats de l'objet de 20 %,
# jusqu'à dix niveaux (soit un triplement des stats au sommet)
const AMELIORATION_MAX := 10
const AMELIORATION_BONUS := 0.20
# id objet -> niveau d'amélioration atteint
var ameliorations: Dictionary = {}

# familles d'objets qu'un métier sait améliorer : paires (type,
# sous-type) — sous-type vide = tout le type — ou l'entrée spéciale
# (« navire ») pour les pièces de navire, reconnues par leur
# description. Chaque métier ne retouche que sa spécialité,
# c'est-à-dire ce qu'il fabrique lui-même.
const FAMILLES_AMELIORATION := {
	"carpenter": [["navire", ""]],
	"medic": [["consumable", "soin"]],
	"cook": [["consumable", "energie"], ["consumable", "nourriture"]],
	"musician": [["accessoire", "instrument"]],
	"blacksmith": [["armure", ""], ["arme", "hache"], ["arme", "masse"], ["arme", "lance"], ["arme", "bâton"]],
	"navigateur": [["accessoire", "boussole"], ["accessoire", "longue-vue"], ["accessoire", "sextant"]],
	"combattant": [["arme", "gants"], ["armure", "protège-bras"], ["accessoire", "visage"], ["accessoire", "pieds"], ["accessoire", "ceinture"], ["accessoire", "bracelet"]],
	"sabreur": [["arme", "épée"]],
	"tireur": [["arme", "pistolet"], ["arme", "fusil"], ["arme", "mousquet"], ["arme", "carabine"], ["arme", "canon"], ["arme", "lance-roquettes"]],
	"archeologue": [["accessoire", "monocle"]],
}

# le métier unique du personnage (clé de `metiers`), "" s'il n'en a pas
func metier_perso() -> String:
	if metiers.is_empty():
		return ""
	return str(metiers.keys()[0])

func niveau_amelioration(id_objet: String) -> int:
	return int(ameliorations.get(id_objet, 0))

# multiplicateur courant des stats de l'objet (1.0 = vierge)
func facteur_amelioration(id_objet: String) -> float:
	return 1.0 + AMELIORATION_BONUS * float(niveau_amelioration(id_objet))

# coût du prochain niveau : du fer et de l'or, en quantités
# croissantes (deux fois le niveau visé en fer, une fois en or)
func cout_amelioration(id_objet: String) -> Dictionary:
	var niveau_vise := mini(niveau_amelioration(id_objet) + 1, AMELIORATION_MAX)
	return {"16": 2 * niveau_vise, "17": niveau_vise}

# l'objet appartient-il à une famille que le métier sait améliorer ?
func objet_ameliorable(id_objet: String) -> bool:
	var details := Inventaire.details_objet(id_objet)
	var familles: Array = FAMILLES_AMELIORATION.get(metier_perso(), [])
	for famille in familles:
		var famille_type := str(famille[0])
		var famille_sous_type := str(famille[1])
		if famille_type == "navire":
			if str(details.get("description", "")).begins_with("Navire :"):
				return true
		elif str(details.get("type", "")) == famille_type and (famille_sous_type == "" or str(details.get("sous_type", "")) == famille_sous_type):
			return true
	return false

# engage le prochain niveau d'amélioration ; renvoie un message
# d'explication en cas de refus, "" si l'atelier a travaillé
func ameliorer_objet(id_objet: String) -> String:
	if int(Inventaire.objets.get(id_objet, 0)) <= 0:
		return "Tu ne possèdes pas cet objet."
	if not objet_ameliorable(id_objet):
		return "Ton métier ne sait pas améliorer cet objet."
	var niveau := niveau_amelioration(id_objet)
	if niveau >= AMELIORATION_MAX:
		return "Cet objet est déjà au sommet de l'art de ton métier."
	var cout := cout_amelioration(id_objet)
	for id_ressource in cout:
		if int(Inventaire.objets.get(str(id_ressource), 0)) < int(cout[id_ressource]):
			return "Il te manque des ressources pour ce niveau."
	for id_ressource in cout:
		Inventaire.retirer_objet(str(id_ressource), int(cout[id_ressource]))
	ameliorations[id_objet] = niveau + 1
	# les effets de l'objet porté changent : les stats suivent
	recalculer_stats(false)
	sauvegarder()
	return ""

# effets d'un objet, gonflés par ses niveaux d'amélioration (chaque
# valeur arrondie à l'entier le plus proche)
func _effets_ameliores(id_objet: String) -> Dictionary:
	var effets: Dictionary = Inventaire.details_objet(id_objet).get("effets", {})
	var facteur := facteur_amelioration(id_objet)
	if facteur == 1.0:
		return effets
	var copies := {}
	for cle in effets:
		copies[cle] = roundi(float(effets[cle]) * facteur)
	return copies

# équipe d'un coup, sur chaque emplacement, le meilleur objet atteignable
# (score = somme des effets bénéfiques) ; l'arme principale exige une
# arme accordée à la classe, l'arme secondaire accepte toute classe, les
# deux meilleures bagues couvrent les anneaux ; un objet porté n'est
# remplacé que par un score strictement supérieur — l'automatisation ne
# régresse jamais. Renvoie le nombre d'emplacements modifiés.
func equiper_les_meilleurs() -> int:
	var candidats: Array = []
	for id in Inventaire.objets:
		var candidat := _candidat_equipement(str(id))
		if not candidat.is_empty():
			candidats.append(candidat)
	for emplacement in equipement:
		var id_porte := str(equipement[emplacement])
		if id_porte == "":
			continue
		var candidat_porte := _candidat_equipement(id_porte, true)
		if not candidat_porte.is_empty():
			candidats.append(candidat_porte)
	# meilleur de chaque emplacement simple (le porté gagne les égalités)
	var fixes := ["tête", "visage", "cou", "corps", "cape", "ceinture", "pantalon", "pieds", "main"]
	var meilleurs := {}
	for candidat in candidats:
		var emplacement := str(candidat["emplacement"])
		if emplacement == "arme" or emplacement == "anneau":
			continue
		if not meilleurs.has(emplacement):
			meilleurs[emplacement] = candidat
			continue
		var score := int(candidat["score"])
		var porteur: bool = bool(candidat["porte"])
		var actuel: Dictionary = meilleurs[emplacement]
		if score > int(actuel["score"]) or (score == int(actuel["score"]) and porteur and not bool(actuel["porte"])):
			meilleurs[emplacement] = candidat
	# armes et bagues : classées par score décroissant
	var armes: Array = []
	var bagues: Array = []
	for candidat in candidats:
		if str(candidat["emplacement"]) == "arme":
			armes.append(candidat)
		elif str(candidat["emplacement"]) == "anneau":
			bagues.append(candidat)
	for liste in [armes, bagues]:
		liste.sort_custom(func(a, b) -> bool: return int(a["score"]) > int(b["score"]))
	var remplacements := {}
	for emplacement in fixes:
		if meilleurs.has(emplacement):
			remplacements[emplacement] = str(meilleurs[emplacement]["id"])
	# bagues : les deux meilleures ; une bague seule reste à sa place
	if bagues.size() == 1:
		var bague_seule: Dictionary = bagues[0]
		if bool(bague_seule["porte"]):
			remplacements[est_equipe(str(bague_seule["id"]))] = str(bague_seule["id"])
		else:
			remplacements["anneau1"] = str(bague_seule["id"])
	elif bagues.size() >= 2:
		remplacements["anneau1"] = str(bagues[0]["id"])
		remplacements["anneau2"] = str(bagues[1]["id"])
	# arme principale : la meilleure accordée à la classe ; l'arme
	# secondaire : la meilleure des autres (l'actuelle incluse)
	for candidat in armes:
		if bool(candidat["accordee"]):
			remplacements["arme"] = str(candidat["id"])
			break
	for candidat in armes:
		if str(candidat["id"]) != str(remplacements.get("arme", "@")):
			remplacements["arme2"] = str(candidat["id"])
			break
	# application : arme avant arme secondaire (l'ancienne arme
	# retourne à l'inventaire et reste candidate pour arme2)
	var changements := 0
	for emplacement in remplacements:
		if str(equipement.get(emplacement, "")) == str(remplacements[emplacement]):
			continue
		if _equiper_sur_emplacement(emplacement, str(remplacements[emplacement])):
			changements += 1
	if changements > 0:
		recalculer_stats()
		sauvegarder()
	return changements

# fiche de candidature d'un objet : vide s'il n'équipe aucun
# emplacement ; porté = déjà sur le perso (l'objet des slots sortis
# du combat garde son droit de place, il n'est pas dans l'inventaire)
func _candidat_equipement(id: String, porte := false) -> Dictionary:
	var details := Inventaire.details_objet(id)
	var emplacement := emplacement_equipement(str(details.get("type", "")), str(details.get("sous_type", "")))
	if emplacement == "":
		return {}
	if int(details.get("niveau_min", 1)) > niveau and not porte:
		return {}
	return {
		"emplacement": emplacement,
		"id": id,
		"score": _score_equipement(details),
		"accordee": arme_accordee(details),
		"porte": porte,
	}

# score d'un équipement pour l'optimisation : somme des valeurs
# positives de ses effets (attaque, défense, vie, caractéristiques...)
func _score_equipement(details: Dictionary) -> int:
	var score := 0
	var effets: Dictionary = details.get("effets", {})
	for cle in effets:
		if str(cle) == "duration":
			continue
		score += maxi(int(effets[cle]), 0)
	return score

# équipe un objet sur un emplacement précis (l'ancien retourne à
# l'inventaire) sans passer par la résolution automatique des slots
func _equiper_sur_emplacement(emplacement: String, id: String) -> bool:
	if not equipement.has(emplacement) or not Inventaire.objets.has(id):
		return false
	if equipement[emplacement] == id:
		return false
	var details := Inventaire.details_objet(id)
	if int(details.get("niveau_min", 1)) > niveau:
		return false
	if equipement[emplacement] != "":
		Inventaire.ajouter_objet(equipement[emplacement])
	Inventaire.retirer_objet(id, 1)
	equipement[emplacement] = id
	return true

# Création définitive du personnage (depuis l'interface de création)
func creer(nouveau_nom: String, nouvelle_race: String, nouvelle_classe: String,
		id_profession: String = "", nouveau_sexe: String = "M",
		nouvelle_apparence: String = APPARENCE_HUMAINE_DEFAUT) -> void:
	# le nouveau perso ne garde rien de l'ancien : l'inventaire et
	# l'historique des quêtes (fichiers locaux) repartent de zéro,
	# pas plus sa dernière position d'exploration
	Inventaire.reinitialiser()
	QuestManager.reinitialiser()
	Reseau.oublier_position_memorisee()
	nom = nouveau_nom
	race_id = nouvelle_race
	classe_id = nouvelle_classe
	sexe = nouveau_sexe if VALEURS_SEXES_VALIDES.has(nouveau_sexe) else "M"
	apparence_humaine = normaliser_apparence_humaine(race_id, nouvelle_apparence)
	niveau = 1
	xp = 0
	berry = 0
	points_statistique = 0
	barre_sorts = []
	barre_objets = []
	fruit_id = ""
	fruit_xp = 0
	buffs = []
	# sorts de base de la classe : placés d'office dans la barre de combat
	for id_sort in classes.get(nouvelle_classe, {}).get("sorts_initiaux", []):
		var id := str(id_sort)
		if sorts.has(id) and not barre_sorts.has(id):
			barre_sorts.append(id)
	metiers = {}
	# métier unique, choisi à la création
	if id_profession != "" and _professions.has(id_profession):
		metiers[id_profession] = {"niveau": 1, "xp": 0}
	points_depenses = {}
	equipement = {
		"arme": "", "arme2": "", "corps": "", "tête": "", "visage": "", "cou": "",
		"main": "", "cape": "", "ceinture": "", "pantalon": "", "pieds": "",
		"anneau1": "", "anneau2": "",
	}
	# le navire d'un nouveau perso est nu : aucune pièce installée
	bateau = {"planche": "", "gouvernail": "", "mat": "", "coque": "", "proue": ""}
	recalculer_stats()
	perso_cree = true
	sauvegarder()
	barre_sorts_modifiee.emit()
func sauvegarder() -> void:
	# en ligne, le serveur est l'unique référence du perso : la
	# sauvegarde locale n'est plus touchée pendant la session
	if en_ligne:
		Reseau.sauvegarder_perso_immediat()
		return
	_ecrire_fichier_perso()

# connecté à caracteristiques_modifiees : le perso existant se sauvegarde
# tout seul à chaque changement (XP, Berry, points, vie...)
func _auto_sauvegarder() -> void:
	if perso_cree:
		sauvegarder()

func _ecrire_fichier_perso() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("perso", "nom", nom)
	cfg.set_value("perso", "race", race_id)
	cfg.set_value("perso", "classe", classe_id)
	cfg.set_value("perso", "sexe", sexe)
	cfg.set_value("perso", "apparence_humaine", apparence_humaine)
	cfg.set_value("perso", "berry", berry)
	cfg.set_value("perso", "niveau", niveau)
	cfg.set_value("perso", "xp", xp)
	cfg.set_value("perso", "vie", vie)
	cfg.set_value("perso", "points_statistique", points_statistique)
	cfg.set_value("perso", "points_depenses", points_depenses)
	cfg.set_value("perso", "equipement", equipement)
	cfg.set_value("perso", "bateau", bateau)
	cfg.set_value("perso", "metiers", metiers)
	cfg.set_value("perso", "barre_sorts", barre_sorts)
	cfg.set_value("perso", "barre_objets", barre_objets)
	cfg.set_value("perso", "fruit", fruit_id)
	cfg.set_value("perso", "fruit_xp", fruit_xp)
	cfg.set_value("perso", "buffs", buffs)
	cfg.set_value("perso", "prochain_combat_double", prochain_combat_double)
	cfg.set_value("perso", "ameliorations", ameliorations)
	perso_cree = cfg.save(CHEMIN_PERSO) == OK

func charger_perso() -> void:
	# en ligne, la référence est le perso serveur : ne jamais reprendre
	# le perso.cfg local par-dessus
	if en_ligne:
		return
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PERSO) != OK:
		return
	nom = str(cfg.get_value("perso", "nom", "Héros"))
	race_id = str(cfg.get_value("perso", "race", "1"))
	classe_id = str(cfg.get_value("perso", "classe", "12"))
	# classe supprimée du jeu : bascule sur la classe de remplacement
	var classe_remplacee := false
	if not classes.has(classe_id):
		classe_id = CLASSES_REMPLACEMENT.get(classe_id, "12")
		classe_remplacee = true
	var sexe_lu := str(cfg.get_value("perso", "sexe", "M"))
	sexe = sexe_lu if VALEURS_SEXES_VALIDES.has(sexe_lu) else "M"
	apparence_humaine = normaliser_apparence_humaine(
		race_id, str(cfg.get_value("perso", "apparence_humaine", APPARENCE_HUMAINE_DEFAUT)))
	berry = int(cfg.get_value("perso", "berry", 0))
	points_statistique = int(cfg.get_value("perso", "points_statistique", 0))
	prochain_combat_double = bool(cfg.get_value("perso", "prochain_combat_double", false))
	ameliorations = {}
	var ameliorations_sauvees: Dictionary = cfg.get_value("perso", "ameliorations", {})
	for id_ameliore in ameliorations_sauvees:
		ameliorations[str(id_ameliore)] = int(ameliorations_sauvees[id_ameliore])
	var depenses = cfg.get_value("perso", "points_depenses", {})
	if depenses is Dictionary:
		points_depenses = depenses
	var metiers_lus = cfg.get_value("perso", "metiers", {})
	if metiers_lus is Dictionary:
		metiers = _normaliser_metiers_sauves(metiers_lus)
	var barre_lue = cfg.get_value("perso", "barre_sorts", [])
	if barre_lue is Array:
		barre_sorts = []
		for id_sort in barre_lue:
			var id := str(id_sort)
			if not barre_sorts.has(id):
				barre_sorts.append(id)
	var barre_objets_lue = cfg.get_value("perso", "barre_objets", [])
	if barre_objets_lue is Array:
		barre_objets = []
		for id_objet in barre_objets_lue:
			var id_item := str(id_objet)
			if not barre_objets.has(id_item):
				barre_objets.append(id_item)
	filtrer_barre_objets()
	fruit_id = str(cfg.get_value("perso", "fruit", ""))
	fruit_xp = maxi(int(cfg.get_value("perso", "fruit_xp", 0)), 0)
	buffs = []
	var buffs_lus = cfg.get_value("perso", "buffs", [])
	if buffs_lus is Array:
		for buff in buffs_lus:
			if buff is Dictionary:
				buffs.append(buff)
	var equip = cfg.get_value("perso", "equipement", {})
	if equip is Dictionary:
		# re-mappe chaque objet équipé vers son emplacement (compatibilité avec
		# les anciennes sauvegardes qui utilisaient armure/accessoire)
		for emplacement in equipement:
			equipement[emplacement] = ""
		for ancienne_cle in equip:
			var id_equipe := str(equip[ancienne_cle])
			if id_equipe == "":
				continue
			var details := Inventaire.details_objet(id_equipe)
			var cible := _resoudre_emplacement(details)
			if cible != "":
				equipement[cible] = id_equipe
	# pièces du navire : chaque emplacement reprend sa pièce ; les
	# pièces installées ne sont pas dans l'inventaire (retirées à
	# l'installation), leur id suffit
	var navire_lu = cfg.get_value("perso", "bateau", {})
	if navire_lu is Dictionary:
		for emplacement in bateau:
			bateau[emplacement] = ""
		for emplacement_lu in navire_lu:
			if bateau.has(emplacement_lu):
				bateau[emplacement_lu] = str(navire_lu[emplacement_lu])
	niveau = int(cfg.get_value("perso", "niveau", 1))
	xp = int(cfg.get_value("perso", "xp", 0))
	# filtrer la barre seulement ici : le niveau est connu, les sorts de
	# classe débloqués au fil des niveaux ne quittent pas la barre au
	# chargement (fruit et classe sont déjà lus à ce stade)
	_filtrer_barre_sorts()
	# classe remappée : les sorts de l'ancienne classe ont quitté la
	# barre (_filtrer_barre_sorts), ceux de la nouvelle la remplissent
	# s'il reste de la place — ici le niveau est chargé, les déblocages
	# s'appliquent
	if classe_remplacee:
		for id_sort in sorts_de_classe():
			if not sort_dans_barre(id_sort) and not barre_sorts_pleine():
				barre_sorts.append(id_sort)
	recalculer_stats()
	vie = clampi(int(cfg.get_value("perso", "vie", vie_max)), 0, vie_max)
	# un seul métier par personnage — les sauvegardes à plusieurs métiers
	# (ancien bouton Apprendre) ou sans métier sont normalisées
	perso_cree = true
	# la barre a pu changer (filtre, remap de classe) : le HUD suit
	barre_sorts_modifiee.emit()

# remet le perso en mémoire à zéro, sans toucher à la sauvegarde locale :
# un compte serveur sans perso repart d'une création à neuf
func reinitialiser() -> void:
	perso_cree = false
	nom = "Héros"
	race_id = "1"
	classe_id = "1"
	apparence_humaine = APPARENCE_HUMAINE_DEFAUT
	niveau = 1
	xp = 0
	berry = 0
	points_statistique = 0
	barre_sorts = []
	barre_objets = []
	fruit_id = ""
	fruit_xp = 0
	buffs = []
	metiers = {}
	points_depenses = {}
	ameliorations = {}
	equipement = {
		"arme": "", "arme2": "", "corps": "", "tête": "", "visage": "", "cou": "",
		"main": "", "cape": "", "ceinture": "", "pantalon": "", "pieds": "",
		"anneau1": "", "anneau2": "",
	}
	# idem le navire
	bateau = {"planche": "", "gouvernail": "", "mat": "", "coque": "", "proue": ""}
	recalculer_stats()
	# la barre repart à vide : l'interface suit
	barre_sorts_modifiee.emit()

func supprimer_perso() -> void:
	reinitialiser()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_PERSO))

func xp_prochain_niveau() -> int:
	return niveau * 100

# --- bonus de caractéristiques au gameplay ---

# dégâts ajoutés à tout sort d'attaque : la Force muscle chaque coup,
# au corps à corps comme à distance (l'Intelligence, elle, soigne)
func bonus_degats_sort(type_sort: String, _portee_sort: int) -> float:
	if type_sort.to_lower() != "attack":
		return 0.0
	return float(caracteristiques.get("force", 0)) * DEGATS_PAR_FORCE

# soin ajouté aux sorts de type heal (intelligence)
func bonus_soin_sort() -> float:
	return float(caracteristiques.get("intelligence", 0)) * SOIN_PAR_INTELLIGENCE

# la caractéristique qui augmente les effets d'un sort ("" si aucune) :
# la Force muscle toutes les attaques, l'Intelligence les soins —
# c'est elle qu'il faut améliorer pour renforcer ce sort
func stat_booster_sort(sort: Dictionary) -> String:
	var type := str(sort.get("type", "")).to_lower()
	if type == "attack":
		return "Force"
	if type == "heal" or type == "healing":
		return "Intelligence"
	return ""

# bonus actuel de la caractéristique du sort sur ses effets (dégâts ou
# soin), avec les stats courantes du personnage
func bonus_sort_actuel(sort: Dictionary) -> float:
	var type := str(sort.get("type", "")).to_lower()
	if type == "attack":
		return bonus_degats_sort(type, int(sort.get("portee", 1)))
	if type == "heal" or type == "healing":
		return bonus_soin_sort()
	return 0.0

# récompense d'XP avec le bonus de sagesse appliqué (pour gagner_xp
# et l'affichage des récompenses de victoire)
func xp_effectif(montant: int) -> int:
	return roundi(float(montant) * (1.0 + float(caracteristiques.get("sagesse", 0)) * BONUS_XP_PAR_SAGESSE))

# précision ajoutée aux attaques du personnage (caractéristique
# « chance », affichée « Précision »)
func bonus_precision() -> float:
	return float(caracteristiques.get("chance", 0)) * PRECISION_PAR_CHANCE

# esquive du personnage : retranchée à la précision des attaques
# ennemies qui le ciblent (caractéristique « agilite », « Vitesse »)
func bonus_esquive() -> float:
	return float(caracteristiques.get("agilite", 0)) * ESQUIVE_PAR_AGILITE

# chance de gagner un PM supplémentaire au début de son tour
func chance_pm_supplementaire() -> float:
	return clampf(float(caracteristiques.get("agilite", 0)) * CHANCE_PM_PAR_AGILITE, 0.0, 0.5)

# chance de réussir sa fuite d'un combat contre des ennemis : une
# base accueillante grandit avec l'agilité, plafonnée pour garder
# un risque
func chance_fuite() -> float:
	return clampf(FUITE_BASE + float(caracteristiques.get("agilite", 0)) * FUITE_PAR_AGILITE, 0.0, FUITE_MAX)

# probabilité de prendre l'initiative à l'ouverture du combat
# (jouer avant les ennemis)
func chance_initiative() -> float:
	return clampf(INITIATIVE_BASE + float(caracteristiques.get("agilite", 0)) * INITIATIVE_PAR_AGILITE, 0.0, 0.95)

func gagner_xp(montant: int) -> void:
	xp += xp_effectif(montant)
	var niveau_avant := niveau
	while xp >= xp_prochain_niveau():
		xp -= xp_prochain_niveau()
		niveau += 1
		vie_max += 5
		# pas de soin au passage de niveau : les points de vie
		# actuels ne bougent pas
		points_statistique += POINTS_PAR_NIVEAU
	# un nouveau sort de classe s'est débloqué -> placé dans la barre
	# s'il reste de la place ; les pouvoirs du fruit suivent une autre
	# progression : le niveau du fruit (utiliser_pouvoir_fruit)
	var barre_changee := false
	if niveau > niveau_avant:
		for id_sort in sorts_de_classe():
			if not sort_dans_barre(id_sort) and not barre_sorts_pleine():
				barre_sorts.append(id_sort)
				barre_changee = true
	# la barre a bougé : le HUD et le menu se resynchronisent
	if barre_changee:
		barre_sorts_modifiee.emit()
	caracteristiques_modifiees.emit()

# debug : mène le perso au niveau indiqué d'un coup, en enchaînant les
# montées de niveau normales (points, vie, sorts débloqués inclus) ;
# sans effet si le niveau demandé n'excède pas le courant
func monter_niveau(cible: int) -> void:
	var garde := 0
	while niveau < cible and garde < 1000:
		gagner_xp(xp_prochain_niveau() - xp)
		garde += 1
	sauvegarder()

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
	# la défense dépensée s'applique immédiatement (le total absorbs les
	# dégâts) ; recalculer_stats la reconfirme au prochain passage
	if cle == "defense":
		defense += 1
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
		if cle == "defense":
			defense += montant
	sauvegarder()
	caracteristiques_modifiees.emit()

func soigner(montant: int) -> void:
	vie = clampi(vie + montant, 0, vie_max)
	caracteristiques_modifiees.emit()

func ajouter_berry(montant: int) -> void:
	berry += montant
	caracteristiques_modifiees.emit()

func blesser(montant: int) -> void:
	# le bouclier d'absorption paie d'abord, les PV ensuite
	montant = absorber_bouclier(montant)
	vie = clampi(vie - montant, 0, vie_max)
	caracteristiques_modifiees.emit()

# points de bouclier actifs (Égide des anciens) : un pool temporaire
# qui encaisse les dégâts à la place des PV, pendant quelques tours
var bouclier: int = 0

# ajoute des points de bouclier (se cumule avec l'existant)
func gagner_bouclier(montant: int) -> void:
	if montant <= 0:
		return
	bouclier += montant
	caracteristiques_modifiees.emit()

# fait payer les dégâts au bouclier d'abord ; renvoie la part qui
# déborde et ira aux PV
func absorber_bouclier(montant: int) -> int:
	if bouclier <= 0 or montant <= 0:
		return montant
	var absorb := mini(bouclier, montant)
	bouclier -= absorb
	return montant - absorb

# dissipe le bouclier (fin de durée ou nouveau départ)
func perdre_bouclier() -> void:
	if bouclier != 0:
		bouclier = 0
		caracteristiques_modifiees.emit()

# --- Métiers et artisanat ---

const XP_METIER_BASE := 100  # xp pour passer du niveau n à n+1 : XP_METIER_BASE * n

# toutes les professions connues (id -> infos), lues dans la base
var _professions: Dictionary = {}
# métiers liés à chaque classe (id de classe -> [ids de professions de la
# table character_class_professions]) : la classe choisie à la création
# détermine les métiers proposés
var _metiers_par_classe: Dictionary = {}
# recettes actives (tableau), indexées par id
var _recettes: Array = []
var _recettes_par_id: Dictionary = {}

func charger_donnees_metiers() -> void:
	if not BaseDonnees.disponible:
		return
	_professions.clear()
	for ligne in BaseDonnees.lire(
		"SELECT id, display_name, description, icon, color FROM professions"
		+ " WHERE is_active = 1 ORDER BY display_name;"):
		_professions[str(ligne["id"])] = {
			"nom": str(ligne["display_name"]),
			"description": str(ligne["description"]),
			"icone": str(ligne["icon"]),
			"couleur": Color.from_string(str(ligne["color"]), Color.WHITE),
		}
	_metiers_par_classe.clear()
	for ligne in BaseDonnees.lire(
		"SELECT ccp.class_id, ccp.profession_id FROM character_class_professions ccp"
		+ " JOIN professions p ON p.id = ccp.profession_id AND p.is_active = 1"
		+ " ORDER BY ccp.class_id, p.display_name;"):
		var id_classe := str(ligne["class_id"])
		if not _metiers_par_classe.has(id_classe):
			_metiers_par_classe[id_classe] = []
		_metiers_par_classe[id_classe].append(str(ligne["profession_id"]))
	_recettes.clear()
	_recettes_par_id.clear()
	# tous les ingrédients en une requête, groupés par objet fabriqué
	var ingredients_par_item: Dictionary = {}
	for ing in BaseDonnees.lire(
		"SELECT item_id, ingredient_id, quantity FROM item_craft_ingredients;"):
		var cle_item := str(ing["item_id"])
		if not ingredients_par_item.has(cle_item):
			ingredients_par_item[cle_item] = []
		ingredients_par_item[cle_item].append({
			"id": str(ing["ingredient_id"]),
			"quantite": int(ing["quantity"]),
		})
	for ligne in BaseDonnees.lire(
		"SELECT c.id, c.display_name, c.profession_id, c.required_profession_level,"
		+ " c.result_item_id, c.result_quantity, c.xp_reward, c.berry_cost, c.craft_time_seconds"
		+ " FROM crafts c WHERE c.is_active = 1 ORDER BY c.required_profession_level;"):
		var resultat := str(ligne["result_item_id"])
		var recette_chargee := {
			"id": str(ligne["id"]),
			"profession": str(ligne["profession_id"]),
			"nom": str(ligne["display_name"]),
			"niveau_requis": int(ligne["required_profession_level"]),
			"item_resultat": resultat,
			"quantite_resultat": int(ligne["result_quantity"]),
			"xp": int(ligne["xp_reward"]),
			"cout_berry": int(ligne["berry_cost"]),
			"temps": int(ligne["craft_time_seconds"]),
			"ingredients": ingredients_par_item.get(resultat, []),
		}
		_recettes.append(recette_chargee)
		_recettes_par_id[recette_chargee["id"]] = recette_chargee

func professions() -> Dictionary:
	return _professions

# métiers proposés pour une classe donnée : ceux de la table de liaison, ou
# toutes les professions actives en repli (classe sans métier défini)
func professions_pour_classe(id_classe: String) -> Array:
	var ids = _metiers_par_classe.get(id_classe, [])
	if not ids.is_empty():
		var actifs: Array = []
		for id_profession in ids:
			if _professions.has(id_profession):
				actifs.append(str(id_profession))
		return actifs
	return _professions.keys()

func recettes(id_profession: String = "") -> Array:
	if id_profession == "":
		return _recettes
	return _recettes.filter(func(r): return r["profession"] == id_profession)

func recette(id_recette: String) -> Dictionary:
	return _recettes_par_id.get(id_recette, {})

func a_metier(id_profession: String) -> bool:
	return metiers.has(id_profession)

func apprendre_metier(id_profession: String) -> bool:
	# un seul métier par personnage, choisi à la création
	if not metiers.is_empty() or not _professions.has(id_profession):
		return false
	metiers[id_profession] = {"niveau": 1, "xp": 0}
	metiers_modifies.emit()
	return true

# règle de cohérence pour les sauvegardes : un seul métier conservé.
# Plusieurs métiers appris (ancien système) → Archéologue prioritaire ;
# aucun métier → Archéologue par défaut ; sinon on garde l'unique choisi.
func _normaliser_metiers_sauves(anciens: Dictionary) -> Dictionary:
	var id_garde := ""
	var id_archeologue := ""
	for id_profession in _professions:
		if str(_professions[id_profession]["nom"]) == "Archéologue":
			id_archeologue = str(id_profession)
	if anciens.size() == 1:
		var seul := str(anciens.keys()[0])
		if _professions.has(seul):
			id_garde = seul
	if anciens.size() > 1:
		for id_profession in anciens:
			if str(id_profession) == id_archeologue:
				id_garde = str(id_profession)
		if id_garde == "":
			for id_profession in anciens:
				if _professions.has(str(id_profession)):
					id_garde = str(id_profession)
					break
	# métier absent, disparu ou non choisi : personnage existant → Archéologue
	if id_garde == "":
		id_garde = id_archeologue
	if id_garde == "":
		return {}
	if anciens.has(id_garde):
		return {id_garde: anciens[id_garde]}
	return {id_garde: {"niveau": 1, "xp": 0}}

func niveau_metier(id_profession: String) -> int:
	if not metiers.has(id_profession):
		return 0
	return int(metiers[id_profession]["niveau"])

func xp_prochain_niveau_metier(id_profession: String) -> int:
	return XP_METIER_BASE * maxi(niveau_metier(id_profession), 1)

func _gagner_xp_metier(id_profession: String, montant: int) -> void:
	if not metiers.has(id_profession):
		return
	var donnees: Dictionary = metiers[id_profession]
	donnees["xp"] = int(donnees["xp"]) + montant
	while int(donnees["xp"]) >= XP_METIER_BASE * int(donnees["niveau"]):
		donnees["xp"] = int(donnees["xp"]) - XP_METIER_BASE * int(donnees["niveau"])
		donnees["niveau"] = int(donnees["niveau"]) + 1
	metiers_modifies.emit()

# raison pour laquelle une recette n'est pas réalisable ("" si possible)
func verifier_recette(id_recette: String) -> String:
	var r := recette(id_recette)
	if r.is_empty():
		return "Recette inconnue"
	if not metiers.has(r["profession"]):
		return "Métier non appris"
	if niveau_metier(r["profession"]) < int(r["niveau_requis"]):
		return "Niveau de métier insuffisant"
	if berry < int(r["cout_berry"]):
		return "Pas assez de Berry"
	for ing in r["ingredients"]:
		if int(Inventaire.objets.get(ing["id"], 0)) < int(ing["quantite"]):
			return "Ingrédient manquant : %s" % Inventaire.nom_objet(ing["id"])
	return ""

# fabrique l'objet de la recette : consomme Berry et ingrédients,
# ajoute le résultat à l'inventaire et donne l'XP de métier
func artisaner(id_recette: String) -> bool:
	if verifier_recette(id_recette) != "":
		return false
	var r := recette(id_recette)
	berry -= int(r["cout_berry"])
	for ing in r["ingredients"]:
		Inventaire.retirer_objet(ing["id"], int(ing["quantite"]))
	Inventaire.ajouter_objet(str(r["item_resultat"]), int(r["quantite_resultat"]))
	_gagner_xp_metier(str(r["profession"]), int(r["xp"]))
	return true
