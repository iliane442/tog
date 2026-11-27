shader_type canvas_item;

varying vec2 position_rive;

void vertex() {
	position_rive = VERTEX;
}

void fragment() {
	vec2 pixel = floor(position_rive / 3.0) * 3.0;
	float temps = floor(TIME * 12.0) / 12.0;
	float houle = sin(pixel.x * 0.064 + pixel.y * 0.048 - temps * 2.6);
	float reflet = sin(pixel.x * 0.15 - pixel.y * 0.12 + houle * 1.2 - temps * 1.7);
	COLOR.a *= mix(0.24, 1.0, smoothstep(-0.5, 0.75, houle * 0.64 + reflet * 0.36));
}
