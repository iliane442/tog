extends Node2D
# avatar d'un autre joueur connecté au serveur (côté client) :
# sprite + pseudo, qui glisse en douceur vers les positions reçues

const VISUEL_DEFAUT := "humain_pirate"
const VISUEL_JOUEUR := preload("res://scripts/visuel_joueur.gd")
# planches d'idle et de marche : 4 lignes de direction (sud, ouest,
# est, nord) ; idle = 4 colonnes, marche = 6 — cf. LIGNES / FRAMES
# dans player.gd
const LIGNES := {"sud": 0, "ouest": 1, "est": 2, "nord": 3}
const COLONNES_REPOS := 4
const COLONNES_MARCHE := 6
const FPS_REPOS := 6.0
const FPS_MARCHE := 10.0

var pseudo := "":
	set(valeur):
		if pseudo == valeur:
			return
		pseudo = valeur
		_actualiser_etiquette()
var en_combat := false
var visuel := VISUEL_DEFAUT
var _marque_groupe := false

var _sprite: Sprite2D
var _etiquette: Label
var _tween: Tween
var _texture_repos: Texture2D
var _texture_marche: Texture2D
var _ligne := 0
var _colonne := 0.0
var _filtre_etage: Callable

func _ready() -> void:
	add_to_group("entites_minicarte")
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("avatar_sur_mon_etage"):
		_filtre_etage = Callable(scene, "avatar_sur_mon_etage")
	z_index = 20
	_sprite = Sprite2D.new()
	_appliquer_visuel()
	add_child(_sprite)
	_etiquette = Label.new()
	_etiquette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiquette.add_theme_font_size_override("font_size", 14)
	_etiquette.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_etiquette.add_theme_constant_override("shadow_offset_x", 1)
	_etiquette.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_etiquette)
	maj_combat(en_combat)

func repere_minicarte() -> Dictionary:
	return {"categorie": "joueurs", "nom": pseudo, "groupe": _marque_groupe,
		"role": "Dans ton groupe" if _marque_groupe else "Joueur"}

# anime l'avatar : planche de marche tant que le glissement vers la
# dernière position reçue dure, puis retour au repos sur place
func _process(delta: float) -> void:
	if _filtre_etage.is_valid():
		visible = not en_combat and bool(_filtre_etage.call(global_position))
	var en_mouvement := _tween != null and _tween.is_valid()
	var colonnes := COLONNES_MARCHE if en_mouvement else COLONNES_REPOS
	_colonne = fmod(_colonne + delta * (FPS_MARCHE if en_mouvement else FPS_REPOS), float(colonnes))
	var feuille := _texture_marche if en_mouvement else _texture_repos
	if _sprite.texture != feuille:
		_sprite.texture = feuille
		_sprite.hframes = colonnes
	_sprite.frame = _ligne * colonnes + int(_colonne)

# apparence du joueur distant (préfixe de planche de sprites, ex.
# humain_pirate, mink_pirate...) : planches de repos et de marche
func definir_visuel(prefixe: String) -> void:
	if prefixe == visuel:
		return
	visuel = prefixe
	_appliquer_visuel()

func _appliquer_visuel() -> void:
	if _sprite == null:
		return
	var chemin_repos := "res://assets/sprites/%s/%s_idle.png" % [visuel, visuel]
	var chemin_marche := "res://assets/sprites/%s/%s_walk.png" % [visuel, visuel]
	if not (ResourceLoader.exists(chemin_repos) and ResourceLoader.exists(chemin_marche)):
		visuel = VISUEL_DEFAUT
		chemin_repos = "res://assets/sprites/%s/%s_idle.png" % [visuel, visuel]
		chemin_marche = "res://assets/sprites/%s/%s_walk.png" % [visuel, visuel]
	_texture_repos = load(chemin_repos)
	_texture_marche = load(chemin_marche)
	_sprite.texture = _texture_repos
	_sprite.hframes = COLONNES_REPOS
	_sprite.vframes = LIGNES.size()
	_sprite.frame = _ligne * COLONNES_REPOS  # direction courante, face sud au départ
	VISUEL_JOUEUR.appliquer_gabarit(_sprite, visuel, 0.0)
	_actualiser_etiquette()

# état de combat du joueur distant : son avatar quitte la map le temps
# du combat — il est présent dans les arènes des coéquipiers (miroir) et
# sa place sur la carte n'a plus de sens
func maj_combat(actif: bool) -> void:
	en_combat = actif
	visible = not actif
	_actualiser_etiquette()

# marque (ou démarque) un compagnon de notre groupe de joueurs
func marquer_groupe(actif: bool) -> void:
	_marque_groupe = actif
	_actualiser_etiquette()

func _actualiser_etiquette() -> void:
	if _etiquette == null:
		return
	_etiquette.text = ("[G] " if _marque_groupe else "") + pseudo
	if _marque_groupe:
		_etiquette.add_theme_color_override("font_color", Color("#8de8e5"))
		_etiquette.add_theme_color_override("font_outline_color", Color("#142433"))
		_etiquette.add_theme_constant_override("outline_size", 6)
		_etiquette.add_theme_font_size_override("font_size", 17)
	else:
		_etiquette.remove_theme_color_override("font_color")
		_etiquette.remove_theme_color_override("font_outline_color")
		_etiquette.remove_theme_constant_override("outline_size")
		_etiquette.add_theme_font_size_override("font_size", 14)
	_etiquette.reset_size()
	_etiquette.position.x = -_etiquette.size.x / 2.0
	_etiquette.position.y = _sprite.position.y + _sprite.get_rect().position.y * _sprite.scale.y - 10.0

# ligne de direction (sud, ouest, est, nord) d'un vecteur de déplacement
func _ligne_cardinale(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return LIGNES["est"] if direction.x > 0.0 else LIGNES["ouest"]
	return LIGNES["nord"] if direction.y < 0.0 else LIGNES["sud"]

# glisse vers la dernière position publiée (~10 Hz) ; le sens du
# déplacement oriente le sprite (il garde sa direction en cas d'arrêt
# bref entre deux paquets)
func viser(position_cible: Vector2) -> void:
	var direction := position_cible - global_position
	if direction.length() > 1.0:
		_ligne = _ligne_cardinale(direction)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", position_cible, 0.15)
