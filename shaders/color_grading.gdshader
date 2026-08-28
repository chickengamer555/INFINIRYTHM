shader_type canvas_item;

// Professional color grading shader for enhanced visuals
// Adds contrast, saturation, and color tinting

uniform float contrast : hint_range(0.0, 3.0) = 1.2;
uniform float saturation : hint_range(0.0, 3.0) = 1.3;
uniform float brightness : hint_range(-1.0, 1.0) = 0.05;
uniform vec4 color_tint : source_color = vec4(0.55, 0.7, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.15;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_size : hint_range(0.0, 2.0) = 0.8;

// Convert RGB to HSV
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Convert HSV to RGB
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	
	// Apply brightness
	color.rgb += brightness;
	
	// Apply contrast
	color.rgb = ((color.rgb - 0.5) * contrast) + 0.5;
	
	// Apply saturation
	vec3 hsv = rgb2hsv(color.rgb);
	hsv.y *= saturation;
	color.rgb = hsv2rgb(hsv);
	
	// Apply color tint
	color.rgb = mix(color.rgb, color.rgb * color_tint.rgb, tint_strength);
	
	// Apply vignette
	vec2 uv_centered = UV - 0.5;
	float vignette = 1.0 - smoothstep(vignette_size, vignette_size + 0.5, length(uv_centered));
	vignette = mix(1.0, vignette, vignette_strength);
	color.rgb *= vignette;
	
	// Clamp to prevent over-bright values (unless HDR)
	color.rgb = clamp(color.rgb, 0.0, 2.0);
	
	COLOR = color;
}

