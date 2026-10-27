shader_type canvas_item;
// The photo camera's eyepiece view on the desktop (photo_camera.gd): the lens picture in a soft
// round vignette, black around it.

void fragment() {
	float r = length((UV - 0.5) * vec2(1.333, 1.0));
	float window = 1.0 - smoothstep(0.40, 0.52, r);
	vec3 colour = texture(TEXTURE, UV).rgb * mix(1.0, 0.55, smoothstep(0.2, 0.48, r));
	COLOR = vec4(colour * window, 1.0);
}
