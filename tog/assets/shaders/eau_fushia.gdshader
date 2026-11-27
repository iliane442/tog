shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 fonte = texture(TEXTURE, UV);
	vec2 p = floor(UV / TEXTURE_PIXEL_SIZE);
	float eau = smoothstep(0.05, 0.18, fonte.g - fonte.r)
		* smoothstep(-0.08, 0.045, fonte.b - fonte.g);
	float temps = floor(TIME * 14.0) / 14.0;
	float onde = sin(p.y * 0.19 + sin(p.x * 0.095) * 1.5 - temps * 3.4);
	float eclat = smoothstep(0.30, 0.96, onde) * eau;
	fonte.rgb += vec3(0.12, 0.22, 0.20) * eclat;
	COLOR = fonte;
}
