extends Node2D

const VISUELS := preload("res://scripts/combat/visuels_sorts.gd")
const PLANCHE := preload("res://scripts/combat/effet_sort.gd")
const PALETTE_SORT := preload("res://assets/shaders/palette_sort.gdshader")
const TRAJET := VISUELS.Trajet
const IMPACT := VISUELS.Impact
const ANGLE_OR := 2.399963
const PLANCHES_HORIZONTALES := [
	"tog_fumee_beam.png", "tog_plasma_beam.png", "tog_ice_spike_line.png", "tog_tracer_bolt.png",
]

var cible_id: int
var _trajet: int
var _impact: int
var _nombre: int
var _amplitude: float
var _coeur: Color
var _matiere: Color
var _ombre: Color
var _angle_initial: float
var _source: Vector2
var _corps: Vector2
var _sol_source: Vector2
var _direction: Vector2
var _planche: PLANCHE
var _temps := 0.0
var _charge: float
var _voyage: float
var _duree_impact: float
var _touche: bool

func jouer(id: int, profil: Array, lanceur: Node2D, cible: Node2D, details: Dictionary, touche: bool) -> void:
	z_index = 65
	_touche = touche
	cible_id = cible.get_instance_id() if touche else 0
	global_position = cible.global_position
	if not touche and lanceur != cible:
		var direction := lanceur.global_position.direction_to(cible.global_position)
		global_position += direction * 24.0 + direction.orthogonal() * 37.0
	_sol_source = to_local(lanceur.global_position)
	_source = to_local(_centre(lanceur))
	_corps = _centre(cible) - cible.global_position
	_direction = _sol_source.direction_to(Vector2.ZERO)
	if _direction.is_zero_approx():
		_direction = Vector2.RIGHT
	_angle_initial = fposmod(float(id) * ANGLE_OR, TAU)
	_trajet = profil[0] if lanceur != cible else TRAJET.LOCAL
	_impact = profil[1]
	var palette: Array = VISUELS.PALETTES[profil[2]]
	_coeur = palette[0]
	_matiere = palette[1]
	_ombre = palette[2]
	_nombre = int(profil[3])
	_amplitude = float(profil[4])
	_charge = 0.055 + 0.06 * _amplitude
	_voyage = _temps_de_trajet()
	_duree_impact = 0.28 + 0.18 * _amplitude + 0.025 * _nombre if touche else 0.16
	if touche and not details.is_empty():
		_preparer_planche(details)
	queue_redraw()

func _centre(entite: Node2D) -> Vector2:
	var sprite := entite.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return entite.global_position + Vector2(0, -25)
	return sprite.to_global(sprite.get_rect().get_center())

func _temps_de_trajet() -> float:
	match _trajet:
		TRAJET.LOCAL:
			return 0.0
		TRAJET.ESTOC, TRAJET.RAYON:
			return 0.115
		TRAJET.CHUTE, TRAJET.CHUTE_POING, TRAJET.COMETE:
			return 0.19 + 0.018 * _nombre
		_:
			return clampf(_source.distance_to(_corps) / 680.0, 0.14, 0.30) + 0.017 * (_nombre - 1)

func _preparer_planche(details: Dictionary) -> void:
	_planche = PLANCHE.new()
	_planche.configurer_ligne(details)
	_planche.hide()
	add_child(_planche)
	_planche.z_index = -1
	var horizontale: bool = str(details.get("sprite_sheet_path", "")).get_file() in PLANCHES_HORIZONTALES
	var angle := _direction.angle() if horizontale else 0.0
	var taille := 102.0 * _amplitude
	if not _planche.positionner(to_global(_corps), global_position, taille, angle, horizontale):
		_planche.queue_free()
		_planche = null
		return
	var materiau := ShaderMaterial.new()
	materiau.shader = PALETTE_SORT
	materiau.set_shader_parameter("ombre", _ombre)
	materiau.set_shader_parameter("matiere", _matiere)
	materiau.set_shader_parameter("coeur", _coeur)
	_planche.appliquer_materiau(materiau)

