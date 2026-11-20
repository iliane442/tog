shader_type canvas_item;
render_mode unshaded;

uniform sampler2D donnees : filter_nearest, repeat_disable;
uniform sampler2D hauteur : filter_linear, repeat_disable;
uniform sampler2D sols : source_color, filter_nearest, repeat_disable;
uniform vec2 dimensions;
uniform bool souterrain = false;

varying vec2 position_case;

void vertex() {
	position_case = VERTEX / 64.0;
}

int type_sol(vec2 case_sol) {
	ivec2 cellule = ivec2(clamp(floor(case_sol), vec2(0.0), dimensions - 1.0));
	return int(round(texelFetch(donnees, cellule, 0).r * 8.0));
}

float altitude(vec2 case_sol) {
	return texture(hauteur, case_sol / dimensions).g;
}

vec3 tuile(vec2 case_sol, vec2 atlas) {
	return texture(sols, (atlas + fract(case_sol)) / vec2(3.0, 2.0)).rgb;
}

void fragment() {
	vec2 p = floor(position_case * 32.0) / 32.0;
	vec2 bord = p + 0.15 * vec2(sin(p.y * 5.5) + 0.4 * sin(p.y * 13.7),
		sin(p.x * 4.1) + 0.4 * sin(p.x * 11.1));
	int id = type_sol(bord);
	float variation = sin(p.x * 0.78 + p.y * 0.34) * sin(p.y * 0.65 - p.x * 0.35);
	float plis = sin(p.x * 2.4 + p.y * 0.93 + sin(p.y * 0.58) * 2.1)
		* sin(p.x * 0.97 - p.y * 1.16);
	float h = altitude(p);
	float lumiere = altitude(p + vec2(0.8, 0.9)) - altitude(p - vec2(0.8, 0.9));
	vec3 couleur;
	if (id == 3) {
		float roche = clamp(0.5 + lumiere * 2.0 + variation * 0.14, 0.0, 1.0);
		couleur = mix(vec3(0.26, 0.30, 0.32), vec3(0.63, 0.60, 0.53), roche);
		float strates = smoothstep(0.22, 0.49, sin(h * 47.0 + plis * 0.74));
		couleur *= 0.79 + 0.20 * strates + 0.15 * plis;
		float grain = dot(tuile(p * 0.94, vec2(1.0, 1.0)), vec3(0.29, 0.60, 0.11));
		couleur *= 0.68 + 0.87 * grain;
		if (souterrain) {
			couleur *= vec3(0.59, 0.68, 0.83);
		} else {
			float crete = smoothstep(0.61, 0.95, h + 0.10 * plis + 0.09 * variation);
			vec3 neige = vec3(0.79, 0.78, 0.72) * (0.69 + 0.23 * roche + 0.26 * grain);
			couleur = mix(couleur, neige, crete * 0.90);
		}
	} else if (id == 5) {
		float eau = sin(p.y * 26.0 + variation * 1.5) * sin(p.x * 8.0 + p.y * 1.7);
		couleur = vec3(0.12, 0.26, 0.33) + max(eau, 0.0) * vec3(0.035, 0.052, 0.061);
	} else if (id == 2) {
		couleur = tuile(p * 0.91, vec2(0.0, 1.0));
	} else if (souterrain) {
		couleur = tuile(p * 0.78, vec2(1.0, 1.0)) * (0.88 + 0.13 * variation);
	} else if (id == 1) {
		couleur = tuile(p * 0.93, vec2(1.0, 0.0)) * vec3(0.86, 0.91, 0.93);
	} else {
		couleur = tuile(p * 0.92, vec2(0.0)) * vec3(0.77, 0.87, 0.79);
		if (id == 4 || id == 6) {
			couleur *= vec3(0.61, 0.81, 0.81) * (0.86 + 0.16 * variation);
		}
	}
	float ombre = smoothstep(0.0, 0.21, altitude(p - vec2(0.14, 1.05)));
	if (id != 3) {
		couleur *= 1.0 - 0.24 * ombre;
	}
	COLOR = vec4(couleur, 1.0);
}
