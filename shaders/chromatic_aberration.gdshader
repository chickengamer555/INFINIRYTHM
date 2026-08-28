shader_type canvas_item;

// Chromatic aberration shader - splits RGB channels for cool cyberpunk effect
// Perfect for rhythm games and intense moments

uniform float aberration_strength : hint_range(0.0, 0.05) = 0.005;
uniform float radial_strength : hint_range(0.0, 2.0) = 0.5;
uniform vec2 center = vec2(0.5, 0.5);
uniform bool audio_reactive = false;
uniform float audio_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Calculate distance from center for radial effect
	vec2 dir = UV - center;
	float dist = length(dir);
	
	// Dynamic aberration based on distance from center
	float aberration = aberration_strength * (1.0 + dist * radial_strength);
	
	// Audio-reactive enhancement
	if (audio_reactive) {
		aberration *= (1.0 + audio_intensity * 2.0);
	}
	
	// Offset each color channel
	vec2 offset_r = dir * aberration;
	vec2 offset_g = vec2(0.0);
	vec2 offset_b = -dir * aberration;
	
	// Sample each channel separately
	float r = texture(TEXTURE, UV + offset_r).r;
	float g = texture(TEXTURE, UV + offset_g).g;
	float b = texture(TEXTURE, UV + offset_b).b;
	float a = texture(TEXTURE, UV).a;
	
	COLOR = vec4(r, g, b, a);
}