func _process(delta: float) -> void:
	_temps += delta
	var impact := _temps - _charge - _voyage
	if impact >= _duree_impact:
		queue_free()
		return
	if _planche != null and impact >= 0.0:
		var t := impact / _duree_impact
		_planche.show()
		_planche.modulate.a = 0.9 * minf((1.0 - t) * 4.0, 1.0)
		_planche.afficher_progression(t)
	queue_redraw()

func _draw() -> void:
	if _temps < _charge:
		_dessiner_charge(_temps / _charge)
	elif _temps < _charge + _voyage:
		_dessiner_trajet((_temps - _charge) / _voyage)
	else:
		_dessiner_impact(clampf((_temps - _charge - _voyage) / _duree_impact, 0.0, 1.0))

func _dessiner_charge(t: float) -> void:
	var centre := _source
	var rayon := (21.0 - 13.0 * t) * _amplitude
	_arc(centre, Vector2(rayon, rayon * 0.7), _angle_initial + t, TAU * 0.72, _teinte(_matiere, t * 0.85), 2.0)
	for index in mini(_nombre + 2, 7):
		var angle := index * TAU / mini(_nombre + 2, 7) + _angle_initial
		var p := centre + Vector2.from_angle(angle) * (rayon + 7.0)
		_losange(p, 3.2 * t, angle, _teinte(_coeur, t))
	if _trajet in [TRAJET.CHUTE, TRAJET.CHUTE_POING, TRAJET.COMETE]:
		_arc(Vector2.ZERO, Vector2(24, 8) * _amplitude, 0.0, TAU, _teinte(_matiere, t), 2.0)

func _dessiner_trajet(t: float) -> void:
	match _trajet:
		TRAJET.ESTOC, TRAJET.RAYON:
			_trait(t)
		TRAJET.CHUTE:
			_chute(t)
		TRAJET.CHUTE_POING, TRAJET.COMETE:
			_masse_tombante(t)
		TRAJET.VAGUE:
			_vague(t)
		TRAJET.POING, TRAJET.PROJECTILE, TRAJET.SALVE, TRAJET.ORBE:
			_bolides(t)

func _trait(t: float) -> void:
	var fin := _source.lerp(_corps, minf(t * 1.5, 1.0))
	var normal := _direction.orthogonal()
	var epaisseur := (5.0 + _nombre) * _amplitude * (1.0 - t * 0.5)
	if _trajet == TRAJET.ESTOC:
		_ruban(_source.lerp(fin, 0.25), fin + _direction * 8.0, epaisseur, 1.0 - t * 0.35)
	else:
		var points := PackedVector2Array([_source])
		for index in range(1, 8):
			var sinus := sin(float(index) * 4.5 + t * 17.0)
			points.append(_source.lerp(fin, index / 8.0) + normal * sinus * (4.0 + _nombre))
		points.append(fin)
		draw_polyline(points, _teinte(_ombre, 0.82), epaisseur + 5.0)
		draw_polyline(points, _teinte(_matiere, 0.96), epaisseur)
		draw_polyline(points, _coeur, 2.0)
	_etoile(fin, epaisseur + 2.0, 1.0 - t * 0.25)

func _chute(t: float) -> void:
	var rayons := maxi(_nombre, 1)
	for index in rayons:
		var decal := Vector2.from_angle(index * ANGLE_OR + _angle_initial) * (7.0 * index * _amplitude)
		var cible := _corps + Vector2(decal.x, decal.y * 0.35)
		var p := clampf((t - 0.12 * index / rayons) * 1.18, 0.0, 1.0)
		var fin := cible + Vector2(lerpf(23.0, 0.0, p), -135.0 * _amplitude * (1.0 - p))
		var source := fin + Vector2(12.0, -37.0 - 8.0 * _amplitude)
		_ruban(source, fin, (7.0 if index == 0 else 3.5) * _amplitude, 0.8)
		_losange(fin, (7.0 if index == 0 else 3.0) * _amplitude, 1.1, _coeur)
	_arc(Vector2.ZERO, Vector2(lerpf(26.0, 13.0, t), 6.0) * _amplitude,
		0.0, TAU, _teinte(_matiere, 0.7), 2.0)

