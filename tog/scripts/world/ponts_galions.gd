extends RefCounted

const AXE := 9
const PROUE := 2
const LONGUEUR_ESCALIER := 2
const LONGUEUR_PONT := 4

const PLANS := {
	"ateliers": {
		"largeurs": [1, 3, 5, 7, 9, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11],
		"depart": Vector2i(12, 16), "quai": Vector2i(14, 16), "trappe": Vector2i(9, 13),
		"mobilier": {
			"mat": [Vector2i(9, 8), Vector2i(9, 15)],
			"forge": [Vector2i(5, 9)], "etabli": [Vector2i(13, 10)], "alambic": [Vector2i(5, 13)],
		},
	},
	"navigation": {
		"largeurs": [1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 11, 11, 11, 11, 11, 11, 9],
		"depart": Vector2i(11, 18), "quai": Vector2i(13, 18), "trappe": Vector2i(9, 15),
		"mobilier": {
			"mat": [Vector2i(9, 9), Vector2i(9, 14)],
			"astrolabe": [Vector2i(9, 5)], "cartes": [Vector2i(12, 13)], "coffre": [Vector2i(6, 16)],
		},
	},
	"stockage": {
		"largeurs": [3, 5, 7, 9, 11, 13, 13, 15, 15, 15, 15, 15, 15, 15, 15],
		"depart": Vector2i(13, 16), "quai": Vector2i(16, 16), "trappe": Vector2i(9, 14),
		"mobilier": {
			"mat": [Vector2i(9, 8), Vector2i(9, 13)],
			"caisses": [Vector2i(4, 9), Vector2i(5, 12), Vector2i(12, 8), Vector2i(13, 12), Vector2i(14, 13)],
			"tonneaux": [Vector2i(4, 10), Vector2i(5, 13), Vector2i(5, 15), Vector2i(13, 9), Vector2i(13, 15)],
			"grue": [Vector2i(15, 11)],
		},
	},
	"vie": {
		"largeurs": [1, 3, 5, 7, 9, 11, 13, 13, 13, 13, 13, 15, 15, 15, 15, 15],
		"depart": Vector2i(13, 17), "quai": Vector2i(16, 17), "trappe": Vector2i(9, 16),
		"mobilier": {
			"mat": [Vector2i(9, 9), Vector2i(9, 14)],
			"jardiniere": [Vector2i(4, 8), Vector2i(14, 8), Vector2i(4, 16), Vector2i(14, 16), Vector2i(5, 22), Vector2i(13, 22)],
			"salon": [Vector2i(6, 20), Vector2i(12, 20)], "lanterne": [Vector2i(9, 5), Vector2i(9, 22)],
		},
	},
}

static func escaliers(plan: Dictionary) -> Array[Rect2i]:
	var largeurs: Array = plan["largeurs"]
	var x := AXE + floori(int(largeurs.max()) * 0.5) - 2
	var depart: Vector2i = plan["quai"] + Vector2i.DOWN
	return [Rect2i(x, depart.y, 2, LONGUEUR_ESCALIER),
		Rect2i(x, depart.y + LONGUEUR_ESCALIER + LONGUEUR_PONT, 2, LONGUEUR_ESCALIER)]

static func rangees(plan: Dictionary) -> Array[Rect2i]:
	var bandes: Array[Rect2i] = []
	var largeurs: Array = plan["largeurs"]
	var liaisons := escaliers(plan)
	var largeur_poupe := int(largeurs.max())
	for y in range(PROUE, liaisons[1].end.y + LONGUEUR_PONT):
		var largeur := int(largeurs[y - PROUE]) if y < liaisons[0].position.y else largeur_poupe
		bandes.append(Rect2i(AXE - floori(largeur * 0.5), y, largeur, 1))
	return bandes
