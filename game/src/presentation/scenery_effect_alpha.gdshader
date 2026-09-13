shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;

#include "res://src/presentation/effect_texture.gdshaderinc"

void fragment() {
	vec4 pigment = effect_color(UV);
	ALBEDO = pigment.rgb;
	ALPHA = pigment.a;
}
