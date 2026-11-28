extends RefCounted

const CLASSIQUE := "navigation/classique"
const ITEM_TROIS_AIGUILLES := "976"
const ITEM_CADRE := "977"
const METIER_NAVIGATEUR := "29"
const MAX_EMPLACEMENTS := 10
const PORTS := {
	"village_fushia": {"nom": "Fushia", "prix": 15, "arrivee": "DepuisShells"},
	"shells_town": {"nom": "Shells Town", "prix": 20, "arrivee": "DepuisFushia"},
	"orange_town": {"nom": "Orange Town", "prix": 30, "arrivee": "DepuisShellsTown"},
	"syrup_village": {"nom": "Syrup Village", "prix": 45, "arrivee": "DepuisOrangeTown"},
	"baratie": {"nom": "Baratie", "prix": 60, "arrivee": "DepuisSyrupVillage"},
	"coco_village": {"nom": "Village Coco", "prix": 80, "arrivee": "DepuisBaratie"},
	"loguetown": {"nom": "Loguetown", "prix": 110, "arrivee": "DepuisVillageCoco"},
	"reverse_mountain": {"nom": "Reverse Mountain", "prix": 150, "arrivee": "DepuisLoguetown"},
	"whisky_peak": {"nom": "Whisky Peak", "prix": 200, "arrivee": "DepuisReverseMountain"},
	"little_garden": {"nom": "Little Garden", "prix": 260, "arrivee": "DepuisWhiskyPeak"},
	"drum": {"nom": "Drum", "prix": 330, "arrivee": "DepuisLittleGarden"},
	"nanohana": {"nom": "Alabasta", "prix": 420, "arrivee": "DepuisDrum"},
	"ile_celeste": {"nom": "Skypiea", "prix": 520, "arrivee": "DepuisAlabasta"},
	"zou": {"nom": "Zou", "prix": 650, "arrivee": "DepuisAlabasta"},
}
const CAPS_BOSS := {
	"trm_c6_logpose": "whisky_peak",
	"trm_wp_vermouth": "little_garden",
	"trm_lg_gardien": "drum",
	"trm_drum_wapol": "nanohana",
	"trm_c6_gds": "ile_celeste",
	"ener_trone": "zou",
}
const METEOS := [
	{"nom": "Mer calme", "surcout": 0.0},
	{"nom": "Vents contraires", "surcout": 0.15},
	{"nom": "Mer agitée", "surcout": 0.30},
	{"nom": "Tempête", "surcout": 0.55},
]
const DUREE_METEO := 300

static func identifiant(scene: String) -> String:
	var id := scene.get_file().get_basename()
	if id == "fushia":
		return "village_fushia"
	return id if PORTS.has(id) else ""

static func scene_port(port: String) -> String:
	return "res://scenes/%s.tscn" % port if PORTS.has(port) else ""

static func nom_port(port: String) -> String:
	return str(PORTS.get(port, {}).get("nom", port))

static func voisins(port: String) -> Array[String]:
	var resultat: Array[String] = []
	var ordre := PORTS.keys()
	var indice := ordre.find(port)
	if indice < 0:
		return resultat
	if indice > 0:
		resultat.append(ordre[indice - 1])
	if indice + 1 < ordre.size():
		resultat.append(ordre[indice + 1])
	if port == "nanohana":
		resultat.append("zou")
	elif port == "zou":
		resultat.append("nanohana")
	return resultat

static func carte(port: String) -> String:
	return "navigation/carte/" + port

static func eternel(port: String) -> String:
	return "navigation/eternel/" + port

static func fusion(ports: Array[String]) -> String:
	var destinations := ports.duplicate()
	destinations.sort()
	var type := "trois_aiguilles" if destinations.size() == 3 else "cadre"
	return "navigation/%s/%s" % [type, "+".join(destinations)]

static func destinations(objet: String) -> Array[String]:
	var resultat: Array[String] = []
	var parties := objet.split("/")
	if parties.size() != 3 or parties[0] != "navigation":
		return resultat
	var ports := parties[2].split("+")
	match parties[1]:
		"carte", "eternel":
			if ports.size() != 1:
				return resultat
		"trois_aiguilles":
			if ports.size() != 3:
				return resultat
		"cadre":
			if ports.size() < 4 or ports.size() > 10:
				return resultat
		_:
			return resultat
	for port in ports:
		if not PORTS.has(port) or port in resultat:
			return []
		resultat.append(port)
	return resultat

static func est_log_pose(objet: String) -> bool:
	return objet == CLASSIQUE or (not objet.begins_with("navigation/carte/") and not destinations(objet).is_empty())