func _vague(t: float) -> void:
	var position := _sol_source.lerp(Vector2.ZERO, t)
	for index in mini(_nombre, 6):
		var retard := index * 5.0
		var centre := position - _direction * retard
		var rayon := (12.0 + index * 2.0 + 12.0 * t) * _amplitude
		_arc(centre, Vector2(rayon, rayon * 0.37), _direction.angle() - 1.0, 2.8,
			_teinte(_matiere, 0.86 - index * 0.1), 2.0 + t * 2.0)
		_losange(centre + Vector2(0, -4), 2.5 * _amplitude, _direction.angle(), _teinte(_coeur, 0.8))

func _masse_tombante(t: float) -> void:
	var chute := t * t
	var position := _corps + Vector2(-24, -148) * _amplitude * (1.0 - chute)
	var rayon := (12.0 + 16.0 * t) * _amplitude
	_arc(Vector2.ZERO, Vector2(26, 8) * _amplitude, t, TAU, _teinte(_matiere, 0.75), 3.0)
	_ruban(position + Vector2(-18, -42) * _amplitude, position, rayon * 0.72, 0.78)
	if _trajet == TRAJET.CHUTE_POING:
		_dessiner_poing(position, rayon, PI / 2.0)
	else:
		draw_circle(position, rayon, _ombre)
		draw_circle(position, rayon * 0.83, _matiere)
		_etoile(position, rayon * 0.82, 0.91)
	for index in _nombre + 2:
		var angle := index * ANGLE_OR + t * 2.0
		var p := position + Vector2.from_angle(angle) * (rayon + 7.0 + index % 3 * 5.0)
		_losange(p, 3.4 * _amplitude, angle, _coeur)

func _bolides(t: float) -> void:
	var normal := _direction.orthogonal()
	var ecart_depart := 0.29 if _nombre > 1 else 0.0
	for index in _nombre:
		var retard := ecart_depart * float(index) / maxi(_nombre - 1, 1)
		var p := (t - retard) / (1.0 - ecart_depart)
		if p < 0.0 or p > 1.0:
			continue
		var ecart := (float(index) - (_nombre - 1) * 0.5) * 16.0
		var arc := normal * (ecart * sin(p * PI)) + Vector2(0, -12.0 * sin(p * PI))
		var fin := _source.lerp(_corps, p) + arc
		var poing := _trajet == TRAJET.POING
		var longueur := (6.5 if poing else 4.2) * _amplitude
		var debut := _source.lerp(fin, 0.0 if poing else 0.63)
		_ruban(debut, fin, longueur, 0.9)
		if poing:
			_dessiner_poing(fin, longueur, _direction.angle())
		elif _trajet == TRAJET.ORBE:
			_dessiner_orbe(fin, longueur, t)
		else:
			_losange(fin, longueur * 1.6, _direction.angle(), _ombre)
			_losange(fin, longueur, _direction.angle(), _coeur)
			_losange(fin + normal * 9.0 - _direction * 7.0, 2.0, _direction.angle(), _matiere)

func _dessiner_orbe(p: Vector2, taille: float, t: float) -> void:
	draw_circle(p, taille * 2.8, _teinte(_ombre, 0.50))
	draw_circle(p, taille * 2.15, _ombre)
	draw_circle(p, taille * 1.73, _matiere)
	draw_circle(p + Vector2(1, -2), taille * 0.9, _coeur)
	for index in 4:
		var angle := _angle_initial + index * TAU / 4.0 + t * 5.0
		var position := p + Vector2.from_angle(angle) * (taille * (2.4 + 0.21 * index))
		_losange(position, taille * 0.56, angle, _matiere)

