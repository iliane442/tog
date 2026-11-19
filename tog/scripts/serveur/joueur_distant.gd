extends Node2D
# avatar d'un autre joueur connecté au serveur (côté client) :
# sprite + pseudo, qui glisse en douceur vers les positions reçues

const TEXTURE := preload("res://assets/sprites/humain_pirate/humain_pirate_idle.png")

var pseudo := ""
var en_combat := false

var _etiquette: Label
var _tween: Tween

func _ready() -> void:
	z_index = 20
	var sprite := Sprite2D.new()
	sprite.texture = TEXTURE
	add_child(sprite)
	_etiquette = Label.new()
	maj_combat(en_combat)
	_etiquette.position = Vector2(-40, -58)
	_etiquette.custom_minimum_size = Vector2(128, 0)
	_etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiquette.add_theme_font_size_override("font_size", 14)
	_etiquette.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_etiquette.add_theme_constant_override("shadow_offset_x", 1)
	_etiquette.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_etiquette)

# affiche l'état de combat du joueur distant sur son pseudo
func maj_combat(actif: bool) -> void:
	en_combat = actif
	if _etiquette == null:
		return
	if actif:
		_etiquette.text = "%s  (en combat)" % pseudo
		_etiquette.add_theme_color_override("font_color", Color("#ffd166"))
	else:
		_etiquette.text = pseudo
		_etiquette.remove_theme_color_override("font_color")

# glisse vers la dernière position publiée (~10 Hz)
func viser(position_cible: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", position_cible, 0.15)
