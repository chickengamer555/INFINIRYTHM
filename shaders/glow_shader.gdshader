shader_type canvas_item;

// Enhanced glow/bloom shader for 2D rhythm game
// Creates beautiful neon glow effects on bright colors

uniform float glow_intensity : hint_range(0.0, 5.0) = 1.5;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.3;
// PERFORMANCE: Reduced from 16 to 10 samples (30-40% faster shader execution)
uniform int blur_samples : hint_range(4, 32) = 10;
uniform float blur_radius : hint_range(1.0, 20.0) = 8.0;
uniform vec4 glow_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform bool use_color_tint = true;

void fragment() {
	vec4 original_color = texture(TEXTURE, UV);
	
	// Extract bright areas (above threshold)
	float brightness = dot(original_color.rgb, vec3(0.299, 0.587, 0.114));
	
	if (brightness > glow_threshold) {
		// Apply glow to bright areas
		vec4 glow = vec4(0.0);
		float total_weight = 0.0;
		
		// Radial blur for glow effect
		for (int i = 0; i < blur_samples; i++) {
			float angle = float(i) * 6.28318 / float(blur_samples);
			vec2 offset = vec2(cos(angle), sin(angle)) * blur_radius * TEXTURE_PIXEL_SIZE;
			
			vec4 sample_color = texture(TEXTURE, UV + offset);
			float sample_brightness = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
			
			if (sample_brightness > glow_threshold) {
				float weight = 1.0 - (length(offset) / (blur_radius * length(TEXTURE_PIXEL_SIZE)));
				glow += sample_color * weight;
				total_weight += weight;
			}
		}
		
		if (total_weight > 0.0) {
			glow /= total_weight;
			
			// Apply color tint if enabled
			if (use_color_tint) {
				glow.rgb = mix(glow.rgb, glow.rgb * glow_color.rgb, 0.3);
			}
			
			// Combine original with glow
			COLOR = original_color + glow * glow_intensity;
		} else {
			COLOR = original_color;
		}
	} else {
		COLOR = original_color;
	}
}

