extends Node2D
# avatar d'un autre joueur connecté au serveur (côté client) :
# sprite + pseudo, qui glisse en douceur vers les positions reçues

const VISUEL_DEFAUT := "humain_pirate"
# planches d'idle et de marche : 4 lignes de direction (sud, ouest,
# est, nord) ; idle = 4 colonnes, marche = 6 — cf. LIGNES / FRAMES
# dans player.gd
const LIGNES := {"sud": 0, "ouest": 1, "est": 2, "nord": 3}
const COLONNES_REPOS := 4
const COLONNES_MARCHE := 6
const FPS_REPOS := 6.0
const FPS_MARCHE := 10.0

var pseudo := ""
var en_combat := false
var visuel := VISUEL_DEFAUT
# vrai si ce joueur fait partie de notre groupe : son pseudo se
# colore en vert sur la map (jaune « en combat » prioritaire)
var _marque_groupe := false

var _sprite: Sprite2D
var _etiquette: Label
var _tween: Tween
var _texture_repos: Texture2D
var _texture_marche: Texture2D
var _ligne := 0
var _colonne := 0.0

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

# anime l'avatar : planche de marche tant que le glissement vers la
# dernière position reçue dure, puis retour au repos sur place
func _process(delta: float) -> void:
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
	visuel = str(prefixe)
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

# état de combat du joueur distant : son avatar quitte la map le temps
# du combat — il est présent dans les arènes des coéquipiers (miroir) et
# sa place sur la carte n'a plus de sens
func maj_combat(actif: bool) -> void:
	en_combat = actif
	visible = not actif
	_appliquer_couleur_pseudo()
	if _etiquette == null:
		return
	if actif:
		_etiquette.text = "%s  (en combat)" % pseudo
	else:
		_etiquette.text = pseudo

# marque (ou démarque) un compagnon de notre groupe de joueurs
func marquer_groupe(actif: bool) -> void:
	_marque_groupe = actif
	_appliquer_couleur_pseudo()

# couleur du pseudo : jaune en combat, vert pour un compagnon de
# groupe, couleur du thème sinon
func _appliquer_couleur_pseudo() -> void:
	if _etiquette == null:
		return
	if en_combat:
		_etiquette.add_theme_color_override("font_color", Color("#ffd166"))
	elif _marque_groupe:
		_etiquette.add_theme_color_override("font_color", Color("#7bd88f"))
	else:
		_etiquette.remove_theme_color_override("font_color")

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
