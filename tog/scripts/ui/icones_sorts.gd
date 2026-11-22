extends RefCounted

const COLONNES := 4
const TAILLE := 96.0
const PLANCHES := [
	[
		preload("res://assets/sorts/techniques.png"),
		[1, 2, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
	],
	[
		preload("res://assets/sorts/techniques-haki.png"),
		[21, 22, 23, 24, 25, 26, 27, 28, 29, 31, 32, 33, 34, 6, 178, 179],
	],
	[
		preload("res://assets/sorts/caoutchouc-flamme-magma.png"),
		[3, 4, 5, 130, 132, 100, 101, 133, 134, 135, 114, 115, 154, 155, 156, 176],
	],
	[
		preload("res://assets/sorts/glace-foudre-lumiere.png"),
		[104, 105, 139, 140, 141, 102, 103, 136, 137, 138, 112, 113, 151, 152, 153, 175],
	],
	[
		preload("res://assets/sorts/tenebres-bistouri-fils.png"),
		[108, 109, 145, 146, 147, 110, 111, 148, 149, 150, 126, 127, 172, 173, 174, 129],
	],
	[
		preload("res://assets/sorts/leopard-fleurs-fumee.png"),
		[106, 107, 142, 143, 144, 116, 117, 157, 158, 159, 120, 121, 163, 164, 165, 128],
	],
	[
		preload("res://assets/sorts/sable-seisme-poison.png"),
		[118, 119, 160, 161, 162, 122, 123, 166, 167, 168, 124, 125, 169, 170, 171, 177],
	],
	[
		preload("res://assets/sorts/classes-lames-tirs.png"),
		[200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214],
	],
	[
		preload("res://assets/sorts/classes-soins-musique.png"),
		[215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229],
	],
	[
		preload("res://assets/sorts/classes-ateliers-navigation.png"),
		[230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244],
	],
	[
		preload("res://assets/sorts/classes-archeologie.png"),
		[245, 246, 247, 248, 249],
	],
]
const ICONE_DEFAUT := preload("res://addons/pixel_ui_fantasy/icons/scroll.png")
const ICONES_DE_SECOURS := {
	"attack": preload("res://addons/pixel_ui_fantasy/icons/sword.png"),
	"heal": preload("res://addons/pixel_ui_fantasy/icons/potion_red.png"),
	"defense": preload("res://addons/pixel_ui_fantasy/icons/shield.png"),
	"buff": preload("res://addons/pixel_ui_fantasy/icons/gem.png"),
	"debuff": preload("res://addons/pixel_ui_fantasy/icons/cross.png"),
	"control": preload("res://addons/pixel_ui_fantasy/icons/cross.png"),
}

static var _icones: Dictionary[String, Texture2D] = {}

static func pour_sort(id_sort: String, type_sort: String) -> Texture2D:
	if _icones.is_empty():
		_charger_planches()
	return _icones.get(id_sort, ICONES_DE_SECOURS.get(type_sort.to_lower(), ICONE_DEFAUT))

static func _charger_planches() -> void:
	for planche in PLANCHES:
		var atlas: Texture2D = planche[0]
		var ids: Array = planche[1]
		for index in ids.size():
			var colonne := index % COLONNES
			var ligne := floori(float(index) / COLONNES)
			var icone := AtlasTexture.new()
			icone.atlas = atlas
			icone.region = Rect2(Vector2(colonne, ligne) * TAILLE, Vector2.ONE * TAILLE)
			icone.filter_clip = true
			_icones[str(ids[index])] = icone