static func article(objet: String) -> Dictionary:
	if not objet.begins_with("navigation/"):
		return {}
	if objet == CLASSIQUE:
		return {"nom": "Log Pose classique", "description": "Indique le cap réglé à bord."}
	var ports := destinations(objet)
	if ports.is_empty():
		return {}
	var noms: Array[String] = []
	for port in ports:
		noms.append(nom_port(port))
	if objet.begins_with("navigation/carte/"):
		return {"nom": "Carte marine · " + noms[0], "description": "Règle le Log Pose classique sur %s. Réutilisable." % noms[0]}
	if objet.begins_with("navigation/eternel/"):
		return {"nom": "Log Pose éternel · " + noms[0], "description": "Ouvre cette destination tant qu’il est équipé."}
	var trois_aiguilles := ports.size() == 3
	var nom := "Log Pose à trois aiguilles" if trois_aiguilles else "Cadre de Log Pose"
	return {
		"nom": nom + " · " + ", ".join(noms),
		"description": "Équipe-le dans la salle de navigation pour rejoindre %s." % ", ".join(noms),
		"modele": ITEM_TROIS_AIGUILLES if trois_aiguilles else ITEM_CADRE,
	}

static func etat(donnees: Variant) -> Dictionary:
	var source: Dictionary = donnees if donnees is Dictionary else {}
	var cap := str(source.get("cap", ""))
	var capacite := clampi(int(source.get("capacite", 1)), 1, MAX_EMPLACEMENTS)
	var equipement: Array[String] = []
	var selection: Variant = source.get("equipement", [CLASSIQUE])
	if selection is Array:
		for objet in selection:
			if objet is String and est_log_pose(objet) and objet not in equipement and equipement.size() < capacite:
				equipement.append(objet)
	var visites: Array[String] = ["village_fushia"]
	var historique: Variant = source.get("visites", [])
	if historique is Array:
		for port in historique:
			if port is String and PORTS.has(port) and port not in visites:
				visites.append(port)
	var boss: Array[String] = []
	var victoires: Variant = source.get("boss", [])
	if victoires is Array:
		for cle in victoires:
			if cle is String and CAPS_BOSS.has(cle) and cle not in boss:
				boss.append(cle)
	return {
		"cap": cap if PORTS.has(cap) else "", "capacite": capacite, "equipement": equipement,
		"visites": visites, "boss": boss,
	}

static func cap_accessible(navigation: Dictionary, port: String) -> bool:
	if CLASSIQUE in navigation["equipement"] and navigation["cap"] == port:
		return true
	for objet: String in navigation["equipement"]:
		if port in destinations(objet):
			return true
	return false

static func cout_etalonnage(port: String) -> int:
	return maxi(5, ceili(float(PORTS[port]["prix"]) * 0.25))

static func prix_article(port: String, eternelle: bool) -> int:
	return int(PORTS[port]["prix"]) * (6 if eternelle else 2)

static func prix_emplacement(capacite: int) -> int:
	return 250 * capacite * capacite

static func meteo(depart: String, destination: String, timestamp: int) -> Dictionary:
	var route := [depart, destination]
	route.sort()
	var periode := int(floor(float(timestamp) / DUREE_METEO))
	var phase := posmod(hash("/".join(route)) + periode, 7)
	return METEOS[clampi(phase - 3, 0, 3)]

static func prix_traversee(destination: String, meteo_route: Dictionary, solidite: int, resistance: float) -> int:
	var economie := clampf((float(solidite) - 20.0) / 1000.0, 0.0, 0.35)
	var surcout := float(meteo_route["surcout"]) * (1.0 - clampf(resistance / 100.0, 0.0, 0.65))
	return maxi(1, roundi(float(PORTS[destination]["prix"]) * (1.0 - economie) * (1.0 + surcout)))

static func recettes(navigation: Dictionary) -> Array:
	var resultat: Array = []
	for port: String in navigation["visites"]:
		resultat.append(_recette(carte(port), 1, 10, {"156": 1}, prix_article(port, false) / 3.0))
		resultat.append(_recette(eternel(port), 1, 30, {"189": 1, carte(port): 1}, prix_article(port, true) / 3.0))
	return resultat

static func _recette(objet: String, niveau: int, xp: int, composants: Dictionary, prix: float) -> Dictionary:
	var ingredients: Array = []
	for id in composants:
		ingredients.append({"id": id, "quantite": composants[id]})
	return {
		"id": objet, "profession": METIER_NAVIGATEUR, "nom": article(objet)["nom"], "niveau_requis": niveau,
		"item_resultat": objet, "quantite_resultat": 1, "xp": xp, "cout_berry": maxi(1, roundi(prix)),
		"temps": 0, "ingredients": ingredients,
	}
