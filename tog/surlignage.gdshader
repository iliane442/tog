shader_type canvas_item;

uniform bool surligne = false;
uniform vec4 couleur : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform float epaisseur : hint_range(1.0, 8.0) = 2.0;

void fragment() {
	vec4 couleur_pixel = texture(TEXTURE, UV);
	if (surligne) {
		vec2 pas = TEXTURE_PIXEL_SIZE * epaisseur;
		float entourage = 0.0;
		entourage += texture(TEXTURE, UV + vec2(pas.x, 0.0)).a;
		entourage += texture(TEXTURE, UV - vec2(pas.x, 0.0)).a;
		entourage += texture(TEXTURE, UV + vec2(0.0, pas.y)).a;
		entourage += texture(TEXTURE, UV - vec2(0.0, pas.y)).a;
		// pixel transparent accolé au sprite : on le remplace par le contour
		if (couleur_pixel.a < 0.5 && entourage > 0.0) {
			couleur_pixel = couleur;
			couleur_pixel.a = 1.0;
		}
	}
	COLOR = couleur_pixel;
}
