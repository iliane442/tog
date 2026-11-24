shader_type canvas_item;
render_mode unshaded;

uniform sampler2D mer : filter_nearest, repeat_enable;
uniform vec2 dimensions;
uniform vec2 origine;

void fragment() {
	vec2 point = floor(UV * dimensions) - origine;
	vec2 grille = vec2(point.y / 64.0 + point.x / 128.0, point.y / 64.0 - point.x / 128.0);
	vec2 vague = grille * 46.0;
	float image = floor(mod(TIME, 2.4) * 10.0);
	float phase = image * TAU / 24.0;
	vec2 flux = vec2(2.5 * sin(vague.y * TAU / 64.0 + phase),
		128.0 * image / 24.0 + 1.4 * sin(vague.x * TAU / 64.0 - phase));
	vec3 couleur = texture(mer, (floor(vague + flux) + 0.5) / 128.0).rgb;
	float crete = sin((vague.x + 2.0 * vague.y) * TAU / 32.0 - 2.0 * phase);
	float eclat = (max(0.0, crete - 0.72) + crete * 0.20) * 0.094;
	COLOR = vec4((couleur + vec3(0.42, 1.0, 0.72) * eclat) * 0.92, 1.0);
}
