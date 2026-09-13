// Explicit unfogged TextureShader path. RGB conversion happens after source
// texture/color/darkening arithmetic. The owning blend shader selects alpha use.
uniform sampler2D diffuse_texture : filter_linear_mipmap_anisotropic;
uniform vec4 effect_tint = vec4(1.0);
uniform float darken_value = 1.0;

vec3 effect_display_to_linear(vec3 value) {
	return mix(value/12.92,pow(max((value+vec3(0.055))/1.055,vec3(0.0)),vec3(2.4)),greaterThan(value,vec3(0.04045)));
}

vec4 effect_color(vec2 uv) {
	vec4 pigment = texture(diffuse_texture,uv);
	vec3 response = pigment.rgb * effect_tint.rgb * darken_value;
	return vec4(OUTPUT_IS_SRGB ? response : effect_display_to_linear(response),pigment.a * effect_tint.a);
}