func _dessiner_poing(p: Vector2, largeur: float, angle: float) -> void:
	var forme := PackedVector2Array()
	var profil := PackedVector2Array([
		Vector2(-1.22, -0.50), Vector2(-0.48, -0.61), Vector2(-0.08, -1.03),
		Vector2(0.53, -1.10), Vector2(0.91, -0.91), Vector2(1.04, -0.57),
		Vector2(0.91, -0.28), Vector2(1.10, 0.03), Vector2(1.00, 0.38),
		Vector2(0.73, 0.64), Vector2(0.58, 0.91), Vector2(-0.04, 1.02),
		Vector2(-0.60, 0.73), Vector2(-1.22, 0.52),
	])
	for point in profil:
		forme.append(p + (point * largeur * 1.42).rotated(angle))
	draw_colored_polygon(forme, _matiere)
	forme.append(forme[0])
	draw_polyline(forme, _ombre, maxf(2.0, largeur * 0.1))
	var axe := Vector2.from_angle(angle) * largeur
	var normal := axe.orthogonal()
	var plis := _ombre.lerp(_matiere, 0.51)
	for indice: float in [-0.73, -0.23, 0.27]:
		var haut := p + normal * indice
		draw_line(haut + axe * 0.18, haut + axe * 1.28, plis, maxf(1.5, largeur * 0.10))
	draw_polyline(PackedVector2Array([
		p - axe * 0.76 + normal * 0.76, p - axe * 0.30 + normal * 0.42,
		p + axe * 0.44 + normal * 0.48, p + axe * 0.59 + normal * 0.85,
	]), _coeur, maxf(2.0, largeur * 0.13))

func _dessiner_impact(t: float) -> void:
	if not _touche:
		_particules(t, 10.0 * _amplitude, (1.0 - t) * 0.38)
		return
	var rayon := (26.0 + 12.0 * t) * _amplitude
	var alpha := minf(t * 10.0 + 0.32, 1.0) * (1.0 - t)
	match _impact:
		IMPACT.TAILLE, IMPACT.FRAPPE:
			_coup(t, rayon, alpha)
		IMPACT.EXPLOSION, IMPACT.ONDE:
			_ondes(t, rayon, alpha)
		IMPACT.PRISON, IMPACT.METEO:
			_eclats_verticaux(t, rayon, alpha)
		IMPACT.VORTEX, IMPACT.AURA:
			_spirales(t, rayon, alpha)
		IMPACT.SOINS, IMPACT.NOTES:
			_signes_ascendants(t, rayon, alpha)
		IMPACT.GARDE, IMPACT.SCEAU, IMPACT.OEIL:
			_protection(t, rayon, alpha)
		IMPACT.FLEURS, IMPACT.TOILE:
			_motifs(t, rayon, alpha)
		IMPACT.FAILLE:
			_fissures(t, rayon, alpha)
		IMPACT.PHENIX:
			_ailes(t, rayon, alpha)
		IMPACT.ARMEMENT:
			_armement(t, rayon, alpha)
		IMPACT.CAGE:
			_cage(t, rayon, alpha)
	_particules(t, rayon, alpha)

func _coup(t: float, rayon: float, alpha: float) -> void:
	if _impact == IMPACT.FRAPPE:
		_etoile(_corps, rayon * (0.93 - 0.46 * t), alpha)
		for index in mini(_nombre, 4):
			var angle := _angle_initial + index * ANGLE_OR
			_losange(_corps + Vector2.from_angle(angle) * rayon * t, 5.0 * alpha, angle, _coeur)
		return
	for index in mini(_nombre, 6):
		var angle := _direction.angle() + (index - (_nombre - 1) * 0.5) * 0.49
		var centre := _corps + Vector2.from_angle(angle - PI / 2.0) * (6.0 + index * 2.0)
		_arc(centre, Vector2(rayon, rayon * 0.53), angle - 1.28 + t * 0.35, 2.25,
			_teinte(_ombre, alpha), 9.0 * alpha)
		_arc(centre, Vector2(rayon, rayon * 0.53), angle - 1.2 + t * 0.35, 2.1,
			_teinte(_matiere, alpha), 6.0 * alpha)
		_arc(centre, Vector2(rayon, rayon * 0.53), angle - 0.96 + t * 0.35, 1.54,
			_teinte(_coeur, alpha), 2.0 * alpha)

func _ondes(t: float, rayon: float, alpha: float) -> void:
	for index in mini(_nombre + 1, 6):
		var p := clampf(t * 1.4 - index * 0.13, 0.0, 1.0)
		var echelle := lerpf(0.25, 1.65, p)
		_arc(Vector2.ZERO, Vector2(rayon, rayon * 0.40) * echelle,
			_angle_initial + index * 0.51, TAU, _teinte(_matiere, alpha * p), 3.4 - 1.6 * p)
	if _impact == IMPACT.EXPLOSION:
		_etoile(_corps, rayon * (1.18 - t * 0.58), alpha)
		for index in _nombre + 3:
			var angle := index * ANGLE_OR + _angle_initial
			var p := Vector2.from_angle(angle) * rayon * t * (1.5 + 0.05 * index)
			p.y -= 26.0 * sin(t * PI)
			_losange(_corps + p, (4.0 + float(index % 3)) * alpha, angle, _teinte(_matiere, alpha))

