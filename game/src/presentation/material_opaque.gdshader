shader_type spatial;
render_mode unshaded, cull_back;
#include "res://src/presentation/material_uv.gdshaderinc"
void fragment() {
	ALBEDO = source_diffuse(UV).rgb;
}
