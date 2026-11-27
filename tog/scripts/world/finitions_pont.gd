extends RefCounted

const DEFAUT := "teck"
const CHOIX := {
	"teck": {"nom": "Teck naturel", "planche": Color("#cf9c61"), "bordage": Color("#835530"), "moulure": Color("#e1b582")},
	"chene": {"nom": "Chêne patiné", "planche": Color("#9a714f"), "bordage": Color("#62432d"), "moulure": Color("#bd946e")},
}
const CHEMIN_GRAIN := "res://assets/world/galions/bois-de-pont.png"
const LONGUEUR := 192
const LARGEUR := 32
const DECALES := [0, 73, 141, 48]
const BANDES_GRAIN := [6, 50, 93, 26]

static var _textures: Dictionary = {}

static func normaliser(id: String) -> String:
	return id if CHOIX.has(id) else DEFAUT

static func fiche(id: String) -> Dictionary:
	return CHOIX[normaliser(id)]

static func texture(id: String) -> Texture2D:
	id = normaliser(id)
	if not _textures.has(id):
		_textures[id] = ImageTexture.create_from_image(_composer_planches(CHOIX[id]["planche"]))
	return _textures[id]

# Deux longueurs par rangée, avec les joints décalés et les clous aux extrémités.
# Le motif est périodique sur les deux axes pour rester continu à travers le pont.
static func _composer_planches(bois: Color) -> Image:
	var grain := (load(CHEMIN_GRAIN) as Texture2D).get_image()
	var image := Image.create_empty(LONGUEUR * 2, LARGEUR * DECALES.size(), false, Image.FORMAT_RGB8)
	for ligne: int in DECALES.size():
		for y: int in LARGEUR:
			@warning_ignore("integer_division")
			var source_y: int = BANDES_GRAIN[ligne] + y * 10 / LARGEUR
			for x: int in image.get_width():
				var planche: int = x + DECALES[ligne]
				var joint := posmod(planche, LONGUEUR)
				var alternance := floori(float(planche) / LONGUEUR) % 2
				var nuance := grain.get_pixel(posmod(x + ligne * 29, grain.get_width()), source_y).get_luminance()
				var couleur := bois.lerp(Color("#4f3325"), (1.0 - nuance) * 0.32 + alternance * 0.085)
				if y == 0 or joint == 0:
					couleur = bois.darkened(0.54)
				elif y == 1 or joint == 1:
					couleur = couleur.lightened(0.19)
				else:
					var bout := mini(absi(joint - 7), absi(joint - (LONGUEUR - 7)))
					var clou := mini(absi(y - 8), absi(y - (LARGEUR - 8)))
					if bout + clou <= 2:
						couleur = Color("#54483a").lightened(0.33) if y in [7, LARGEUR - 9] else Color("#54483a")
				image.set_pixel(x, ligne * LARGEUR + y, couleur)
	return image