func _eclats_verticaux(t: float, rayon: float, alpha: float) -> void:
	for index in _nombre + 1:
		var angle := index * TAU / (_nombre + 1) + _angle_initial
		var base := Vector2(cos(angle), sin(angle) * 0.37) * rayon * 0.9
		if _impact == IMPACT.METEO:
			var chute := fposmod(t + index * 0.21, 1.0)
			var p := base + Vector2(12.0 * (1.0 - chute), -120.0 * _amplitude * (1.0 - chute))
			_ruban(p + Vector2(8, -18), p, 3.2 * alpha, alpha)
			_losange(p, 5.0 * alpha, 1.2, _teinte(_coeur, alpha))
			continue
		var hauteur := (25.0 + 22.0 * absf(sin(angle))) * _amplitude * clampf(t * 5.0, 0.1, 1.0)
		var sommet := base + Vector2(cos(angle) * 9.0, -hauteur)
		var largeur := (4.0 + _amplitude * 2.0) * (1.0 - t * 0.5)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-largeur, 0), sommet, base + Vector2(largeur, 0),
			base + Vector2(0, 5),
		]), _teinte(_ombre, alpha))
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-largeur, 0), sommet, base + Vector2(0, 2),
		]), _teinte(_matiere, alpha))
		draw_line(sommet, base + Vector2(-1, -3), _teinte(_coeur, alpha), 1.5)

func _spirales(t: float, rayon: float, alpha: float) -> void:
	var vortex := _impact == IMPACT.VORTEX
	for index in _nombre:
		var angle := _angle_initial + t * 3.1 + index * TAU / _nombre
		var centre := Vector2.ZERO if vortex else _corps.lerp(Vector2.ZERO, fposmod(index * 0.3 - t * 0.65, 1.0))
		var largeur := rayon * (lerpf(1.24, 0.34, t) if vortex else lerpf(0.75, 0.44, t))
		_arc(centre, Vector2(largeur, largeur * 0.43), angle, 1.62,
			_teinte(_ombre, alpha), 8.0 * alpha)
		_arc(centre, Vector2(largeur, largeur * 0.43), angle + 0.17, 1.4,
			_teinte(_matiere, alpha), 4.0 * alpha)
		_arc(centre, Vector2(largeur, largeur * 0.43), angle + 0.48, 0.86,
			_teinte(_coeur, alpha), 1.5)

func _signes_ascendants(t: float, rayon: float, alpha: float) -> void:
	_arc(Vector2.ZERO, Vector2(rayon, rayon * 0.38), t, TAU, _teinte(_matiere, alpha), 2.4)
	for index in _nombre + 2:
		var phase := fposmod(t + index / float(_nombre + 2), 1.0)
		var p := Vector2(cos(phase * 4.1 + index * ANGLE_OR) * rayon * 0.85, -phase * 75.0 * _amplitude)
		var grain := 3.0 + index % 3
		if _impact != IMPACT.NOTES:
			draw_line(p + Vector2(-grain, 0), p + Vector2(grain, 0), _teinte(_coeur, alpha), 2.5)
			draw_line(p + Vector2(0, -grain), p + Vector2(0, grain), _teinte(_coeur, alpha), 2.5)
		else:
			_losange(p, grain, 0.0, _teinte(_matiere, alpha))
			draw_polyline(PackedVector2Array([p, p + Vector2(2, -12), p + Vector2(9, -8)]),
				_teinte(_coeur, alpha), 2.2)

