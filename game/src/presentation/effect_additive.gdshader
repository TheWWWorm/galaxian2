shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
#include "res://src/presentation/effect_texture.gdshaderinc"

void fragment() {
	ALBEDO = effect_color(UV).rgb;
	// Source type 2 uses ONE, ONE: texture/tint alpha is not a blend factor.
	ALPHA = 1.0;
}
