shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
#include "res://src/presentation/sky_vertex.gdshaderinc"
void fragment() {
	ALBEDO = source_diffuse(UV).rgb;
	ALPHA = 1.0;
}
