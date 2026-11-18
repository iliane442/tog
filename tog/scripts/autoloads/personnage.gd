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

const POINTS_PAR_NIVEAU := 5

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
# sexe ("M" ou "F") — seul élément de personnalisation choisi à la création,
# l'apparence dépend ensuite de l'équipement porté
var sexe: String = "M"
const VALEURS_SEXES_VALIDES: Array[String] = ["M", "F"]
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

# Barre de sorts du joueur : ids des sorts placés dans les emplacements
# (dans l'ordre) ; seuls les sorts de la classe peuvent y figurer.
# Utilisée par les combats ; composée dans l'onglet Sorts du menu.
const TAILLE_BARRE_SORTS := 10
var barre_sorts: Array[String] = []

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

func _ready() -> void:
	# sauvegarde automatique du perso à chaque changement de stats
	caracteristiques_modifiees.connect(_auto_sauvegarder)
	metiers_modifies.connect(_auto_sauvegarder)
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

# niveau actuel du fruit mangé (0 tant qu'il n'a pas été utilisé)
func niveau_fruit() -> int:
	var niveau := 0
	while fruit_xp >= XP_FRUIT_PAR_PALIER * (niveau + 1) * (niveau + 2) / 2:
		niveau += 1
	return niveau

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

# pouvoirs du fruit débloqués à son niveau actuel (4 sorts + 1 éveil)
func sorts_fruit() -> Array[String]:
	return _sorts_fruit_niveau(niveau_fruit())

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
	return true

# retire un sort de la barre de combat ; l'ordre des autres sorts est
# conservé (rien ne se passe s'il n'y figure pas)
func retirer_sort_barre(id: String) -> void:
	if barre_sorts.has(id):
		barre_sorts.erase(id)
		sauvegarder()

# garde en barre uniquement les sorts disponibles (classe + fruit mangé)
func _filtrer_barre_sorts() -> void:
	for id_sort in barre_sorts.duplicate():
		if not sorts_disponibles().has(id_sort):
			barre_sorts.erase(id_sort)

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
	for id in sorts_fruit():
		if sorts.has(id) and not sort_dans_barre(id) and not barre_sorts_pleine():
			barre_sorts.append(id)
	recalculer_stats()
	sauvegarder()
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
	if not Inventaire.objets.has(id_objet):
		return "Tu ne possèdes pas cet objet."
	var details := Inventaire.details_objet(id_objet)
	if str(details.get("type", "")) != "consumable":
		return "Cet objet ne se consomme pas."
	var effets: Dictionary = details.get("effets", {})
	var soin := int(effets.get("heal", 0))
	# clés de bonus durable (hors soin et durée de l'effet)
	var bonus := {}
	for cle in effets:
		if str(cle) != "heal" and str(cle) != "health" and str(cle) != "duration":
			bonus[str(cle)] = int(effets[cle])
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
	recalculer_stats()
	sauvegarder()
	return ""

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
	# bonus des objets équipés (effects_json des items)
	for emplacement in equipement:
		var id_equipe: String = str(equipement[emplacement])
		if id_equipe == "":
			continue
		_appliquer_effets_objet(Inventaire.details_objet(id_equipe).get("effets", {}))
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
	vie_max = maxi(vie_max, 1)
	vie = vie_max
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

# Création définitive du personnage (depuis l'interface de création)
func creer(nouveau_nom: String, nouvelle_race: String, nouvelle_classe: String,
		id_profession: String = "", nouveau_sexe: String = "M") -> void:
	nom = nouveau_nom
	race_id = nouvelle_race
	classe_id = nouvelle_classe
	sexe = nouveau_sexe if VALEURS_SEXES_VALIDES.has(nouveau_sexe) else "M"
	niveau = 1
	xp = 0
	berry = 0
	points_statistique = 0
	barre_sorts = []
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
	cfg.set_value("perso", "sexe", sexe)
	cfg.set_value("perso", "berry", berry)
	cfg.set_value("perso", "niveau", niveau)
	cfg.set_value("perso", "xp", xp)
	cfg.set_value("perso", "vie", vie)
	cfg.set_value("perso", "points_statistique", points_statistique)
	cfg.set_value("perso", "points_depenses", points_depenses)
	cfg.set_value("perso", "equipement", equipement)
	cfg.set_value("perso", "metiers", metiers)
	cfg.set_value("perso", "barre_sorts", barre_sorts)
	cfg.set_value("perso", "fruit", fruit_id)
	cfg.set_value("perso", "fruit_xp", fruit_xp)
	cfg.set_value("perso", "buffs", buffs)
	perso_cree = cfg.save(CHEMIN_PERSO) == OK

func charger_perso() -> void:
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
	berry = int(cfg.get_value("perso", "berry", 0))
	points_statistique = int(cfg.get_value("perso", "points_statistique", 0))
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
	fruit_id = str(cfg.get_value("perso", "fruit", ""))
	fruit_xp = maxi(int(cfg.get_value("perso", "fruit_xp", 0)), 0)
	buffs = []
	var buffs_lus = cfg.get_value("perso", "buffs", [])
	if buffs_lus is Array:
		for buff in buffs_lus:
			if buff is Dictionary:
				buffs.append(buff)
	_filtrer_barre_sorts()
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
	niveau = int(cfg.get_value("perso", "niveau", 1))
	xp = int(cfg.get_value("perso", "xp", 0))
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

func supprimer_perso() -> void:
	perso_cree = false
	nom = "Héros"
	race_id = "1"
	classe_id = "1"
	niveau = 1
	xp = 0
	berry = 0
	points_statistique = 0
	barre_sorts = []
	fruit_id = ""
	fruit_xp = 0
	buffs = []
	metiers = {}
	points_depenses = {}
	equipement = {
		"arme": "", "arme2": "", "corps": "", "tête": "", "visage": "", "cou": "",
		"main": "", "cape": "", "ceinture": "", "pantalon": "", "pieds": "",
		"anneau1": "", "anneau2": "",
	}
	recalculer_stats()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_PERSO))

func xp_prochain_niveau() -> int:
	return niveau * 100

func gagner_xp(montant: int) -> void:
	xp += montant
	var niveau_avant := niveau
	while xp >= xp_prochain_niveau():
		xp -= xp_prochain_niveau()
		niveau += 1
		vie_max += 5
		vie = vie_max
		points_statistique += POINTS_PAR_NIVEAU
	# un nouveau sort de classe s'est débloqué -> placé dans la barre
	# s'il reste de la place ; les pouvoirs du fruit suivent une autre
	# progression : le niveau du fruit (utiliser_pouvoir_fruit)
	if niveau > niveau_avant:
		for id_sort in sorts_de_classe():
			if not sort_dans_barre(id_sort) and not barre_sorts_pleine():
				barre_sorts.append(id_sort)
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
