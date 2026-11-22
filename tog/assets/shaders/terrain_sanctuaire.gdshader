shader_type canvas_item;
render_mode unshaded;

uniform sampler2D donnees : filter_nearest, repeat_disable;
uniform sampler2D hauteur : filter_linear, repeat_disable;
uniform sampler2D dallage : source_color, filter_nearest, repeat_enable;
uniform sampler2D maconnerie : source_color, filter_nearest, repeat_enable;
uniform vec2 dimensions;

varying vec2 position_case;

void vertex() {
	position_case = VERTEX / 64.0;
}

int type_sol(vec2 position) {
	ivec2 cellule = ivec2(clamp(floor(position), vec2(0.0), dimensions - 1.0));
	return int(round(texelFetch(donnees, cellule, 0).r * 8.0));
}

float altitude(vec2 position) {
	return texture(hauteur, position / dimensions).g;
}

bool bordure(vec2 position, int type, float epaisseur) {
	return type_sol(position + vec2(epaisseur, 0.0)) != type
		|| type_sol(position - vec2(epaisseur, 0.0)) != type
		|| type_sol(position + vec2(0.0, epaisseur)) != type
		|| type_sol(position - vec2(0.0, epaisseur)) != type;
}

void fragment() {
	vec2 p = floor(position_case * 32.0) / 32.0;
	int type = type_sol(p);
	vec3 couleur;
	if (type == 3) {
		float profondeur = altitude(p);
		vec3 pierre = texture(maconnerie, p * 0.5).rgb;
		vec3 vide = vec3(0.055, 0.075, 0.105);
		couleur = mix(pierre * vec3(0.65, 0.75, 0.86), vide, smoothstep(0.17, 0.48, profondeur));
		bool face_sud = type_sol(p + vec2(0.0, 0.72)) != 3;
		if (face_sud) {
			couleur *= fract(p.y) > 0.73 ? 0.61 : 0.84;
		}
		if (bordure(p, 3, 0.065)) {
			couleur *= 1.18;
		}
	} else if (type == 5) {
		float courant = sin(p.x * 7.2 + p.y * 5.6 + TIME * 1.1);
		float reflet = floor(max(courant, 0.0) * 4.0) * 0.25;
		couleur = vec3(0.07, 0.23, 0.31) + reflet * vec3(0.05, 0.11, 0.13);
		if (bordure(p, 5, 0.10)) {
			couleur = vec3(0.29, 0.36, 0.39);
		} else if (bordure(p, 5, 0.16)) {
			couleur = vec3(0.20, 0.43, 0.47);
		}
	} else {
		vec3 pierre = texture(dallage, p * 0.5).rgb;
		if (type == 2) {
			couleur = pierre * vec3(0.86, 0.83, 0.77);
			if (bordure(p, 2, 0.04)) {
				couleur = mix(couleur, vec3(0.56, 0.44, 0.24), 0.66);
			}
		} else {
			float grain = dot(pierre, vec3(0.29, 0.60, 0.11));
			couleur = mix(vec3(0.24, 0.28, 0.35), vec3(0.44, 0.46, 0.51), grain);
		}
		float ombre = smoothstep(0.0, 0.18, altitude(p - vec2(0.16, 0.89)));
		couleur *= 1.0 - ombre * 0.21;
	}
	COLOR = vec4(couleur, 1.0);
}
