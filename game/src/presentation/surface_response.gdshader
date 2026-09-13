shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://src/presentation/material_coordinates.gdshaderinc"

// Native forward material. Inputs are prepared by material_light_state; this
// shader owns lighting rather than routing it through Godot's PBR response.
uniform sampler2D diffuse_texture : filter_linear_mipmap_anisotropic;
uniform sampler2D normal_specular_texture : filter_linear_mipmap_anisotropic;
uniform samplerCube reflection_texture : filter_linear;
uniform vec3 light_directions[2];
uniform vec3 ambient_colors[2];
uniform vec3 diffuse_colors[2];
uniform vec3 specular_colors[2];
uniform vec3 rim_color;
uniform float specular_power;
uniform float diffuse_bias;
uniform float normal_bias;
uniform bool reflection_enabled;

varying vec3 tangent_lights[2];
varying vec3 tangent_highlights[2];
varying vec3 tangent_eye;
varying mat3 reflection_frame;

float hemisphere_weight(vec3 a, vec3 b) {
	return clamp(dot(a,b),0.0,1.0);
}

vec3 display_to_linear(vec3 value) {
	return mix(value/12.92,pow(max((value+vec3(0.055))/1.055,vec3(0.0)),vec3(2.4)),greaterThan(value,vec3(0.04045)));
}

void vertex() {
	mat3 into_tangent = transpose(mat3(TANGENT,BINORMAL,NORMAL));
	mat4 into_model = inverse(MODEL_MATRIX);
	vec3 eye_offset = (into_model*vec4(CAMERA_POSITION_WORLD,1.0)).xyz-VERTEX;
	tangent_eye = normalize(into_tangent*eye_offset);
	vec3 eye_axis = normalize(eye_offset);
	for (int i=0;i<2;i++) {
		vec3 local_light = mat3(into_model)*light_directions[i];
		tangent_lights[i] = into_tangent*local_light;
		tangent_highlights[i] = into_tangent*normalize(eye_axis+local_light);
	}
	reflection_frame = mat3(MODEL_MATRIX);
}

void fragment() {
	vec2 uv = source_uv(UV);
	vec3 pigment = texture(diffuse_texture,uv,diffuse_bias).rgb;
	vec4 detail = texture(normal_specular_texture,uv,normal_bias);
	vec3 normal = detail.rgb*2.0-1.0;
	vec3 illumination = vec3(0.0);
	vec3 highlights = vec3(0.0);
	for (int i=0;i<2;i++) {
		illumination += ambient_colors[i]+diffuse_colors[i]*hemisphere_weight(normal,tangent_lights[i]);
		highlights += specular_colors[i]*pow(hemisphere_weight(normal,tangent_highlights[i]),specular_power);
	}
	vec3 response = pigment*illumination+detail.a*highlights;
	if (reflection_enabled) {
		float edge = 1.0-dot(tangent_eye,normal);
		float rim = smoothstep(0.8,1.0,edge);
		float mask = detail.a*detail.a;
		float reflection_weight = clamp(smoothstep(0.6,1.0,edge),mask,2.0*detail.a+rim);
		vec3 bounced = tangent_eye-2.0*dot(normal,tangent_eye)*normal;
		response += texture(reflection_texture,reflection_frame*bounced).rgb*reflection_weight;
		response += rim_color*(mask*rim);
	}
	// Preserve raw source texture arithmetic in the display-referred response.
	// Godot's linear backends apply their display transfer after this stage.
	ALBEDO = OUTPUT_IS_SRGB ? response : display_to_linear(response);
}