func _protection(t: float, rayon: float, alpha: float) -> void:
	if _impact == IMPACT.GARDE:
		_arc(Vector2(0, -3), Vector2(rayon * 1.16, rayon * 1.35), PI, PI, _teinte(_ombre, alpha), 7.0)
		_arc(Vector2(0, -3), Vector2(rayon * 1.16, rayon * 1.35), PI, PI, _teinte(_matiere, alpha), 3.4)
		_arc(Vector2.ZERO, Vector2(rayon * 1.18, rayon * 0.38), 0.0, TAU, _teinte(_coeur, alpha), 2.0)
		for index in _nombre:
			var ancre := Vector2(cos(index * 0.8), -0.70 - sin(index * 0.8) * 0.15) * rayon
			_losange(ancre, 3.6 * alpha, 0.0, _teinte(_coeur, alpha))
		return
	var forme := Vector2(rayon, rayon * (0.36 if _impact == IMPACT.OEIL else 0.63))
	var centre := _corps + Vector2(0, -8)
	_arc(centre, forme, 0.0, TAU, _teinte(_matiere, alpha), 3.0)
	_arc(centre, forme * 1.23, _angle_initial + t, TAU * 0.77, _teinte(_ombre, alpha), 3.0)
	if _impact == IMPACT.OEIL:
		_losange(centre, 8.0 * _amplitude, PI * 0.5, _teinte(_coeur, alpha))
	else:
		for index in _nombre:
			var angle := index * TAU / _nombre + _angle_initial + t * 0.6
			_losange(centre + Vector2.from_angle(angle) * forme, 6.1 * alpha, angle, _teinte(_coeur, alpha))

func _motifs(t: float, rayon: float, alpha: float) -> void:
	for index in _nombre:
		var angle := index * TAU / _nombre + _angle_initial + t * 0.66
		var position := _corps + Vector2.from_angle(angle) * Vector2(rayon, rayon * 0.85) * minf(t * 3.3 + 0.2, 1.0)
		if _impact == IMPACT.FLEURS:
			for petale in 4:
				var a := petale * PI / 2.0 + angle
				_losange(position + Vector2.from_angle(a) * 6.0 * _amplitude, 5.5 * alpha, a,
					_teinte(_matiere, alpha))
			_losange(position, 3.9 * alpha, angle, _teinte(_coeur, alpha))
		else:
			draw_line(position, _corps + Vector2.from_angle(-angle) * rayon, _teinte(_matiere, alpha), 2.0)
			_losange(position, 3.5 * alpha, angle, _teinte(_coeur, alpha))

func _fissures(t: float, rayon: float, alpha: float) -> void:
	for index in _nombre + 2:
		var angle := _direction.angle() + index * TAU / (_nombre + 2) + 0.25
		var direction := Vector2.from_angle(angle)
		var longueur := rayon * minf(4.0 * t, 1.5) * (1.0 + 0.12 * (index % 3))
		var points := PackedVector2Array([Vector2.ZERO])
		for morceau in range(1, 6):
			var p := direction * longueur * morceau / 5.0
			p += direction.orthogonal() * sin(morceau * 2.8 + index) * longueur * 0.2
			p.y *= 0.52
			points.append(p)
		draw_polyline(points, _teinte(_ombre, alpha), 5.0)
		draw_polyline(points, _teinte(_matiere, alpha), 2.0)
	_etoile(_corps, rayon * 0.58, alpha * (1.0 - t))

func _ailes(t: float, rayon: float, alpha: float) -> void:
	_signes_ascendants(t, rayon, alpha)
	var ouverture := 0.38 + sin(t * PI) * 0.96
	var base := _corps + Vector2(0, 7)
	for cote in [-1.0, 1.0]:
		for index in _nombre:
			var ecart := float(index) / _nombre
			var aile := rayon * ouverture * (1.42 - ecart * 0.60)
			var origine := base + Vector2(cote * (8.0 + ecart * 16.0), ecart * 9.0)
			var milieu := base + Vector2(cote * aile * 0.72, -rayon * (0.44 - 0.47 * ecart))
			var pointe := base + Vector2(cote * aile, -rayon * (1.36 - 1.41 * ecart))
			var plume := PackedVector2Array([origine, milieu, pointe])
			draw_polyline(plume, _teinte(_ombre, alpha), 8.0 - ecart * 3.0)
			draw_polyline(plume, _teinte(_matiere, alpha), 5.0 - ecart * 2.0)
			draw_line(milieu, pointe, _teinte(_coeur, alpha), 1.7)

