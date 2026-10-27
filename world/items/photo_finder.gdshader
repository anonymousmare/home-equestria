shader_type spatial;
// The photo camera's eyepiece view in VR (photo_camera.gd): drawn for one eye only, the lens
// picture in a soft round vignette with the camera body's black around it.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D view : source_color, filter_linear, repeat_disable;
uniform int eye = 0;
const float ASPECT = 1024.0 / 768.0;

void fragment() {
	if (VIEW_INDEX != eye) discard;
	// The quad is square; the picture keeps 4:3 inside a round window.
	vec2 c = UV - 0.5;
	float r = length(c);
	float window = 1.0 - smoothstep(0.1, 0.125, r);
	vec2 picture = vec2(c.x * 4.0, c.y * 4.0 * ASPECT) + 0.5;
	vec3 colour = texture(view, picture).rgb;
	// Darker toward the edge of the window, like a real finder.
	colour *= mix(1.0, 0.55, smoothstep(0.05, 0.12, r));
	ALBEDO = colour * window;
	ALPHA = 1.0;
}
