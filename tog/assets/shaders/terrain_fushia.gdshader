shader_type canvas_item;

uniform sampler2D carte_terrain : filter_linear, repeat_disable;
uniform bool mini_carte = false;

// Dimensions en pixels avant l'échelle x2 des sprites.
const vec2 TAILLE_TERRAIN = vec2(5152.0, 4032.0);
varying vec2 position_terrain;
varying vec4 teinte;

void vertex() {
	position_terrain = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy * 0.5;
	teinte = COLOR;
}

float sommet_rocheux(vec2 position) {
	// La carte entière sert de masque continu aux jonctions des quatre sprites.
	vec3 sol = texture(carte_terrain, position / TAILLE_TERRAIN).rgb;
	float rouge_vert = (sol.r - sol.g) * 255.0;
	float vert_bleu = (sol.g - sol.b) * 255.0;
	float roche = smoothstep(-4.0, 3.0, rouge_vert) * (1.0 - smoothstep(9.0, 15.0, rouge_vert));
	roche *= smoothstep(18.0, 25.0, vert_bleu) * (1.0 - smoothstep(34.0, 42.0, vert_bleu));
	return smoothstep(0.35, 0.75, roche);
}

vec3 ombrer_relief(vec3 sol, vec2 position) {
	float corvo = 1.0 - smoothstep(360.0, 720.0, distance(position, vec2(1952.0, 940.0)));
	vec2 aplomb = vec2(0.32, 1.0) * mix(44.0, 72.0, corvo);
	float sommet = sommet_rocheux(position);
	float crete = sommet * (1.0 - sommet_rocheux(position - vec2(18.0, 21.0)));
	float versant = sommet * (1.0 - sommet_rocheux(position + aplomb * 0.55));

	// Laisse la terre battue et les quais lisibles au pied des falaises.
	float herbe = smoothstep(0.01, 0.07, sol.g - sol.r);
	float haut = sommet_rocheux(position - aplomb * 0.43);
	float pied = sommet_rocheux(position - aplomb);
	float paroi = max(haut, pied) * (1.0 - sommet) * herbe;
	float ombre = sommet_rocheux(position - aplomb * 1.42) * (1.0 - sommet) * herbe;

	vec3 relief = sol * (1.0 + 0.12 * sommet - 0.19 * versant);
	relief += vec3(0.19, 0.16, 0.095) * crete;
	relief *= 1.0 - 0.27 * ombre;

	vec2 pixel = floor(position * 0.5) * 2.0;
	float strates = smoothstep(-0.28, 0.3, sin(pixel.y * 0.22 + sin(pixel.x * 0.057) * 1.7));
	float fissures = smoothstep(0.77, 0.93, sin(pixel.x * 0.14 - pixel.y * 0.046));
	vec3 roche = mix(vec3(0.24, 0.25, 0.24), vec3(0.49, 0.43, 0.34), haut);
	roche += vec3(0.038) * strates - vec3(0.048) * fissures;
	return mix(relief, roche, paroi * 0.96);
}

float reflet_eau(vec2 position) {
	vec2 grille = position / vec2(61.0, 33.0);
	vec2 cellule = floor(grille);
	float graine = fract(sin(dot(cellule, vec2(127.1, 311.7))) * 43758.5453);
	vec2 point = fract(grille);
	float phase = TIME * 0.52 + 22.0 * graine;
	float ligne = step(abs(point.y - (0.18 + 0.59 * graine)), 0.027);
	float longueur = step(abs(point.x - 0.5 - 0.12 * sin(phase)), 0.09 + 0.10 * graine);
	return ligne * longueur * smoothstep(0.15, 1.0, sin(phase)) * step(0.31, graine);
}

void fragment() {
	vec4 fond = texture(TEXTURE, UV);
	float eau = step(fond.g * 0.91, fond.b) * step(fond.r * 1.53, fond.g);
	if (eau < 0.5) {
		vec2 position = mini_carte ? UV * TAILLE_TERRAIN : position_terrain;
		fond.rgb = ombrer_relief(fond.rgb, position);
	} else if (!mini_carte) {
		fond.rgb += vec3(0.10, 0.14, 0.12) * reflet_eau(position_terrain);
	}
	COLOR = fond * teinte;
}