func _armement(t: float, rayon: float, alpha: float) -> void:
	var axe := Vector2.from_angle(-PI / 2.0)
	var largeur := (6.0 + t * 6.0) * _amplitude
	for cote in [-1.0, 1.0]:
		var main := _corps + Vector2(cote * rayon * 0.57, -rayon * 0.25)
		_ruban(main - axe * rayon * 0.9, main, largeur, alpha)
		_losange(main, largeur, -PI / 2.0, _teinte(_ombre, alpha))
		_etoile(main, largeur * 0.72, alpha)
	_arc(Vector2.ZERO, Vector2(rayon, rayon * 0.4), 0.0, TAU, _teinte(_matiere, alpha), 2.0)

func _cage(t: float, rayon: float, alpha: float) -> void:
	var largeur := rayon * lerpf(1.35, 0.85, t)
	var ancre := Vector2(0, -rayon * 1.55)
	for index in _nombre:
		var angle := index * TAU / _nombre + t * 0.3
		var pied := Vector2(cos(angle) * largeur, sin(angle) * largeur * 0.37)
		var noeud := ancre.lerp(pied, 0.59) + Vector2(pied.x * 0.4, -rayon * 0.18)
		var fil := PackedVector2Array([ancre, noeud, pied])
		draw_polyline(fil, _teinte(_ombre, alpha), 4.0)
		draw_polyline(fil, _teinte(_coeur, alpha), 1.5)
	_arc(Vector2.ZERO, Vector2(largeur, largeur * 0.37), 0.0, TAU, _teinte(_matiere, alpha), 2.4)

func _particules(t: float, rayon: float, alpha: float) -> void:
	for index in mini(7 + _nombre * 2, 25):
		var angle := _angle_initial + ANGLE_OR * index
		var ecart := (0.43 + float(index % 6) * 0.16) * rayon
		var p := _corps + Vector2.from_angle(angle) * ecart * (0.34 + t)
		p.y -= sin(t * PI) * (5.0 + float(index % 3) * 9.0)
		var couleur := _matiere if index % 3 == 0 else _coeur
		draw_rect(Rect2(p.round(), Vector2.ONE * (2.0 + index % 3) * _amplitude),
			_teinte(couleur, alpha), true)

func _ruban(debut: Vector2, fin: Vector2, largeur: float, alpha: float) -> void:
	if debut.distance_squared_to(fin) < 0.25 or largeur < 0.1:
		return
	var normal := debut.direction_to(fin).orthogonal()
	var bord := normal * largeur
	draw_colored_polygon(PackedVector2Array([
		debut, debut.lerp(fin, 0.55) - bord * 0.74, fin - bord * 1.16,
		fin + bord * 1.16, debut.lerp(fin, 0.55) + bord * 0.74,
	]), _teinte(_ombre, alpha))
	draw_colored_polygon(PackedVector2Array([
		debut, fin - bord * 0.68, fin + bord * 0.68,
	]), _teinte(_matiere, alpha))
	draw_line(debut.lerp(fin, 0.44), fin, _teinte(_coeur, alpha), 1.3)

func _arc(centre: Vector2, rayon: Vector2, debut: float, angle: float, couleur: Color, largeur: float) -> void:
	var points := PackedVector2Array()
	for index in 17:
		points.append(centre + Vector2.from_angle(debut + angle * index / 16.0) * rayon)
	draw_polyline(points, couleur, maxf(largeur, 1.0))

func _losange(centre: Vector2, rayon: float, angle: float, couleur: Color) -> void:
	if rayon < 0.2 or couleur.a <= 0.0:
		return
	var v := Vector2.from_angle(angle) * rayon
	var n := v.orthogonal() * 0.56
	draw_colored_polygon(PackedVector2Array([centre + v, centre + n, centre - v, centre - n]), couleur)

func _etoile(p: Vector2, rayon: float, alpha: float) -> void:
	for index in 3:
		var angle := _angle_initial / 3.0 + index * PI / 3.0
		_losange(p, rayon, angle, _teinte(_ombre, alpha * 0.88))
		_losange(p, rayon * 0.75, angle, _teinte(_coeur, alpha))

func _teinte(couleur: Color, alpha: float) -> Color:
	return Color(couleur, clampf(alpha, 0.0, 1.0))
