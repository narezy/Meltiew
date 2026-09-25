shader_type spatial;
render_mode diffuse_lambert, cull_disabled;

uniform vec4 shallow : source_color = vec4(0.45, 0.85, 0.95, 1.0);
uniform vec4 deep : source_color = vec4(0.2, 0.55, 0.85, 1.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.6 + TIME * 1.4) * 0.03 + cos(wpos.z * 0.5 + TIME * 1.1) * 0.03;
}

void fragment() {
	float w = sin(wpos.x * 1.3 + TIME * 1.6) * cos(wpos.z * 1.1 - TIME * 1.2);
	float sparkle = smoothstep(0.85, 1.0, w);
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.5 + 0.5 * w) + sparkle * 0.25;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	ALPHA = 0.82;
}
