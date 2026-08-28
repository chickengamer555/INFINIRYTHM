# Audio-Reactive Bullet Hell Game 🎵🎮

An intense audio-reactive bullet hell game built in Godot 4.5 that generates enemies, bullets, and visual effects based on your MP3 music files!

## Features

### 🎵 Audio-Reactive Gameplay
- **Advanced Beat Detection**: Bass frequency analysis (60-130 Hz) for accurate beat detection with spike detection
- **Frequency-Based Spawning**: Different enemy types spawn based on audio frequency ranges:
  - **High Frequencies (4000-20000 Hz)**: Fast enemies with spread patterns (top zone - cyan)
  - **Mid Frequencies (250-2000 Hz)**: Standard enemies with aimed patterns (middle zone - green)
  - **Low Frequencies (60-130 Hz)**: Tank enemies with circular patterns (bottom zone - red)
- **Dynamic Intensity**: Enemy spawn rate and fire rate adjusts to music intensity in real-time (0.4s to 1.5s intervals)

### 🎯 Bullet Hell Mechanics
- **Object Pooling System**: Optimized to handle 800+ bullets and 50+ enemies simultaneously
- **Multiple Bullet Patterns**:
  - **Circular/Radial**: 360° bullet spreads
  - **Spiral**: Rotating bullet streams
  - **Aimed**: Bullets track player position
  - **Spread**: Fan-shaped patterns
  - **Random**: Unpredictable pattern combinations
- **Enemy Variety**: 4 enemy types (basic, fast, tank, elite) with unique behaviors
- **Precision Hitbox**: Tiny player hitbox (30% of visual size) for fair bullet dodging

### 🎮 Game Systems
- **Score System**: Earn points for destroying enemies (10-50 points based on type)
- **Combo System**: Chain kills within 2 seconds for multiplier bonuses (10% per combo)
- **Health System**: 100 HP, bullets deal 1 damage, enemies deal 2 damage
- **Invincibility Frames**: 0.5s invincibility after taking damage
- **Visual Feedback**:
  - Trauma-based screen shake on beats and hits
  - Beat flash effects synchronized with bass
  - Color-coded health bar (green/yellow/red)
  - Combo display with live multiplier

### 🎨 Audio-Reactive Visuals
- **Background Layer**: Ambient particle effects react to full spectrum audio (20Hz-20kHz)
- **Frequency Zone Indicators**: Visual overlays show active frequency ranges
- **Beat Flash Effects**: Screen-wide white flash on detected beats
- **Center Circle Visualization**: Multi-layered pulsing based on bass/mid/treble

## Controls

### Player Movement
- **WASD** or **Arrow Keys**: Move player (400 px/s)
- **Shift**: Focus mode (slower 200 px/s precision movement + shows red hitbox)
- **Spacebar**: Play/Pause music
- **Escape**: Return to main menu

### Menu
- **L**: Load MP3 file
- **Enter/Spacebar**: Start game with loaded file

## How to Play

1. **Load Music**: Click "Load Audio File" or press **L** to select an MP3 file (up to 100MB)
2. **Start Game**: Click "Play" or press **Enter** to begin
3. **Survive**: Dodge bullets and destroy enemies to build combos
4. **Focus Mode**: Hold **Shift** to slow down for precise dodging through tight bullet patterns
5. **Watch Your Health**: Bullets deal 1 damage, enemy collisions deal 2 damage
6. **Build Combos**: Destroy enemies quickly (within 2s) to build combo multipliers
7. **Score High**: Chain combos for maximum points!

## Technical Details

### Performance Optimizations
- **Object Pooling**: Pre-instantiated pools for bullets (800) and enemies (50) - no runtime instantiation
- **Efficient Collision**: Manual distance-based collision detection, optimized for bullet hell
- **Custom Rendering**: All game objects use custom `_draw()` functions for performance
- **Smart Spawning**: Dynamic spawn rates based on audio intensity (prevents lag spikes)

