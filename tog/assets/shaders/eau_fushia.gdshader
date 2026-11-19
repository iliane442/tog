shader_type canvas_item;

varying vec2 position_eau;

void vertex() {
	position_eau = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy * 0.5;
}

float motif(vec2 case_eau) {
	return fract(sin(dot(case_eau, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 fond = texture(TEXTURE, UV);
	float eau = step(fond.g * 0.91, fond.b) * step(fond.r * 1.53, fond.g);
	vec2 cellule = floor(position_eau / vec2(61.0, 33.0));
	float graine = motif(cellule);
	vec2 point = fract(position_eau / vec2(61.0, 33.0));
	float phase = TIME * 0.52 + 22.0 * graine;
	float ligne = step(abs(point.y - (0.18 + 0.59 * graine)), 0.027);
	float longueur = step(abs(point.x - 0.5 - 0.12 * sin(phase)), 0.09 + 0.10 * graine);
	float reflet = ligne * longueur * smoothstep(0.15, 1.0, sin(phase)) * step(0.31, graine);
	COLOR = vec4(fond.rgb + vec3(0.10, 0.14, 0.12) * eau * reflet, fond.a);
}
