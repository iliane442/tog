shader_type canvas_item;

uniform vec4 ombre : source_color;
uniform vec4 matiere : source_color;
uniform vec4 coeur : source_color;
varying vec4 modulation;

void vertex() {
	modulation = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float ton = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = mix(ombre.rgb * 0.77, matiere.rgb, smoothstep(0.08, 0.65, ton));
	vec3 palette = mix(base, coeur.rgb, smoothstep(0.54, 0.98, ton));
	COLOR = vec4(mix(pixel.rgb, palette, 0.78), pixel.a) * modulation;
}
