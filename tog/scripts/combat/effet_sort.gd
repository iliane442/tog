# effet_sort.gd — effet visuel d'un sort : spritesheet (atlas PixelLab)
# joué sur la cible puis auto-libéré. Instancié par player.gd quand un
# sort touche ; les données viennent de la table `animations`
# (entity_type = 'skill', entity_id = id du sort).
extends Node2D

# cycles joués quand l'animation est déclarée en boucle
const CYCLES_BOUCLE := 2
# ancre située dans le bas de la cellule -> l'effet se cale aux pieds du
# personnage (les effets d'aura et de soin sont dessinés pieds alignés)
const SEUIL_PIEDS := 0.8
# distance du centre du corps aux pieds (demi-tuile de 32 px)
const DECALAGE_PIEDS := 16
# affiché au-dessus des entités
const Z_INDEX := 50

var _feuille: Texture2D
var _sprite: Sprite2D
var _regions: Array = []  # Rect2 de chaque frame, depuis l'atlas json
var _ancre := Vector2.ZERO
var _nb_frames := 1
var _delai := 0.1
var _boucle := false
var _en_cours := false

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.z_index = Z_INDEX
	_sprite.centered = false
	add_child(_sprite)

# configure depuis une ligne de `animations` : chemin de spritesheet
# (avec ou sans préfixe res://), nombre de frames, délai et boucle.
# L'atlas .json qui accompagne la feuille donne les frames et l'ancre ;
# sans json, découpe régulière avec les dimensions de frame fournies.
func configure(chemin: String, nb_frames: int, delai_ms: int, boucle: bool, largeur_frame: int, hauteur_frame: int) -> void:
	var chemin_png := chemin if chemin.begins_with("res://") else "res://" + chemin
	_feuille = load(chemin_png)
	_nb_frames = maxi(nb_frames, 1)
	_delai = maxi(float(delai_ms) / 1000.0, 0.016)
	_boucle = boucle
	var texte := FileAccess.get_file_as_string(chemin_png.get_basename() + ".json")
	var atlas: Variant = JSON.parse_string(texte)
	if atlas is Dictionary and atlas.get("frames", []) is Array:
		var ancre: Dictionary = atlas.get("meta", {}).get("anchor", {})
		_ancre = Vector2(float(ancre.get("x", 0.0)), float(ancre.get("y", 0.0)))
		for frame in atlas["frames"]:
			var f: Dictionary = frame.get("frame", {})
			_regions.append(Rect2(float(f.get("x", 0.0)), float(f.get("y", 0.0)), float(f.get("w", 0.0)), float(f.get("h", 0.0))))
	else:
		# découpe régulière ligne par ligne, sans atlas
		var colonnes := 1
		if _feuille != null:
			colonnes = maxi(int(_feuille.get_width()) / maxi(largeur_frame, 1), 1)
		for i in _nb_frames:
			_regions.append(Rect2(
				(i % colonnes) * largeur_frame, (i / colonnes) * hauteur_frame,
				largeur_frame, hauteur_frame))

# joue l'effet à la position donnée (centre de la cible) puis se libère
func jouer(position_globale: Vector2) -> void:
	if _feuille == null or _regions.is_empty() or _en_cours:
		queue_free()
		return
	_en_cours = true
	# ancre basse -> cale sur les pieds plutôt que le centre du corps
	var decal := Vector2.ZERO
	_ancre = Vector2(minf(_ancre.x, _regions[0].size.x), minf(_ancre.y, _regions[0].size.y))
	if _ancre.y > SEUIL_PIEDS * _regions[0].size.y:
		decal = Vector2(0, DECALAGE_PIEDS)
	global_position = position_globale + decal
	_sprite.offset = -_ancre
	var cycles := CYCLES_BOUCLE if _boucle else 1
	for _c in cycles:
		for index in mini(_nb_frames, _regions.size()):
			_appliquer_frame(index)
			await get_tree().create_timer(_delai).timeout
			if not is_inside_tree():
				return
	queue_free()

func _appliquer_frame(index: int) -> void:
	var texture := AtlasTexture.new()
	texture.atlas = _feuille
	texture.region = _regions[index]
	_sprite.texture = texture
