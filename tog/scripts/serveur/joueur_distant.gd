extends Node2D
# avatar d'un autre joueur connecté au serveur (côté client) :
# sprite + pseudo, qui glisse en douceur vers les positions reçues

const VISUEL_DEFAUT := "humain_pirate"
# planche d'idle : 4 colonnes d'animation, 4 lignes de direction (sud,
# ouest, est, nord) — cf. FRAMES_REPOS / LIGNES dans player.gd
const COLONNES_REPOS := 4
const LIGNES_REPOS := 4

var pseudo := ""
var en_combat := false
var visuel := VISUEL_DEFAUT

var _sprite: Sprite2D
var _etiquette: Label
var _tween: Tween

func _ready() -> void:
	z_index = 20
	_sprite = Sprite2D.new()
	_appliquer_visuel()
	add_child(_sprite)
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

# apparence du joueur distant (préfixe de planche de sprites, ex.
# humain_pirate, mink_pirate...) : une seule trame de la planche
func definir_visuel(prefixe: String) -> void:
	visuel = str(prefixe)
	_appliquer_visuel()

func _appliquer_visuel() -> void:
	if _sprite == null:
		return
	var chemin := "res://assets/sprites/%s/%s_idle.png" % [visuel, visuel]
	if not ResourceLoader.exists(chemin):
		visuel = VISUEL_DEFAUT
		chemin = "res://assets/sprites/%s/%s_idle.png" % [visuel, visuel]
	_sprite.texture = load(chemin)
	_sprite.hframes = COLONNES_REPOS
	_sprite.vframes = LIGNES_REPOS
	_sprite.frame = 0  # face sud

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
