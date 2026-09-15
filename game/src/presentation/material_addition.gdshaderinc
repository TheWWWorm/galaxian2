#include "res://src/presentation/material_uv.gdshaderinc"
void fragment() {
	ALBEDO = source_diffuse(UV).rgb;
	// Both source additive families use ONE, ONE; alpha is not a blend factor.
	ALPHA = 1.0;
}