### Audio Analysis
- **Spectrum Analyzer**: Real-time FFT analysis via `AudioEffectSpectrumAnalyzerInstance`
- **Optimized Frequency Ranges**:
  - **Bass**: 60-130 Hz (kick drums, beat detection)
  - **Mid**: 250-2000 Hz (melody, vocals, snares)
  - **High**: 4000-20000 Hz (cymbals, hi-hats)
- **Beat Detection**: Energy spike detection with 1.4x threshold and 0.15s cooldown

### Architecture
- **Modular Design**: Separate classes for `Bullet`, `Enemy`, `ObjectPool`, `CameraShake`
- **Signal-Based Communication**: `GameManager` uses signals for decoupled UI updates
- **Layered Scenes**: Background and gameplay layers for visual depth
- **Autoload Singletons**: `AudioManager` and `GameManager` for global state

## File Structure

### Core Scripts
- `BulletHellLevel.gd` - Main gameplay logic, audio-reactive spawning, collision detection
- `Bullet.gd` - Bullet behavior, movement, and pooling
- `Enemy.gd` - Enemy AI, bullet pattern generation, audio reactivity
- `ObjectPool.gd` - Generic object pooling system for performance
- `GameManager.gd` - Score, health, combo management (autoload)
- `AudioManager.gd` - Audio file management (autoload)

### Visual & UI
- `BackgroundVisualizer.gd` - Ambient audio-reactive particle effects
- `CameraShake.gd` - Trauma-based screen shake system
- `Visualizer.gd` - Main scene controller, UI management, audio setup

### Scenes
- `MainMenu.tscn` - File loading menu
- `Visualizer.tscn` - Main game scene with layered visuals
- `Bullet.tscn` - Bullet prefab for pooling
- `Enemy.tscn` - Enemy prefab for pooling

## Game Balance

### Difficulty Scaling
- Enemy spawn interval: 1.5s (calm) to 0.4s (intense music)
- Enemy fire rate: 2.0s (calm) to 0.5s (intense music)
- Bullet speed: 150 px/s
- Player speed: 400 px/s normal, 200 px/s focused
- Combo timeout: 2 seconds between kills

### Score Values
- **Basic Enemy**: 10 points × combo multiplier
- **Fast Enemy**: 15 points × combo multiplier
- **Tank Enemy**: 25 points × combo multiplier
- **Elite Enemy**: 50 points × combo multiplier
- **Combo Multiplier**: 1.0x + 0.1x per consecutive kill

## Tips & Strategies

1. **Use Focus Mode**: Hold Shift in dense bullet patterns to see your true hitbox
2. **Watch the Zones**: Brighter frequency zones = more enemies incoming
3. **Build Combos**: Chain kills quickly for exponential score growth
4. **Listen to the Music**: Enemy spawns sync with beats and frequency spikes
5. **Stay Mobile**: Constant movement makes bullet dodging easier
6. **Learn Patterns**: Each enemy type has predictable bullet patterns you can memorize

## Future Enhancements

Potential features to add:
- Power-ups (shield, slow-time, screen-clearing bomb)
- Boss fights triggered on song climaxes
- Difficulty selection (easy/normal/hard/insane)
- High score persistence and leaderboards
- More enemy types with unique mechanics
- Particle effects for explosions and hits
- Player shooting mechanics
- Song analysis for intelligent difficulty curves

## Music Recommendations

Works best with:
- **Electronic/EDM**: Strong bass creates intense battles
- **Drum & Bass**: Fast-paced, challenging gameplay
- **Rock/Metal**: Heavy riffs spawn tank enemies
- **Orchestral**: Dynamic, flowing patterns
- **Hip-Hop**: Bass-heavy beat-synchronized spawns

---

**Built with Godot 4.5** | Designed for intense audio-reactive bullet hell gameplay

💡 **Tip**: Try different music genres to experience completely different gameplay styles!
