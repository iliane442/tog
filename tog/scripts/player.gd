# player.gd — joueur : déplacement au clic et animation du pirate
extends CharacterBody2D

@export var speed: float = 300.0

# feuilles de sprites : 4 lignes = sud, ouest, est, nord
const LIGNES := {"sud": 0, "ouest": 1, "est": 2, "nord": 3}
const FRAMES_REPOS := 4
const FRAMES_MARCHE := 6
const FPS_REPOS := 6.0
const FPS_MARCHE := 10.0

# visuels par race : id technique (character_races.name) -> préfixe des sheets
const VISUELS_RACES := {
	"human": "humain_pirate",
	"mink": "mink_pirate",
	"fishman": "fishman_pirate",
}
const RACE_DEFAUT := "human"

var target: Vector2
var _ligne := 0
var _colonne := 0.0
var _texture_repos: Texture2D
var _texture_marche: Texture2D
var _race_chargee := ""

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	target = global_position
	_maj_visuels_race()

# id technique de la race courante du personnage
func _id_technique_race() -> String:
	return str(Personnage.races.get(Personnage.race_id, {}).get("id_technique", RACE_DEFAUT))

# charge les feuilles idle/marche de la race ; si la race n'a pas de visuel,
# affiche l'humain
func _maj_visuels_race() -> void:
	var race := _id_technique_race()
	var prefixe: String = VISUELS_RACES.get(race, RACE_DEFAUT)
	var repos := "res://assets/sprites/%s/%s_idle.png" % [prefixe, prefixe]
	var marche := "res://assets/sprites/%s/%s_walk.png" % [prefixe, prefixe]
	if not (ResourceLoader.exists(repos) and ResourceLoader.exists(marche)):
		prefixe = VISUELS_RACES[RACE_DEFAUT]
		repos = "res://assets/sprites/%s/%s_idle.png" % [prefixe, prefixe]
		marche = "res://assets/sprites/%s/%s_walk.png" % [prefixe, prefixe]
	_texture_repos = load(repos)
	_texture_marche = load(marche)
	sprite.texture = _texture_marche
	sprite.hframes = FRAMES_MARCHE
	_race_chargee = race

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		target = get_global_mouse_position()

func _physics_process(delta: float) -> void:
	var race := _id_technique_race()
	if race != _race_chargee:
		_maj_visuels_race()
	var direction = target - global_position
	var en_mouvement = direction.length() > 5.0
	if en_mouvement:
		velocity = direction.normalized() * speed
		_ligne = _ligne_cardinale(direction)
		_colonne = fmod(_colonne + delta * FPS_MARCHE, float(FRAMES_MARCHE))
	else:
		velocity = Vector2.ZERO
		_colonne = fmod(_colonne + delta * FPS_REPOS, float(FRAMES_REPOS))
	move_and_slide()
	var feuille := _texture_marche if en_mouvement else _texture_repos
	var colonnes := FRAMES_MARCHE if en_mouvement else FRAMES_REPOS
	if sprite.texture != feuille:
		sprite.texture = feuille
		sprite.hframes = colonnes
	sprite.frame = _ligne * colonnes + int(_colonne)

func _ligne_cardinale(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return LIGNES["est"] if direction.x > 0.0 else LIGNES["ouest"]
	return LIGNES["nord"] if direction.y < 0.0 else LIGNES["sud"]
