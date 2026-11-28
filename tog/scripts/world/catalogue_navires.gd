extends RefCounted

const DEPART := "lanterne"
const PORT_REVERSE := "res://scenes/reverse_mountain.tscn"
const PORT_GRAND_LINE := "res://scenes/whisky_peak.tscn"
const GALIONS := ["ateliers", "navigation", "stockage", "vie"]
const PRIX_ATELIER := 10000
const MAX_ATELIERS := 3
const SLOOP := preload("res://assets/world/world-ship-sloop-v1.png")
const BRICK := preload("res://assets/world/world-ship-brig-v1.png")
const FREGATE := preload("res://assets/world/fushia_aventure/navire.png")
const MODELES := {
	"lanterne": {"nom": "La Lanterne", "taille": 140, "cale": 20, "solidite": 20, "tempete": 0,
		"pieces": ["atelier", "cale"], "teinte": Color.WHITE, "sprite": SLOOP},
	"brigantin": {"nom": "Brigantin des courants", "taille": 188, "cale": 45, "solidite": 80, "tempete": 2,
		"pieces": ["atelier", "cale", "cabine"], "teinte": Color("#f1f8ff"), "sprite": BRICK, "prix": 5000, "port": PORT_REVERSE, "precedent": DEPART},
	"grand_large": {"nom": "Frégate du Grand Large", "taille": 228, "cale": 90, "solidite": 180, "tempete": 6,
		"pieces": ["atelier", "cale", "cabine", "cartes"], "teinte": Color("#f0ffda"), "sprite": FREGATE,
		"prix": 25000, "port": PORT_GRAND_LINE, "precedent": "brigantin"},
	"ateliers": {"nom": "La Forge des Marées", "taille": 720, "solidite": 240, "tempete": 7,
		"teinte": Color.WHITE,
		"sprite": preload("res://assets/world/galions/ateliers.tres"), "usage": "Trois pièces aménageables en ateliers de métier."},
	"navigation": {"nom": "L’Étoile du Large", "taille": 780, "solidite": 320, "tempete": 12,
		"teinte": Color.WHITE,
		"sprite": preload("res://assets/world/galions/navigation.tres"), "usage": "Sept emplacements d’équipement naval."},
	"stockage": {"nom": "Le Grand Grenier", "taille": 850, "cale": 240, "solidite": 350, "tempete": 8,
		"teinte": Color.WHITE,
		"sprite": preload("res://assets/world/galions/stockage.tres"), "usage": "Une cale commune de 240 piles d’objets."},
	"vie": {"nom": "La Maison des Flots", "taille": 900, "solidite": 380, "tempete": 8,
		"teinte": Color.WHITE,
		"sprite": preload("res://assets/world/galions/vie.tres"), "usage": "Une chambre à décorer pour chaque membre."},
}

const DECORS := {
	"tapis": ["Corde", "Bleu marine", "Grenat", "Vert mousse"],
	"murs": ["Chêne", "Émeraude", "Indigo", "Brique"],
	"mobilier": ["Coffre", "Bureau", "Bibliothèque"],
}

static func fiche(modele: String) -> Dictionary:
	return MODELES.get(modele, MODELES[DEPART])

static func personnel(modele: String) -> String:
	return modele if MODELES.has(modele) and modele not in GALIONS else DEPART

static func modele_vendu(port: String) -> String:
	for modele in ["brigantin", "grand_large"]:
		if MODELES[modele]["port"] == port:
			return modele
	return ""

static func prix_achat(actuel: String, port: String) -> int:
	var modele := modele_vendu(port)
	if modele.is_empty() or MODELES[modele]["precedent"] != actuel:
		return 0
	return int(MODELES[modele]["prix"])
