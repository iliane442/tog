extends RefCounted

const ASSETS := "res://assets/world/alabasta/eau/"
const COLONNES := 6
const RANGEES := 4

const ECUME := [
	preload(ASSETS + "ecume_gauche_128x80.png"),
	preload(ASSETS + "ecume_droite_128x80.png"),
]
const REFLETS := {
	"bassin_canal.png": [preload(ASSETS + "reflets_bassin_canal.png"), Vector2(63, 56)],
	"fontaine.png": [preload(ASSETS + "reflets_fontaine.png"), Vector2(52, 3)],
	"puits.png": [preload(ASSETS + "reflets_puits.png"), Vector2(97, 230)],
}

static func animer_bassins(paysage: Node2D) -> void:
	var animations: Dictionary[String, SpriteFrames] = {}
	for decor in paysage.get_children():
		var sprite := decor as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var fichier := sprite.texture.resource_path.get_file()
		if not REFLETS.has(fichier):
			continue
		var effet: Array = REFLETS[fichier]
		if not animations.has(fichier):
			animations[fichier] = _decouper_atlas(effet[0])
		var reflets := _creer_sprite(animations[fichier])
		var decalage: Vector2 = effet[1]
		if sprite.flip_h:
			var taille := animations[fichier].get_frame_texture(&"default", 0).get_size()
			decalage.x = sprite.texture.get_width() - decalage.x - taille.x
			reflets.flip_h = true
		reflets.position = sprite.get_rect().position + decalage
		sprite.add_child(reflets)

static func animations_ecume() -> Array[SpriteFrames]:
	return [_decouper_atlas(ECUME[0]), _decouper_atlas(ECUME[1])]

static func ajouter_ecume(calque: Node2D, debut: Vector2, fin: Vector2, animation: SpriteFrames) -> void:
	var ecume := _creer_sprite(animation)
	ecume.scale = Vector2(0.5, 0.5)
	ecume.position = Vector2(minf(debut.x, fin.x), minf(debut.y, fin.y) - 2.5)
	calque.add_child(ecume)

static func _creer_sprite(animation: SpriteFrames) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = animation
	sprite.autoplay = &"default"
	return sprite

static func _decouper_atlas(atlas: Texture2D) -> SpriteFrames:
	var animation := SpriteFrames.new()
	animation.set_animation_speed(&"default", 10)
	var taille := atlas.get_size() / Vector2(COLONNES, RANGEES)
	for ligne in RANGEES:
		for colonne in COLONNES:
			var image := AtlasTexture.new()
			image.atlas = atlas
			image.region = Rect2(Vector2(colonne, ligne) * taille, taille)
			image.filter_clip = true
			animation.add_frame(&"default", image)
	return animation
