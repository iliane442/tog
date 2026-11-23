shader_type canvas_item;
render_mode unshaded;

uniform vec2 dimensions = vec2(192.0, 128.0);
uniform int surface = 0;
uniform bool chute_libre = false;

float hachage(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float temps = floor(TIME * 15.0) / 15.0;
	vec2 p = floor(UV * dimensions * 0.5) * 2.0;
	vec3 equilibre = vec3(0.077, 0.54, 0.72);
	vec3 turquoise = vec3(0.24, 0.89, 0.93);
	vec3 ecume = vec3(0.85, 0.99, 1.0);
	float alpha = 1.0;
	vec3 teinte;

	if (surface == 1) {
		float aval = p.y - temps * 144.0;
		float veines = sin(p.x * 0.32 + sin(p.x * 0.079) * 2.3);
		float ruissellement = sin(aval * 0.14 + p.x * 0.15) * 0.5 + 0.5;
		teinte = mix(equilibre, turquoise, smoothstep(-0.95, 0.85, veines));
		teinte = mix(teinte, ecume, step(0.47, veines) * step(0.56, ruissellement) * 0.83);
		float crete = 1.0 - smoothstep(0.02, 0.14, UV.y);
		teinte = mix(teinte, ecume, crete * (0.63 + veines * 0.15));
		if (chute_libre) {
			alpha = (1.0 - smoothstep(0.84, 1.0, UV.y + veines * 0.026));
		}
	} else if (surface == 2) {
		vec2 centre = UV * 2.0 - 1.0;
		float rayon = length(centre);
		float remous = sin(rayon * 19.0 - temps * 6.0 + sin(p.x * 0.18) * 0.85);
		teinte = mix(turquoise, ecume, smoothstep(-0.25, 0.74, remous));
		alpha = (1.0 - smoothstep(0.42, 1.0, rayon)) * (0.35 + 0.5 * step(0.12, remous));
	} else {
		float aval = p.y - temps * 64.0;
		float rive = min(UV.x, 1.0 - UV.x);
		float eau = sin(aval * 0.22 + sin(p.x * 0.068 + aval * 0.029) * 2.4);
		float relief = sin(p.x * 0.15 - aval * 0.16) * 0.19 + 0.65;
		teinte = mix(equilibre, turquoise, relief + smoothstep(-0.75, 0.85, eau) * 0.15);
		float eclats = hachage(floor(vec2(p.x * 0.088, aval * 0.13)));
		teinte = mix(teinte, ecume, step(0.78, eau) * step(0.55, eclats) * 0.74);
		teinte = mix(teinte, vec3(0.10, 0.46, 0.49), (1.0 - smoothstep(0.025, 0.12, rive)) * 0.68);
		float filet = (1.0 - smoothstep(0.019, 0.042, rive)) * step(0.16, eau);
		teinte = mix(teinte, turquoise, filet * 0.76);
	}
	COLOR = vec4(teinte, alpha);
}
