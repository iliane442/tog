# Lecture des planches de VFX. Le lecteur peut être cadencé par la
# chorégraphie d'un sort ou jouer seul pour les attaques des ennemis.
extends Node2D

const CYCLES_BOUCLE := 2
const SEUIL_PIEDS := 0.8
const DECALAGE_PIEDS := 16
const Z_INDEX := 50

static var _cache_planches: Dictionary = {}

var _sprite: Sprite2D
var _images: Array[AtlasTexture] = []
var _ancre := Vector2.ZERO
var _duree := 0.0
var _boucle := false
var _en_cours := false

func _ready() -> void:
	z_index = Z_INDEX
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_sprite)

func configurer_ligne(details: Dictionary) -> void:
	configure(str(details.get("sprite_sheet_path", "")), int(details.get("frame_count", 1)),
		int(details.get("frame_delay_ms", 100)), int(details.get("loop", 0)) == 1,
		int(details.get("frame_width", 32)), int(details.get("frame_height", 32)))

func configure(chemin: String, nb_frames: int, delai_ms: int, boucle: bool, largeur_frame: int, hauteur_frame: int) -> void:
	if chemin.is_empty():
		return
	var chemin_png := chemin if chemin.begins_with("res://") else "res://" + chemin
	var coupure := Vector2i(maxi(largeur_frame, 1), maxi(hauteur_frame, 1))
	var cle := "%s|%d|%d|%d" % [chemin_png, nb_frames, coupure.x, coupure.y]
	if not _cache_planches.has(cle):
		_cache_planches[cle] = _lire_planche(chemin_png, maxi(nb_frames, 1), coupure)
	var planche: Dictionary = _cache_planches[cle]
	if planche.is_empty():
		return
	_images = planche["images"]
	_ancre = planche["ancre"]
	_duree = float(_images.size()) * maxf(float(delai_ms) / 1000.0, 0.016)
	_boucle = boucle

static func _lire_planche(chemin: String, nb_frames: int, coupure: Vector2i) -> Dictionary:
	if not ResourceLoader.exists(chemin, "Texture2D"):
		return {}
	var feuille := load(chemin) as Texture2D
	if feuille == null:
		return {}
	var regions: Array[Rect2] = []
	var ancre := Vector2(coupure) / 2.0
	var chemin_atlas := chemin.get_basename() + ".json"
	var atlas: Variant = null
	if FileAccess.file_exists(chemin_atlas):
		atlas = JSON.parse_string(FileAccess.get_file_as_string(chemin_atlas))
	if atlas is Dictionary and atlas.get("frames") is Array:
		var point: Dictionary = atlas.get("meta", {}).get("anchor", {})
		ancre = Vector2(point.get("x", ancre.x), point.get("y", ancre.y))
		for image: Dictionary in atlas["frames"]:
			var r: Dictionary = image.get("frame", {})
			regions.append(Rect2(r.get("x", 0.0), r.get("y", 0.0), r.get("w", 0.0), r.get("h", 0.0)))
	else:
		# Les JSON d'atlas peuvent être absents d'un export. Toutes les
		# planches du jeu ont aussi une grille régulière exploitable.
		var colonnes := maxi(floori(float(feuille.get_width()) / coupure.x), 1)
		for index in nb_frames:
			regions.append(Rect2(
				(index % colonnes) * coupure.x, floori(float(index) / colonnes) * coupure.y,
				coupure.x, coupure.y))
	var images: Array[AtlasTexture] = []
	var limites := Rect2(Vector2.ZERO, feuille.get_size())
	for index in mini(nb_frames, regions.size()):
		var region := regions[index]
		if not region.has_area() or not limites.encloses(region):
			continue
		var texture := AtlasTexture.new()
		texture.atlas = feuille
		texture.region = region
		texture.filter_clip = true
		images.append(texture)
	return {"images": images, "ancre": ancre}

func positionner(corps: Vector2, pieds: Vector2, taille_max: float, angle: float, centrer: bool) -> bool:
	if _images.is_empty():
		return false
	var taille := _images[0].get_size()
	var ancre := _ancre.clamp(Vector2.ZERO, taille) if not centrer else taille / 2.0
	global_position = pieds if ancre.y > SEUIL_PIEDS * taille.y else corps
	rotation = angle
	scale = Vector2.ONE * (taille_max / maxf(taille.x, taille.y))
	_sprite.offset = -ancre
	return true

func afficher_progression(progression: float) -> void:
	if not _images.is_empty():
		var index := clampi(int(progression * _images.size()), 0, _images.size() - 1)
		if _sprite.texture != _images[index]:
			_sprite.texture = _images[index]

func appliquer_materiau(materiau: Material) -> void:
	_sprite.material = materiau

# Lecture autonome pour les attaques qui utilisent directement une planche.
func jouer(position_globale: Vector2) -> void:
	if _en_cours:
		return
	if _images.is_empty():
		queue_free()
		return
	_en_cours = true
	var taille := _images[0].get_size()
	positionner(position_globale, position_globale + Vector2(0, DECALAGE_PIEDS),
		maxf(taille.x, taille.y), 0.0, false)
	afficher_progression(0.0)
	var lecture := create_tween()
	for _cycle in (CYCLES_BOUCLE if _boucle else 1):
		lecture.tween_method(afficher_progression, 0.0, 1.0, _duree)
	lecture.tween_callback(queue_free)
