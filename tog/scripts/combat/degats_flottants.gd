extends Node2D
## Nombre de dégâts flottant, d'après « Damage number » de la
## bibliothèque pixelfx (patch-gg) : le chiffre rouge jaillit dans une
## gerbe blanche, reste blanc un instant, monte en arc, retombe avec
## un écrasement et un petit rebond, puis s'envole en s'estompant.

signal fini

# teinte du chiffre selon l'information portée
const TEINTES := {
	"degats": Color("#ff5a4a"),
	"soin": Color("#7ee081"),
	"critique": Color("#ffd166"),
}
const BLANC := Color("#ffffff")
const CONTOUR := Color("#1a0508")
const POP_COLOREE := Color("#ff9a86")  # gerbe de fin de flash

const DUREE := 1.05           # durée totale (s), comme le modèle
const FONDU_DEBUT := 0.84      # début de l'envol final
const SOL := -8.0               # ligne d'atterrissage relative au spawn
const GRAVITE := 900.0

var texte := "-27"
var type := "degats"

var _cadre: Node2D
var _devant: Label
var _derriere: Label
var _epines: Array = []
var _t := 0.0
var _x := 0.0
var _y := SOL
var _vx := 0.0
var _vy := 0.0
var _rebonds := 0
var _ecrase := 0.0

func _ready() -> void:
	z_index = 100
	var teinte: Color = TEINTES.get(type, TEINTES["degats"])

	# gerbe de pointes à l'impact : longueurs et directions tirées
	# une fois pour que le rendu soit stable pendant ses ~0,1 s
	for i in range(9):
		_epines.append({
			"angle": TAU * i / 9.0 + randf_range(-0.2, 0.2),
			"longueur": randf_range(12.0, 20.0),
		})

	_cadre = Node2D.new()
	add_child(_cadre)

	# le contour : une copie sombre décalée derrière le chiffre, les
	# fontes bitmap ne gérant pas les outlines
	_derriere = _fabriquer_etiquette(CONTOUR, Vector2(2, 2))
	_devant = _fabriquer_etiquette(BLANC, Vector2.ZERO)
	_cadre.add_child(_derriere)
	_cadre.add_child(_devant)
	_cadre.position = Vector2(_x, _y)

	# le tir : vers le haut et de côté, comme un petit corps
	var cote := 1.0 if randf() < 0.5 else -1.0
	_x = 0.0
	_y = SOL - randf_range(0.0, 2.0)
	_vx = cote * randf_range(24.0, 42.0)
	_vy = -175.0
	_cadre.position = Vector2(_x, _y)

func _fabriquer_etiquette(couleur: Color, decalage: Vector2) -> Label:
	var etiquette := Label.new()
	etiquette.text = texte
	etiquette.add_theme_color_override("font_color", couleur)
	etiquette.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	etiquette.add_theme_constant_override("shadow_offset_y", 2)
	etiquette.size = etiquette.get_minimum_size()
	# centrer sur le pivot du cadre : le cadre gère l'arc et
	# l'écrasement, l'étiquette reste centrée dessus
	etiquette.position = -etiquette.size / 2.0 + decalage
	return etiquette

func _process(delta: float) -> void:
	_t += delta
	if _rebonds < 2:
		_vy += GRAVITE * delta
		_vx -= _vx * 2.0 * delta
		_x += _vx * delta
		_y += _vy * delta
		if _y >= SOL and _vy > 0.0:
			_y = SOL
			_ecrase = 1.0
			_rebonds += 1
			_vy = -_vy * 0.36 if _rebonds < 2 else 0.0
	_ecrase = maxf(_ecrase - delta / 0.09, 0.0)

	# punch-out puis ressort amorti : le chiffre naît énorme et
	# retombe à sa taille en oscillant de moins en moins
	var ressort := 1.0 + 0.7 * exp(-_t * 22.0) * cos(_t * 30.0)
	var sx := ressort
	var sy := ressort
	if _ecrase > 0.0:
		sx *= 1.0 + 0.18 * _ecrase
		sy *= 1.0 - 0.2 * _ecrase
	elif _rebonds < 2 and absf(_vy) > 120.0:
		sx *= 0.92
		sy *= 1.1
	_cadre.scale = Vector2(sx, sy)

	# envol final : le chiffre se décolle et s'estompe
	var fondu := clampf((_t - FONDU_DEBUT) / (DUREE - 0.04 - FONDU_DEBUT), 0.0, 1.0)
	_cadre.position = Vector2(_x, _y - 6.0 * fondu * fondu)
	modulate.a = 1.0 - fondu

	_maj_couleur()
	if _t < 0.16:
		queue_redraw()
	if _t >= DUREE:
		fini.emit()
		queue_free()

# le flash d'impact : blanc plein deux frames, teinte mélangée une
# demi-frame, puis la teinte finale du type
func _maj_couleur() -> void:
	var teinte: Color = TEINTES.get(type, TEINTES["degats"])
	var couleur := teinte
	if _t < 0.035:
		couleur = BLANC
	elif _t < 0.07:
		couleur = teinte.lerp(BLANC, 0.4)
	_devant.add_theme_color_override("font_color", couleur)

# la gerbe : pointes blanches qui s'écartent puis rougeoient, et un
# cœur blanc au moment exact de l'impact
func _draw() -> void:
	if _t >= 0.09:
		return
	var facteur := 1.3 if _t >= 0.035 else 1.0
	var couleur := BLANC if _t < 0.035 else POP_COLOREE
	for epine in _epines:
		var angle: float = epine["angle"]
		var longueur: float = epine["longueur"] * facteur
		draw_line(Vector2.ZERO, Vector2.from_angle(angle) * longueur, couleur, 2.0)
	if _t < 0.07:
		draw_circle(Vector2.ZERO, 3.5, BLANC)
