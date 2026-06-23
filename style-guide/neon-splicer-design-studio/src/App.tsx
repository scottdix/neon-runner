import React, { useState, useEffect, useRef } from "react";
import {
  Smartphone,
  Sparkles,
  Layers,
  Wand2,
  Gamepad2,
  Copy,
  Check,
  RotateCw,
  RefreshCw,
  Zap,
  Radio,
  Sliders,
  ChevronRight,
  User,
  Shield,
  Apple,
  Settings,
  Flame,
  Code2,
  Trash2,
  Plus,
  Play,
  RotateCcw,
  Palette,
  Volume2,
  Tv,
  ExternalLink,
  Cpu,
  Eye,
  Info
} from "lucide-react";

// Standard mobile shapes
interface VectorShape {
  id: string;
  name: string;
  description: string;
  godotType: string;
  previewDrawn: string; // SVG path
}

export default function App() {
  // Mobile UI & Theme Variables
  const [shipColor, setShipColor] = useState("#00f3ff");
  const [enemyColor, setEnemyColor] = useState("#ff007f");
  const [bulletColor, setBulletColor] = useState("#ffcb00");
  const [gridColor, setGridColor] = useState("#1a1aff");
  const [gateColor, setGateColor] = useState("#39ff14");
  const [hazardColor, setHazardColor] = useState("#ff3333");
  const [contrastMode, setContrastMode] = useState<"standard" | "amoled">("standard");

  // Device Simulation Controls
  const [deviceOS, setDeviceOS] = useState<"ios" | "android">("ios");
  const [orientation, setOrientation] = useState<"landscape" | "portrait">("portrait");
  const [safeAreaEnabled, setSafeAreaEnabled] = useState(true);
  const [fpsSetting, setFpsSetting] = useState<30 | 60 | 120>(60);
  const [screenFlow, setScreenFlow] = useState<"menu" | "customizer" | "gameplay" | "powerup" | "gameover">("gameplay");
  const [touchControlStyle, setTouchControlStyle] = useState<"relative" | "virtual_joystick">("relative");

  // Power-up Concepts
  const [powerupName, setPowerupName] = useState("Splicer Laser");
  const [powerupEffect, setPowerupEffect] = useState("Unleashes a constant hyper-speed slicer laser that splits multiplier gates.");
  const [activePowerup, setActivePowerup] = useState<string | null>(null);

  // Godot Export Shader/Script States
  const [godotTab, setGodotTab] = useState<"shaders" | "gdscripts" | "mobile_optimizations">("shaders");
  const [copiedText, setCopiedText] = useState(false);
  const [promptInput, setPromptInput] = useState("");
  const [aiResponse, setAiResponse] = useState<string | null>(null);
  const [isAiLoading, setIsAiLoading] = useState(false);

  // Gameplay Simulation State
  const [score, setScore] = useState(7452380);
  const [multiplier, setMultiplier] = useState(32);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [shipPosition, setShipPosition] = useState({ x: 150, y: 150 });
  const [isDragging, setIsDragging] = useState(false);
  const [hapticTriggered, setHapticTriggered] = useState<string | null>(null);

  // Built-in Godot CanvasItem shaders and scripts pre-loaded
  const PRE_LOADED_SHADERS = {
    mobileGlowShader: `shader_type canvas_item;

uniform vec4 neon_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 8.0) = 3.5;
uniform float pulse_frequency : hint_range(0.0, 10.0) = 2.0;
uniform float edge_thickness : hint_range(0.0, 0.5) = 0.15;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    
    // Create soft, cheap glowing border suitable for low-end mobile architectures
    float dist = distance(UV, vec2(0.5));
    float pulse = 0.8 + 0.2 * sin(TIME * pulse_frequency);
    
    // High-performance additive edge glow wrapper without dynamic loops
    float glow = smoothstep(0.5 - edge_thickness, 0.5, 0.5 - dist) * glow_intensity * pulse;
    
    vec4 final_color = mix(tex, neon_color, 1.0 - tex.a);
    final_color.rgb += neon_color.rgb * glow;
    final_color.a += glow * 0.4;
    
    COLOR = final_color;
}`,
    hapticScript: `extends Node
# High-Efficiency Godot 4 Haptic Wrapper for iOS & Android
# Integrates with system vibrations seamlessly without locking main threads

class_name SplicerHapticManager

signal haptic_dispatched(pattern_type)

func trigger_light_impact() -> void:
	if OS.get_name() == "Android":
		# Vibrates Android devices using modern high-precision API wrappers
		Input.vibrate_handheld(15) 
		emit_signal("haptic_dispatched", "light")
	elif OS.get_name() == "iOS":
		# Trigger through specific iOS plugin binding
		if Engine.has_singleton("iOSHapticFeedback"):
			Engine.get_singleton("iOSHapticFeedback").impact("light")
			emit_signal("haptic_dispatched", "light")

func trigger_medium_multiplier_surge() -> void:
	if OS.get_name() == "Android":
		Input.vibrate_handheld(35)
		emit_signal("haptic_dispatched", "medium")
	elif OS.get_name() == "iOS":
		if Engine.has_singleton("iOSHapticFeedback"):
			Engine.get_singleton("iOSHapticFeedback").impact("medium")

func trigger_danger_collision() -> void:
	if OS.get_name() == "Android":
		# Triplicate pulse emulation
		Input.vibrate_handheld(50)
		emit_signal("haptic_dispatched", "heavy")
`,
    mobileOptimizations: `# Optimize your Godot 4 Project Specifically for High-End Mobile Devices

[application]
run/max_fps=120 # Enable high refresh screens (iPhone Pro ProMotion & Asus ROG/Samsung 120Hz)
config/icon="res://icon.png"
config/name="Neon Splicer"

[display]
window/size/viewport_width=2400
window/size/viewport_height=1080
window/size/mode=4 # Landscape fullscreen
window/handheld/orientation=1 # Sensor Landscape

[rendering]
renderer/rendering_method="mobile" # Use GLES3-based mobile forward renderer (NOT Forward+/Vulkan for premium battery savings)
environment/defaults/default_clear_color=Color(0.02, 0.02, 0.03, 1)

# Essential project settings in Project Settings -> General -> Handheld
# 1. Check "vibrate" permissions in Android Gradle Export Settings
# 2. Check "UIRequiresFullScreen" in iOS Plist Customizations inside Export Presets
# 3. Enable HDR / Glow inside Godot's WorldEnvironment with GLES3 Mobile compatibility profile.`
  };

  const shapes: VectorShape[] = [
    {
      id: "glitch",
      name: "Glitch Enemy",
      godotType: "GPUParticles2D / Batch",
      description: "Low-overhead particle system simulating dynamic pixel corruptions.",
      previewDrawn: "M 10 10 L 25 10 L 25 25 L 10 25 Z M 40 30 L 60 30 L 60 50 L 40 50 Z"
    },
    {
      id: "rhombus",
      name: "Looming Rhombus",
      godotType: "Sprite2D with canvas_item shader",
      description: "Armored rotating threat that splits upon gate splicing.",
      previewDrawn: "M 50 10 L 90 50 L 50 90 L 10 50 Z M 50 25 L 75 50 L 50 75 L 25 50 Z"
    },
    {
      id: "fractal",
      name: "Fractal Orbit",
      godotType: "Pre-rendered texture rotation",
      description: "No real-time geo rendering. Static sprites with rotating UV offset shader.",
      previewDrawn: "M 50 10 C 20 20 20 80 50 90 C 80 80 80 20 50 10 Z"
    },
    {
      id: "singularity",
      name: "Dread Singularity",
      godotType: "Parallax texture stack",
      description: "A gravity well pulling gold bullet streams. Uses an efficient vortex fade shader.",
      previewDrawn: "M 50 50 A 40 40 0 1 0 50 49"
    }
  ];

  const [selectedShape, setSelectedShape] = useState<VectorShape>(shapes[1]);

  // Flash haptic confirmation in browser
  const triggerHapticSim = (type: "light" | "medium" | "heavy") => {
    setHapticTriggered(type);
    if (navigator.vibrate) {
      if (type === "light") navigator.vibrate(15);
      else if (type === "medium") navigator.vibrate(35);
      else if (type === "heavy") navigator.vibrate(80);
    }
    setTimeout(() => setHapticTriggered(null), 300);
  };

  // Reposition ship for optimal start on orientation change
  useEffect(() => {
    if (orientation === "portrait") {
      setShipPosition({ x: 145, y: 430 });
    } else {
      setShipPosition({ x: 312, y: 140 });
    }
  }, [orientation]);

  // Run the canvas game physics loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || screenFlow !== "gameplay") return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animId: number;
    let particles: Array<{ x: number; y: number; vx: number; vy: number; color: string; size: number; alpha: number }> = [];
    let bullets: Array<{ x: number; y: number; vx: number; vy: number }> = [];
    let enemies: Array<{ id: string; x: number; y: number; vx: number; vy: number; size: number; type: string; angle: number; rotSpeed: number }> = [];
    let gates: Array<{ id: string; x: number; y: number; label: string; value: number; size: number; passed: boolean }> = [];

    // Initialize objects
    for (let i = 0; i < 4; i++) {
      enemies.push({
        id: `enemy-${i}`,
        x: Math.random() * (canvas.width - 60) + 30,
        y: Math.random() * (canvas.height - 180) + 50,
        vx: (Math.random() - 0.5) * 1.5,
        vy: (Math.random() - 0.5) * 1.5,
        size: Math.random() * 20 + 20,
        type: shapes[Math.floor(Math.random() * shapes.length)].id,
        angle: Math.random() * Math.PI,
        rotSpeed: (Math.random() - 0.5) * 0.05
      });
    }

    // Add initial gates based on orientation
    if (orientation === "portrait") {
      gates.push({ id: "g1", x: canvas.width * 0.35, y: -100, label: "[ x2 ]", value: 2, size: 50, passed: false });
      gates.push({ id: "g2", x: canvas.width * 0.7, y: -350, label: "[ +12 ]", value: 12, size: 50, passed: false });
      gates.push({ id: "g3", x: canvas.width * 0.5, y: -600, label: "[ ÷2 ]", value: -2, size: 50, passed: false });
    } else {
      gates.push({ id: "g1", x: canvas.width + 100, y: canvas.height * 0.35, label: "[ x2 ]", value: 2, size: 50, passed: false });
      gates.push({ id: "g2", x: canvas.width + 350, y: canvas.height * 0.65, label: "[ +12 ]", value: 12, size: 50, passed: false });
      gates.push({ id: "g3", x: canvas.width + 600, y: canvas.height * 0.45, label: "[ ÷2 ]", value: -2, size: 50, passed: false });
    }

    let bulletCooldown = 0;
    let gridOffset = 0;

    const gameLoop = () => {
      // 1. Clear background (Standard dark Slate or AMOLED)
      ctx.fillStyle = contrastMode === "amoled" ? "#000000" : "#0a0a14";
      ctx.fillRect(0, 0, canvas.width, canvas.height);

      // 2. Draw Vector Warp Grid (with glowing blend mode)
      ctx.strokeStyle = gridColor + "22";
      ctx.lineWidth = 1;
      gridOffset = (gridOffset + 1.2) % 40;

      // Draw grid perspective pattern (warm cyber style)
      for (let x = -40 + gridOffset; x < canvas.width; x += 40) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, canvas.height);
        ctx.stroke();
      }
      for (let y = 0; y < canvas.height; y += 40) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(canvas.width, y);
        ctx.stroke();
      }

      // Safe Area lines if toggled
      if (safeAreaEnabled) {
        ctx.strokeStyle = "#ff00dd15";
        ctx.setLineDash([4, 4]);
        ctx.lineWidth = 2;
        // Draw device frame margins
        ctx.strokeRect(40, 16, canvas.width - 80, canvas.height - 32);
        ctx.setLineDash([]);
      }

      // 3. Fire gold bullet swarms
      bulletCooldown--;
      if (bulletCooldown <= 0) {
        const bulletSpeed = 9;
        if (orientation === "portrait") {
          // Shoot UPWARDS for portrait mode play
          bullets.push({
            x: shipPosition.x,
            y: shipPosition.y - 18,
            vx: (Math.random() - 0.5) * 3,
            vy: -bulletSpeed
          });
          if (activePowerup === "lasers") {
            bullets.push({ x: shipPosition.x - 12, y: shipPosition.y - 10, vx: 0, vy: -bulletSpeed * 1.3 });
            bullets.push({ x: shipPosition.x + 12, y: shipPosition.y - 10, vx: 0, vy: -bulletSpeed * 1.3 });
          }
        } else {
          // Directional fire towards forward (right-facing standard mobile bullet-hell)
          bullets.push({
            x: shipPosition.x + 18,
            y: shipPosition.y,
            vx: bulletSpeed,
            vy: (Math.random() - 0.5) * 3
          });
          if (activePowerup === "lasers") {
            bullets.push({ x: shipPosition.x + 18, y: shipPosition.y - 12, vx: bulletSpeed * 1.3, vy: 0 });
            bullets.push({ x: shipPosition.x + 18, y: shipPosition.y + 12, vx: bulletSpeed * 1.3, vy: 0 });
          }
        }
        bulletCooldown = activePowerup === "lasers" ? 2 : 5;
      }

      // Move & Draw Bullets
      ctx.fillStyle = bulletColor;
      bullets.forEach((b, index) => {
        b.x += b.vx;
        b.y += b.vy;

        // Custom bloom glow dot
        ctx.shadowColor = bulletColor;
        ctx.shadowBlur = 8;
        ctx.beginPath();
        ctx.arc(b.x, b.y, 2.5, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;

        // Clean out of bounds
        if (orientation === "portrait") {
          if (b.y < -20 || b.y > canvas.height + 20) {
            bullets.splice(index, 1);
          }
        } else {
          if (b.x < -20 || b.x > canvas.width + 20) {
            bullets.splice(index, 1);
          }
        }
      });

      // 4. Move & Update gates
      gates.forEach((g, idx) => {
        if (orientation === "portrait") {
          g.y += 2.0; // speed of arrival (falling downwards)
        } else {
          g.x -= 2.0; // speed of arrival (moving leftlands)
        }

        // Is hazard vs positive gate styling
        const isHazard = g.value < 0;
        const currentColor = isHazard ? hazardColor : gateColor;

        // Draw multiplier Gates as glowing parenthesis
        ctx.strokeStyle = currentColor;
        ctx.lineWidth = 2.5;
        ctx.shadowColor = currentColor;
        ctx.shadowBlur = 12;

        ctx.save();
        ctx.translate(g.x, g.y);
        if (orientation === "portrait") {
          // Rotate gate so it stands horizontally (perpendicular to descent path)
          ctx.rotate(Math.PI / 2);
        }

        ctx.beginPath();
        // Left bracket of gate
        ctx.moveTo(-20, -g.size / 2);
        ctx.lineTo(-30, -g.size / 2);
        ctx.lineTo(-30, g.size / 2);
        ctx.lineTo(-20, g.size / 2);
        // Right bracket of gate
        ctx.moveTo(20, -g.size / 2);
        ctx.lineTo(30, -g.size / 2);
        ctx.lineTo(30, g.size / 2);
        ctx.lineTo(20, g.size / 2);
        ctx.stroke();

        ctx.restore();
        ctx.shadowBlur = 0;

        // Label in gate font
        ctx.fillStyle = "#ffffff";
        ctx.font = "bold 13px 'Courier New', monospace";
        ctx.textAlign = "center";
        ctx.fillText(g.label, g.x, g.y + 4);

        // Check Splicing pass event
        const dxShip = Math.abs(shipPosition.x - g.x);
        const dyShip = Math.abs(shipPosition.y - g.y);

        let spliced = false;
        if (orientation === "portrait") {
          // If moving vertically, we check if ship aligns with y axis descent threshold
          spliced = (dyShip < 25 && dxShip < g.size / 2);
        } else {
          spliced = (dxShip < 25 && dyShip < g.size / 2);
        }

        if (spliced && !g.passed) {
          g.passed = true;
          if (isHazard) {
            setMultiplier(prev => Math.max(1, Math.round(prev / 2)));
            setScore(prev => Math.max(0, prev - 10000));
            triggerHapticSim("heavy");
            // Damage puff particles
            for (let i = 0; i < 15; i++) {
              particles.push({
                x: shipPosition.x,
                y: shipPosition.y,
                vx: (Math.random() - 0.5) * 6,
                vy: (Math.random() - 0.5) * 6,
                color: hazardColor,
                size: Math.random() * 3 + 1,
                alpha: 1
              });
            }
          } else {
            // Spliced multiplier increase!
            if (g.value === 2) {
              setMultiplier(prev => prev * 2);
              triggerHapticSim("medium");
            } else {
              setMultiplier(prev => prev + g.value);
              triggerHapticSim("light");
            }
            setScore(prev => prev + 250000 * multiplier);

            // Flash neon gold spark ring
            for (let i = 0; i < 25; i++) {
              particles.push({
                x: g.x,
                y: g.y,
                vx: (Math.random() - 0.5) * 8,
                vy: (Math.random() - 0.5) * 8,
                color: gateColor,
                size: Math.random() * 4 + 1.5,
                alpha: 1
              });
            }
          }
        }

        // Wrap around
        if (orientation === "portrait") {
          if (g.y > canvas.height + 50) {
            g.y = -100 - Math.random() * 200;
            g.x = Math.random() * (canvas.width - 100) + 50;
            g.passed = false;
          }
        } else {
          if (g.x < -100) {
            g.x = canvas.width + Math.random() * 200 + 100;
            g.y = Math.random() * (canvas.height - 100) + 50;
            g.passed = false;
          }
        }
      });

      // 5. Update and Draw Vector Enemies
      enemies.forEach((enemy, index) => {
        enemy.x += enemy.vx;
        enemy.y += enemy.vy;
        enemy.angle += enemy.rotSpeed;

        // Bounce from walls
        if (enemy.x < 40 || enemy.x > canvas.width - 40) enemy.vx *= -1;
        if (enemy.y < 20 || enemy.y > canvas.height - 20) enemy.vy *= -1;

        // Draw enemies based on type
        ctx.strokeStyle = enemyColor;
        ctx.lineWidth = 1.8;
        ctx.shadowColor = enemyColor;
        ctx.shadowBlur = 8;
        ctx.save();
        ctx.translate(enemy.x, enemy.y);
        ctx.rotate(enemy.angle);

        if (enemy.type === "rhombus") {
          // Draw standard Rhombus shape
          ctx.beginPath();
          ctx.moveTo(0, -enemy.size / 2);
          ctx.lineTo(enemy.size / 2, 0);
          ctx.lineTo(0, enemy.size / 2);
          ctx.lineTo(-enemy.size / 2, 0);
          ctx.closePath();
          ctx.stroke();

          // Inner mini rhombus
          ctx.beginPath();
          ctx.moveTo(0, -enemy.size / 4);
          ctx.lineTo(enemy.size / 4, 0);
          ctx.lineTo(0, enemy.size / 4);
          ctx.lineTo(-enemy.size / 4, 0);
          ctx.closePath();
          ctx.stroke();
        } else if (enemy.type === "glitch") {
          // Double rectangles offsets
          ctx.strokeRect(-enemy.size / 2, -enemy.size / 2, enemy.size, enemy.size);
          ctx.strokeRect(-enemy.size / 3 + Math.sin(Date.now() * 0.05) * 3, -enemy.size / 3, enemy.size / 1.5, enemy.size / 1.5);
        } else if (enemy.type === "singularity") {
          // Draw spiral
          ctx.beginPath();
          for (let i = 0; i < 30; i++) {
            const angle = 0.1 * i + (Date.now() * 0.01);
            const r = (enemy.size / 30) * i;
            const xVal = r * Math.cos(angle);
            const yVal = r * Math.sin(angle);
            if (i === 0) ctx.moveTo(xVal, yVal);
            else ctx.lineTo(xVal, yVal);
          }
          ctx.stroke();
        } else {
          // Fractal orbit
          ctx.beginPath();
          ctx.arc(0, 0, enemy.size / 3, 0, Math.PI * 2);
          ctx.stroke();
          ctx.beginPath();
          ctx.arc(0, -enemy.size / 2, 5, 0, Math.PI * 2);
          ctx.stroke();
          ctx.beginPath();
          ctx.arc(0, enemy.size / 2, 5, 0, Math.PI * 2);
          ctx.stroke();
        }

        ctx.restore();
        ctx.shadowBlur = 0;

        // Core collision with player gold bullets
        bullets.forEach((bullet, bidx) => {
          const dist = Math.hypot(bullet.x - enemy.x, bullet.y - enemy.y);
          if (dist < enemy.size / 1.6) {
            // Explode enemy
            triggerHapticSim("light");
            setScore(prev => prev + 150 * multiplier);

            // Explosion particles
            for (let i = 0; i < 15; i++) {
              particles.push({
                x: enemy.x,
                y: enemy.y,
                vx: (Math.random() - 0.5) * 6,
                vy: (Math.random() - 0.5) * 6,
                color: enemyColor,
                size: Math.random() * 3 + 1,
                alpha: 1
              });
            }

            // Remove bullet
            bullets.splice(bidx, 1);

            // Re-spawn enemy elsewhere to keep simulator active
            if (orientation === "portrait") {
              enemy.y = -100;
              enemy.x = Math.random() * (canvas.width - 100) + 50;
            } else {
              enemy.x = canvas.width + 100;
              enemy.y = Math.random() * (canvas.height - 100) + 50;
            }
            enemy.vx = (Math.random() - 0.5) * 1.5;
            enemy.vy = (Math.random() - 0.5) * 1.5;
          }
        });

        // Player collision checking
        const playerShipDist = Math.hypot(shipPosition.x - enemy.x, shipPosition.y - enemy.y);
        if (playerShipDist < 25) {
          // Play heavy screen shake and haptic surge
          triggerHapticSim("heavy");
          setMultiplier(1);
          if (orientation === "portrait") {
            enemy.y = -150;
            enemy.x = Math.random() * (canvas.width - 100) + 50;
          } else {
            enemy.x = canvas.width + 150; // teleport away
          }
        }
      });

      // 6. Draw glowing Cyan Player Ship (Order Arrow)
      ctx.save();
      ctx.translate(shipPosition.x, shipPosition.y);
      if (orientation === "portrait") {
        ctx.rotate(-Math.PI / 2); // Point up towards incoming gates
      }
      ctx.strokeStyle = shipColor;
      ctx.lineWidth = 2.5;
      ctx.shadowColor = shipColor;
      ctx.shadowBlur = 10;

      ctx.beginPath();
      ctx.moveTo(15, 0);       // Nose
      ctx.lineTo(-12, -10);    // Bottom wing
      ctx.lineTo(-6, -4);     // Inner tail notch
      ctx.lineTo(-6, 4);      // Inner tail notch
      ctx.lineTo(-12, 10);     // Top wing
      ctx.closePath();
      ctx.stroke();

      // Custom additive engine flare
      ctx.fillStyle = bulletColor;
      ctx.shadowColor = bulletColor;
      ctx.shadowBlur = 12;
      ctx.beginPath();
      ctx.moveTo(-7, -3);
      ctx.lineTo(-20 - (Math.random() * 10), 0);
      ctx.lineTo(-7, 3);
      ctx.closePath();
      ctx.fill();

      // Power-up shield aura if active
      if (activePowerup) {
        ctx.strokeStyle = "#ffffff";
        ctx.shadowColor = shipColor;
        ctx.shadowBlur = 20;
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.arc(0, 0, 22, 0, Math.PI * 2);
        ctx.stroke();
      }

      ctx.restore();
      ctx.shadowBlur = 0;

      // 7. Update Particles
      particles.forEach((p, index) => {
        p.x += p.vx;
        p.y += p.vy;
        p.alpha -= 0.035;
        if (p.alpha <= 0) {
          particles.splice(index, 1);
        } else {
          ctx.fillStyle = p.color;
          ctx.globalAlpha = p.alpha;
          ctx.fillRect(p.x, p.y, p.size, p.size);
        }
      });
      ctx.globalAlpha = 1.0;

      // Draw active UI HUD indicators directly inside the game space (simulating raw Godot HUD layout)
      ctx.fillStyle = "#ffffff";
      ctx.font = "10px 'Courier New', monospace";
      ctx.textAlign = "left";
      ctx.fillText(`FPS: ${fpsSetting}`, 50, 25);
      ctx.fillText(`LATENCY: 5ms`, 50, 37);

      ctx.textAlign = "right";
      ctx.fillText(`HAPTICS: ${hapticEnabledState()}`, canvas.width - 50, 25);

      animId = requestAnimationFrame(gameLoop);
    };

    gameLoop();

    return () => {
      cancelAnimationFrame(animId);
    };
  }, [shipPosition, shipColor, enemyColor, bulletColor, gridColor, gateColor, hazardColor, contrastMode, safeAreaEnabled, activePowerup, fpsSetting]);

  function hapticEnabledState() {
    return hapticTriggered ? `[ ${hapticTriggered.toUpperCase()} ]` : "READY";
  }

  // Handle mobile dragging simulation
  const handleMouseDown = (e: React.MouseEvent<HTMLCanvasElement>) => {
    setIsDragging(true);
    setShipPosFromEvent(e);
  };

  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
    if (!isDragging) return;
    setShipPosFromEvent(e);
  };

  const handleMouseUp = () => {
    setIsDragging(false);
  };

  const handleTouchStart = (e: React.TouchEvent<HTMLCanvasElement>) => {
    setIsDragging(true);
    if (e.touches.length > 0) {
      setShipPosFromTouch(e.touches[0]);
    }
  };

  const handleTouchMove = (e: React.TouchEvent<HTMLCanvasElement>) => {
    if (!isDragging) return;
    if (e.touches.length > 0) {
      setShipPosFromTouch(e.touches[0]);
    }
  };

  const handleTouchEnd = () => {
    setIsDragging(false);
  };

  const setShipPosFromEvent = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const clickX = ((e.clientX - rect.left) / rect.width) * canvas.width;
    const clickY = ((e.clientY - rect.top) / rect.height) * canvas.height;
    // Set with slight margin padding
    setShipPosition({
      x: Math.max(30, Math.min(canvas.width - 35, clickX)),
      y: Math.max(30, Math.min(canvas.height - 30, clickY))
    });
  };

  const setShipPosFromTouch = (touch: React.Touch) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const clickX = ((touch.clientX - rect.left) / rect.width) * canvas.width;
    const clickY = ((touch.clientY - rect.top) / rect.height) * canvas.height;
    setShipPosition({
      x: Math.max(30, Math.min(canvas.width - 35, clickX)),
      y: Math.max(30, Math.min(canvas.height - 30, clickY))
    });
  };

  // Trigger dynamic custom query through backend Gemini API
  const handleGenerateAI = async () => {
    setIsAiLoading(true);
    try {
      const response = await fetch("/api/brainstorm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          themeColors: {
            shipColor,
            enemyColor,
            bulletColor,
            gridColor
          },
          activeScreen: screenFlow,
          customPrompt: promptInput || "Explain mobile UI best practice safe areas for 19.5:9 rounded smartphones and generate Godot 4 camera anchoring.",
          refinedScope: "general"
        })
      });
      const data = await response.json();
      if (data.success) {
        setAiResponse(data.analysis);
      } else {
        setAiResponse(`Failed to call developer AI. Error: ${data.message}`);
      }
    } catch (e: any) {
      setAiResponse(`Error establishing AI connection: ${e.message}`);
    } finally {
      setIsAiLoading(false);
    }
  };

  const handleGenerateAIForShape = async (shape: VectorShape) => {
    setIsAiLoading(true);
    setGodotTab("shaders");
    try {
      const response = await fetch("/api/brainstorm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          selectedShape: {
            name: shape.name,
            color: enemyColor,
            bloomScale: 3.0,
            rotateSpeed: 1.2,
            distortion: 0.35
          },
          refinedScope: "shape_shader"
        })
      });
      const data = await response.json();
      if (data.success) {
        setAiResponse(data.analysis);
      } else {
        setAiResponse(`Failed to configure shape. Error: ${data.message}`);
      }
    } catch (e: any) {
      setAiResponse(`Error generating shader: ${e.message}`);
    } finally {
      setIsAiLoading(false);
    }
  };

  const handleGenerateAIPowerup = async () => {
    setIsAiLoading(true);
    setGodotTab("gdscripts");
    try {
      const response = await fetch("/api/brainstorm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          powerupConcept: {
            name: powerupName,
            effect: powerupEffect
          },
          themeColors: {
            shipColor,
            bulletColor
          },
          refinedScope: "powerup"
        })
      });
      const data = await response.json();
      if (data.success) {
        setAiResponse(data.analysis);
      } else {
        setAiResponse(`Failed to configure powerup. Error: ${data.message}`);
      }
    } catch (e: any) {
      setAiResponse(`Error generating power-up controller: ${e.message}`);
    } finally {
      setIsAiLoading(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedText(true);
    setTimeout(() => setCopiedText(false), 2000);
  };

  return (
    <div className={`min-h-screen ${contrastMode === "amoled" ? "bg-black" : "bg-slate-950"} text-slate-100 flex flex-col font-sans overflow-x-hidden transition-colors duration-300`}>
      {/* 1. Header Bar with Neon Title Header */}
      <header className="border-b border-slate-900 bg-slate-900/60 backdrop-blur-md px-6 py-4 flex items-center justify-between sticky top-0 z-40">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-lg bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center">
            <Zap className="h-5 w-5 text-cyan-400 animate-pulse" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold tracking-wider text-cyan-400 bg-cyan-400/10 px-2 py-0.5 rounded-full uppercase">
                Godot 4 Mobile Tool
              </span>
              <span className="text-xs font-bold text-emerald-400 flex items-center gap-1">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping" /> iOS/Android Focused
              </span>
            </div>
            <h1 className="text-xl font-black italic tracking-tight text-white uppercase mt-0.5 font-sans">
              Neon Splicer <span className="text-slate-500 font-light font-serif">/</span> Design Investigation Studio
            </h1>
          </div>
        </div>

        <div className="flex items-center gap-4">
          {/* Theme Mode Toggles */}
          <div className="bg-slate-950 p-1 rounded-lg border border-slate-800 flex items-center text-xs">
            <button
              onClick={() => setContrastMode("standard")}
              className={`px-3 py-1.5 rounded font-medium transition-all ${
                contrastMode === "standard"
                  ? "bg-slate-800 text-cyan-400 border border-slate-700 shadow-sm"
                  : "text-slate-400 hover:text-slate-200"
              }`}
            >
              Standard OLED
            </button>
            <button
              onClick={() => setContrastMode("amoled")}
              className={`px-3 py-1.5 rounded font-medium transition-all ${
                contrastMode === "amoled"
                  ? "bg-slate-900 text-purple-400 border border-purple-900 shadow-sm"
                  : "text-slate-400 hover:text-slate-200"
              }`}
            >
              AMOLED Deep Black
            </button>
          </div>

          <a
            href="https://ai.studio/build"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-slate-400 hover:text-white flex items-center gap-1.5 border border-slate-800 px-3 py-1.5 rounded-lg bg-slate-950/40"
          >
            AI Studio Preview <ExternalLink className="h-3 w-3" />
          </a>
        </div>
      </header>

      {/* Main Grid Workspace Container */}
      <div className="flex-1 grid grid-cols-1 lg:grid-cols-12 gap-6 p-4 lg:p-6">
        
        {/* LEFT PANEL (Col 1-3.5): Aesthetics, Safe Area Settings, and Shape laboratory */}
        <aside className="lg:col-span-3 flex flex-col gap-6 order-2 lg:order-1">
          {/* Aesthetic Controls */}
          <div className="bg-slate-900/40 border border-slate-800/80 rounded-xl p-5 shadow-lg relative overflow-hidden">
            <div className="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-cyan-500 to-purple-500" />
            <h2 className="text-sm font-bold uppercase tracking-wider text-slate-300 flex items-center gap-2 mb-4">
              <Palette className="h-4 w-4 text-cyan-400" /> Vector Color Engine
            </h2>

            <div className="space-y-4">
              {/* Ship color */}
              <div>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-slate-400 font-medium">Player Vector Arrow</span>
                  <span className="text-cyan-400 font-mono text-xs">{shipColor}</span>
                </div>
                <div className="flex gap-2">
                  <input
                    type="color"
                    value={shipColor}
                    onChange={(e) => setShipColor(e.target.value)}
                    className="w-10 h-8 rounded bg-slate-950 border border-slate-800 cursor-pointer p-0.5"
                  />
                  <div className="flex justify-between w-full gap-1">
                    {["#00f3ff", "#39ff14", "#ff00ff", "#ffffff"].map((c) => (
                      <button
                        key={c}
                        onClick={() => setShipColor(c)}
                        className="w-full h-8 rounded border border-slate-800"
                        style={{ backgroundColor: c }}
                        title={c}
                      />
                    ))}
                  </div>
                </div>
              </div>

              {/* Enemy color */}
              <div>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-slate-400 font-medium">Entropy Enemies (Bloom)</span>
                  <span className="text-rose-400 font-mono text-xs">{enemyColor}</span>
                </div>
                <div className="flex gap-2">
                  <input
                    type="color"
                    value={enemyColor}
                    onChange={(e) => setEnemyColor(e.target.value)}
                    className="w-10 h-8 rounded bg-slate-950 border border-slate-800 cursor-pointer p-0.5"
                  />
                  <div className="flex justify-between w-full gap-1">
                    {["#ff007f", "#ff3333", "#ffae00", "#9c27b0"].map((c) => (
                      <button
                        key={c}
                        onClick={() => setEnemyColor(c)}
                        className="w-full h-8 rounded border border-slate-800"
                        style={{ backgroundColor: c }}
                        title={c}
                      />
                    ))}
                  </div>
                </div>
              </div>

              {/* Bullets & Grid color */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-[11px] text-slate-400 mb-1 font-medium">Bullet Swarm</label>
                  <input
                    type="color"
                    value={bulletColor}
                    onChange={(e) => setBulletColor(e.target.value)}
                    className="w-full h-8 rounded bg-slate-950 border border-slate-800 cursor-pointer p-0.5"
                  />
                </div>
                <div>
                  <label className="block text-[11px] text-slate-400 mb-1 font-medium">Warp Grid Floor</label>
                  <input
                    type="color"
                    value={gridColor}
                    onChange={(e) => setGridColor(e.target.value)}
                    className="w-full h-8 rounded bg-slate-950 border border-slate-800 cursor-pointer p-0.5"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3 pt-1">
                <div>
                  <label className="block text-[11px] text-slate-400 mb-1 font-medium">Positive Gates</label>
                  <input
                    type="color"
                    value={gateColor}
                    onChange={(e) => setGateColor(e.target.value)}
                    className="w-full h-8 rounded bg-slate-950 border border-slate-800 cursor-pointer p-0.5"
                  />
                </div>
                <div>
                  <label className="block text-[11px] text-slate-400 mb-1 font-medium">Divide Gates</label>
                  <input
                    type="color"
                    value={hazardColor}
                    onChange={(e) => setHazardColor(e.target.value)}
                    className="w-full h-8 rounded bg-slate-950 border border-slate-800 cursor-pointer p-0.5"
                  />
                </div>
              </div>
            </div>
          </div>

          {/* Entropy Enemy Faction laboratory */}
          <div className="bg-slate-900/40 border border-slate-800/80 rounded-xl p-5 shadow-lg">
            <h2 className="text-sm font-bold uppercase tracking-wider text-slate-300 flex items-center justify-between mb-3">
              <span className="flex items-center gap-2">
                <Layers className="h-4 w-4 text-purple-400" /> Entropy Shape Lab
              </span>
              <span className="text-[10px] text-purple-400 font-mono bg-purple-400/10 px-1.5 py-0.5 rounded">Mobile-optimized</span>
            </h2>
            <p className="text-[11px] text-slate-400 mb-4 leading-relaxed">
              In Geometry Wars, drawing vector graphics in real-time has high GPU cost. Select a shape to load optimization blueprints:
            </p>

            <div className="space-y-2.5">
              {shapes.map((shape) => (
                <button
                  key={shape.id}
                  onClick={() => {
                    setSelectedShape(shape);
                    triggerHapticSim("light");
                  }}
                  className={`w-full text-left p-3 rounded-lg border transition-all flex items-center gap-3 ${
                    selectedShape.id === shape.id
                      ? "bg-purple-950/20 border-purple-500/60 shadow-md shadow-purple-950/10"
                      : "bg-slate-950/40 border-slate-800 hover:border-slate-700"
                  }`}
                >
                  <svg className="w-8 h-8 flex-shrink-0" viewBox="0 0 100 100">
                    <path
                      d={shape.previewDrawn}
                      stroke={enemyColor}
                      strokeWidth="6"
                      fill="none"
                      className="drop-shadow-[0_0_6px_var(--color-rose-500)]"
                    />
                  </svg>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-white block truncate">{shape.name}</span>
                    </div>
                    <span className="text-[9px] font-mono text-slate-500 block truncate uppercase mt-0.5">
                      {shape.godotType}
                    </span>
                  </div>
                </button>
              ))}
            </div>

            <div className="mt-4 bg-slate-950/80 rounded-lg p-3 border border-slate-800/50">
              <div className="flex items-center gap-2 justify-between">
                <span className="text-[10px] font-bold text-purple-400 tracking-wider font-mono">SELECTED SHAPE SHADER</span>
                <button
                  onClick={() => handleGenerateAIForShape(selectedShape)}
                  disabled={isAiLoading}
                  className="bg-purple-600 hover:bg-purple-500 text-white font-bold text-[10px] px-2.5 py-1 rounded transition-all flex items-center gap-1 cursor-pointer disabled:opacity-50"
                >
                  Generate Shader <Wand2 className="h-3 w-3" fill="currentColor" />
                </button>
              </div>
              <p className="text-[11px] text-slate-400 mt-1.5 leading-normal italic">
                {selectedShape.description}
              </p>
            </div>
          </div>

          {/* Quick Haptic Vibration profiles for Mobile Controllers */}
          <div className="bg-slate-900/40 border border-slate-800/80 rounded-xl p-5 shadow-lg">
            <h2 className="text-sm font-bold uppercase tracking-wider text-slate-300 flex items-center gap-2 mb-2">
              <Radio className="h-4 w-4 text-emerald-400" /> Device Haptic Profiler
            </h2>
            <p className="text-[11px] text-slate-400 mb-3 leading-relaxed">
              Test tactile feedback trigger waves mapped to screen gameplay interactions:
            </p>

            <div className="grid grid-cols-3 gap-2">
              <button
                onClick={() => triggerHapticSim("light")}
                className="bg-slate-950 hover:bg-slate-900 text-xs text-white border border-slate-800 p-2.5 rounded-lg flex flex-col items-center justify-center gap-1 active:scale-95 transition-all"
              >
                <div className="h-2 w-2 rounded-full bg-emerald-500" />
                <span className="font-bold text-[10px] uppercase">Light Hit</span>
                <span className="text-[8px] text-slate-500">15ms Burst</span>
              </button>

              <button
                onClick={() => triggerHapticSim("medium")}
                className="bg-slate-950 hover:bg-slate-900 text-xs text-white border border-slate-800 p-2.5 rounded-lg flex flex-col items-center justify-center gap-1 active:scale-95 transition-all"
              >
                <div className="h-2 w-2 rounded-full bg-cyan-500" />
                <span className="font-bold text-[10px] uppercase">Gate Splice</span>
                <span className="text-[8px] text-slate-500">35ms Wave</span>
              </button>

              <button
                onClick={() => triggerHapticSim("heavy")}
                className="bg-slate-950 hover:bg-slate-900 text-xs text-white border border-slate-800 p-2.5 rounded-lg flex flex-col items-center justify-center gap-1 active:scale-95 transition-all"
              >
                <div className="h-2 w-2 rounded-full bg-red-500 animate-ping" />
                <span className="font-bold text-[10px] uppercase">Death Hit</span>
                <span className="text-[8px] text-slate-500">80ms Shock</span>
              </button>
            </div>
            {hapticTriggered && (
              <div className="mt-3 text-center text-[10px] text-emerald-400 font-mono bg-emerald-950/25 border border-emerald-500/20 py-1 rounded">
                Simulated {hapticTriggered.toUpperCase()} Haptic Vibration Dispatched to physical device.
              </div>
            )}
          </div>
        </aside>

        {/* MIDDLE PANEL (Col 3.5-8.5): High-Fidelity Mobile Emulator */}
        <section className="lg:col-span-5 flex flex-col items-center justify-start gap-4 p-2">
          
          {/* Simulation Viewport Screen Manager Header */}
          <div className="w-full flex justify-between items-center bg-slate-900/60 border border-slate-800/60 p-3 rounded-lg">
            <div className="flex items-center gap-2">
              <Smartphone className="h-4 w-4 text-cyan-400" />
              <span className="text-xs font-bold text-white">Flow:</span>
              <div className="flex gap-1">
                {[
                  { id: "menu", label: "Menu" },
                  { id: "customizer", label: "Customizer" },
                  { id: "gameplay", label: "Gameplay" },
                  { id: "powerup", label: "Power-up" },
                  { id: "gameover", label: "Game Over" }
                ].map((s) => (
                  <button
                    key={s.id}
                    onClick={() => {
                      setScreenFlow(s.id as any);
                      triggerHapticSim("light");
                    }}
                    className={`text-[10.5px] px-2.5 py-1 rounded font-bold uppercase tracking-tight transition-all ${
                      screenFlow === s.id
                        ? "bg-cyan-500 text-slate-950 font-black shadow-lg shadow-cyan-500/20"
                        : "bg-slate-950 text-slate-400 hover:text-white"
                    }`}
                  >
                    {s.label}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* Smartphone Simulator Chassis with Screen Ratio Toggles */}
          <div className="text-center w-full flex justify-center gap-4 text-xs">
            <div className="flex items-center gap-4 bg-slate-950 border border-slate-800 px-3 py-1.5 rounded-lg">
              <span className="text-[11px] text-slate-400">Device Platform:</span>
              <button
                onClick={() => setDeviceOS("ios")}
                className={`font-semibold flex items-center gap-1 ${deviceOS === "ios" ? "text-cyan-400 font-black" : "text-slate-500"}`}
              >
                <Apple className="h-3 w-3" /> iOS (ProMotion)
              </button>
              <span className="text-slate-800">|</span>
              <button
                onClick={() => setDeviceOS("android")}
                className={`font-semibold flex items-center gap-1 ${deviceOS === "android" ? "text-cyan-400 font-black" : "text-slate-500"}`}
              >
                <Smartphone className="h-3 w-3" /> Android (Vulkan method compatible)
              </button>
            </div>

            <div className="flex items-center gap-4 bg-slate-950 border border-slate-800 px-3 py-1.5 rounded-lg">
              <span className="text-[11px] text-slate-400">Orientation:</span>
              <button
                onClick={() => setOrientation("landscape")}
                className={`font-semibold flex items-center gap-1 ${orientation === "landscape" ? "text-cyan-400 font-black" : "text-slate-500"}`}
              >
                Landscape
              </button>
              <span className="text-slate-800">|</span>
              <button
                onClick={() => setOrientation("portrait")}
                className={`font-semibold flex items-center gap-1 ${orientation === "portrait" ? "text-cyan-400 font-black" : "text-slate-500"}`}
              >
                Portrait
              </button>
            </div>
          </div>

          {/* Actual Outer Phone Chassis container */}
          <div
            className={`relative transition-all duration-300 border-4 border-slate-800 rounded-[38px] bg-slate-950 shadow-2xl p-3 flex flex-col items-center justify-center ${
              orientation === "landscape"
                ? "w-full max-w-2xl aspect-[19.5/9]"
                : "w-[305px] h-[610px]"
            }`}
            style={{
              boxShadow: `0 25px 60px -15px rgba(0, 0, 0, 0.9), 0 0 20px 2px ${shipColor}20`
            }}
          >
            {/* Camera / Notch simulation */}
            {deviceOS === "ios" ? (
              // Dynamic Island
              <div
                className={`absolute bg-black rounded-full z-30 transition-all ${
                  orientation === "landscape"
                    ? "left-6 top-1/2 -translate-y-1/2 w-[18px] h-[65px]"
                    : "top-5 left-1/2 -translate-x-1/2 w-[65px] h-[18px]"
                }`}
              />
            ) : (
              // Android Camera Punch-Hole
              <div
                className={`absolute bg-neutral-900 rounded-full border border-neutral-800 z-30 ${
                  orientation === "landscape"
                    ? "left-7 top-1/2 -translate-y-1/2 h-3 w-3"
                    : "top-6 left-1/2 -translate-x-1/2 h-3 w-3"
                }`}
              />
            )}

            {/* Internal Phone Bezel and Screen Area */}
            <div className="relative w-full h-full rounded-[28px] overflow-hidden bg-slate-950 border border-slate-900 flex flex-col justify-between">
              
              {/* STATUS BAR */}
              <div className="absolute top-0 inset-x-0 h-6 px-7 z-20 flex justify-between items-center text-[10px] text-slate-400/80 font-mono pointer-events-none">
                <span>08:02 AM</span>
                <div className="flex items-center gap-1 bg-black/40 px-2 py-0.5 rounded-full">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                  <span className="text-[8px] font-bold text-white uppercase">{deviceOS} HAPTICS</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <Tv className="h-2.5 w-2.5" />
                  <span>LT-60 FPS</span>
                  <span>100%</span>
                </div>
              </div>

              {/* GAME SCREEN BODY FLOWS */}
              <div className="w-full h-full flex-1 relative flex flex-col justify-between pt-6 pb-4">
                
                {/* 1. MAIN MENU SCREEN FLOW */}
                {screenFlow === "menu" && (
                  <div className="w-full h-full flex flex-col items-center justify-center p-6 text-center select-none bg-radial from-slate-900 via-slate-950 to-slate-950">
                    <div className="relative my-auto">
                      {/* Animated Grid Lines behind title */}
                      <div className="absolute -inset-10 bg-gradient-to-r from-purple-500/10 to-cyan-500/10 rounded-full blur-2xl" />
                      
                      <h1 className="text-3xl font-black italic tracking-tighter uppercase relative">
                        <span className="absolute -top-4 left-1/2 -translate-x-1/2 text-[10px] text-cyan-400 tracking-widest uppercase font-mono font-bold">
                          VECTOR GATE RUNNER
                        </span>
                        <span className="bg-gradient-to-b from-white to-slate-400 bg-clip-text text-transparent">NEON</span>{" "}
                        <span style={{ color: shipColor }} className="drop-shadow-[0_0_8px_currentColor]">SPLICER</span>
                      </h1>
                      <p className="text-[10px] font-mono tracking-wide text-slate-400 mt-2 max-w-xs mx-auto">
                        HOMAGE TO GEOMETRY WARS FOR DECENTRALIZED MOBILE PHONES
                      </p>
                    </div>

                    <div className="flex flex-col gap-2 w-full max-w-[200px] mb-4">
                      <button
                        onClick={() => {
                          setScreenFlow("gameplay");
                          triggerHapticSim("medium");
                        }}
                        className="bg-white hover:bg-slate-200 text-slate-950 font-black text-xs py-2.5 rounded-lg uppercase tracking-wider flex items-center justify-center gap-1 border border-white"
                      >
                        <Play className="h-3 w-3 fill-slate-900" /> TAP TO INITIALIZE
                      </button>

                      <button
                        onClick={() => {
                          setScreenFlow("customizer");
                          triggerHapticSim("light");
                        }}
                        className="bg-slate-900/80 hover:bg-slate-800 text-white font-bold text-xs py-2 rounded-lg tracking-wider border border-slate-800"
                      >
                        SHIP SPLICER CUSTOMIZER
                      </button>
                    </div>

                    <div className="text-[9px] font-mono text-slate-500 border-t border-slate-900/80 pt-2 w-full max-w-xs">
                      v4.2-GDX MOBILE CORE // ACCENT: {shipColor}
                    </div>
                  </div>
                )}

                {/* 2. SHIP CUSTOMIZER FLOW */}
                {screenFlow === "customizer" && (
                  <div className="w-full h-full flex flex-col justify-between p-6 select-none bg-slate-950">
                    <div className="text-center mt-2">
                      <h2 className="text-md font-extrabold italic uppercase tracking-wider">
                        SPLICER HULL LAB
                      </h2>
                      <p className="text-[10px] text-slate-400">Choose your light-form chassis</p>
                    </div>

                    {/* Ship Preview Area */}
                    <div className="my-auto flex items-center justify-center relative">
                      <div className="absolute inset-0 bg-cyan-500/10 rounded-full blur-2xl w-24 h-24 mx-auto" />
                      {/* Interactive responsive mockup shape */}
                      <svg className="w-20 h-20 animate-pulse relative" viewBox="0 0 100 100">
                        <polygon
                          points="50,15 15,80 35,70 50,78 65,70 85,80"
                          stroke={shipColor}
                          strokeWidth="4.5"
                          fill="none"
                          className="drop-shadow-[0_0_12px_var(--color-cyan-500)]"
                        />
                        <polygon points="53,40 40,65 50,58 60,65" fill={bulletColor} />
                      </svg>
                    </div>

                    <div className="space-y-2">
                      <span className="text-[10px] font-mono text-slate-500 text-center block">
                        CYAN SHIP FORM - GLOW ENVELOPE: {shipColor}
                      </span>
                      <div className="flex gap-2">
                        <button
                          onClick={() => {
                            setShipColor("#00f3ff");
                            triggerHapticSim("light");
                          }}
                          className="flex-1 py-1.5 rounded bg-slate-900 border border-slate-800 text-[10px] font-bold text-cyan-400"
                        >
                          CHRONO BLUE
                        </button>
                        <button
                          onClick={() => {
                            setShipColor("#ff00ff");
                            triggerHapticSim("light");
                          }}
                          className="flex-1 py-1.5 rounded bg-slate-900 border border-slate-800 text-[10px] font-bold text-fuchsia-400"
                        >
                          CORRUPT PINK
                        </button>
                        <button
                          onClick={() => {
                            setShipColor("#39ff14");
                            triggerHapticSim("light");
                          }}
                          className="flex-1 py-1.5 rounded bg-slate-900 border border-slate-800 text-[10px] font-bold text-emerald-400"
                        >
                          OVERCLOCKED ACID
                        </button>
                      </div>

                      <button
                        onClick={() => {
                          setScreenFlow("gameplay");
                          triggerHapticSim("medium");
                        }}
                        className="bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-black text-xs py-2 rounded-lg w-full uppercase"
                      >
                        CONFIRM & LOAD STAGE
                      </button>
                    </div>
                  </div>
                )}

                {/* 3. GAMEPLAY SIMULATOR SCREEN */}
                {screenFlow === "gameplay" && (
                  <div className="w-full h-full relative flex flex-col justify-between select-none">
                    {/* Game Canvas backplate */}
                    <canvas
                      ref={canvasRef}
                      width={orientation === "landscape" ? 624 : 290}
                      height={orientation === "landscape" ? 280 : 540}
                      onMouseDown={handleMouseDown}
                      onMouseMove={handleMouseMove}
                      onMouseUp={handleMouseUp}
                      onTouchStart={handleTouchStart}
                      onTouchMove={handleTouchMove}
                      onTouchEnd={handleTouchEnd}
                      className="absolute inset-0 w-full h-full cursor-crosshair"
                    />

                    {/* Active HUD overlay */}
                    <div className="relative z-10 p-3 pointer-events-none w-full flex justify-between items-start mt-2">
                      {/* Left: Custom Score and Multiplier */}
                      <div className="flex flex-col">
                        <span className="text-[10px] font-mono text-slate-400 leading-none">SCORE</span>
                        <span className="text-lg font-black tracking-tight text-white leading-tight font-mono">
                          {score.toLocaleString()}
                        </span>
                      </div>

                      {/* Power-up Quick Trigger (Fires inside gameplay canvas feedback!) */}
                      <div className="flex items-center gap-1.5 pointer-events-auto">
                        <button
                          onClick={() => {
                            // Spark Lasers
                            setActivePowerup(activePowerup === "lasers" ? null : "lasers");
                            triggerHapticSim("medium");
                            setScore(prev => prev + 50000);
                          }}
                          className={`p-2 rounded-full border flex items-center justify-center transition-all ${
                            activePowerup === "lasers"
                              ? "bg-amber-500 border-amber-400 text-black scale-110 shadow-lg animate-bounce"
                              : "bg-slate-900/90 border-slate-800 text-amber-400 hover:text-white"
                          }`}
                          title="Unleash Fire Splicer Overdrive"
                        >
                          <Flame className="h-4 w-4 fill-currentColor" />
                        </button>
                      </div>

                      {/* Right: Multiplier and Bracket indicators */}
                      <div className="flex flex-col items-end">
                        <span className="text-[9px] font-mono text-emerald-400 font-bold tracking-wider leading-none">
                          MULTIPLIER
                        </span>
                        <div className="flex items-center gap-1">
                          <span className="text-slate-500 font-bold text-xs">[</span>
                          <span
                            style={{ color: gateColor }}
                            className="text-[17px] font-black italic tracking-tighter drop-shadow-[0_0_6px_rgba(57,255,20,0.5)] font-mono"
                          >
                            ×{multiplier}
                          </span>
                          <span className="text-slate-500 font-bold text-xs">]</span>
                        </div>
                      </div>
                    </div>

                    {/* Bottom overlay / Mobile drag indicator status */}
                    <div className="relative z-10 px-3 py-1 pointer-events-none flex justify-between items-center bg-black/40 backdrop-blur-[1px] m-1 rounded-lg">
                      <span className="text-[9px] font-mono text-slate-400 flex items-center gap-1">
                        <Info className="h-3 w-3 text-cyan-400" />
                        DRAG CARDS/SCREEN TO SPLICE
                      </span>
                      <button
                        onClick={() => {
                          setScore(0);
                          setMultiplier(1);
                          triggerHapticSim("medium");
                        }}
                        className="pointer-events-auto bg-slate-950 hover:bg-slate-900 border border-slate-800 font-mono text-[8px] text-slate-300 px-2 py-0.5 rounded"
                      >
                        RESET SCORE
                      </button>
                    </div>
                  </div>
                )}

                {/* 4. ACTIVE POWER-UP SPLICING DESIGNER */}
                {screenFlow === "powerup" && (
                  <div className="w-full h-full flex flex-col justify-between p-5 select-none bg-slate-950">
                    <div className="mt-2 text-center">
                      <h2 className="text-md font-extrabold italic uppercase tracking-wider text-amber-400 flex items-center gap-1.5 justify-center">
                        <Sparkles className="h-4 w-4" /> Power-Up Builder
                      </h2>
                      <p className="text-[10px] text-slate-400">Protype gameplay multipliers triggers</p>
                    </div>

                    <div className="bg-slate-900/60 p-3 rounded-lg border border-slate-800 space-y-3 my-auto">
                      <div>
                        <label className="block text-[10px] text-slate-400 mb-1 font-bold">CONCEPT NAME</label>
                        <input
                          type="text"
                          value={powerupName}
                          onChange={(e) => setPowerupName(e.target.value)}
                          className="w-full bg-slate-950 border border-slate-800 rounded px-2.5 py-1 text-xs text-white uppercase tracking-wider font-mono focus:border-amber-500 outline-none"
                        />
                      </div>

                      <div>
                        <label className="block text-[10px] text-slate-400 mb-1 font-bold">PRIMARY EFFECT</label>
                        <textarea
                          rows={2}
                          value={powerupEffect}
                          onChange={(e) => setPowerupEffect(e.target.value)}
                          className="w-full bg-slate-950 border border-slate-800 rounded px-2.5 py-1 text-[11px] text-slate-300 leading-normal focus:border-amber-500 outline-none resize-none"
                        />
                      </div>

                      <button
                        onClick={handleGenerateAIPowerup}
                        disabled={isAiLoading}
                        className="w-full bg-amber-500 hover:bg-amber-400 text-slate-950 font-black text-xs py-2 rounded-lg uppercase tracking-wide cursor-pointer disabled:opacity-50"
                      >
                        {isAiLoading ? "TRANSPILING WORKSTATION..." : "SPLICING POWER-UP CONFIG"}
                      </button>
                    </div>

                    <div className="text-[9px] font-mono text-slate-500 text-center leading-normal">
                      Outputs real GDScript and particle parameter ranges directly.
                    </div>
                  </div>
                )}

                {/* 5. GAME OVER / SCORE SUMMARY CARD */}
                {screenFlow === "gameover" && (
                  <div className="w-full h-full flex flex-col items-center justify-between p-6 select-none bg-radial from-red-950/20 via-slate-950 to-slate-950">
                    <div className="text-center mt-2">
                      <h2 className="text-xl font-black italic text-red-500 tracking-tighter uppercase drop-shadow-[0_0_8px_rgba(239,68,68,0.4)]">
                        GRID COLLISION DETECTED
                      </h2>
                      <p className="text-[10px] text-slate-400 uppercase tracking-widest font-mono">Splicer Terminated</p>
                    </div>

                    <div className="bg-slate-900/40 border border-slate-800 rounded-xl p-4 w-full max-w-[240px] space-y-2 text-center my-auto">
                      <div>
                        <span className="text-[9px] font-mono text-slate-500 block leading-none">TOTAL SCORE ACQUIRED</span>
                        <span className="text-xl font-black text-white font-mono leading-tight">{score.toLocaleString()}</span>
                      </div>

                      <div className="grid grid-cols-2 gap-2 border-t border-slate-800/85 pt-2">
                        <div>
                          <span className="text-[8px] font-mono text-slate-500 block">MULTIPLIER MAX</span>
                          <span style={{ color: gateColor }} className="text-xs font-bold font-mono">×{multiplier}</span>
                        </div>
                        <div>
                          <span className="text-[8px] font-mono text-slate-500 block">SHAPE SPLITS</span>
                          <span className="text-xs font-bold font-mono text-cyan-400">1,482</span>
                        </div>
                      </div>
                    </div>

                    <button
                      onClick={() => {
                        setScreenFlow("gameplay");
                        setScore(0);
                        setMultiplier(1);
                        triggerHapticSim("medium");
                      }}
                      className="bg-white hover:bg-slate-200 text-slate-950 font-black text-xs py-2 w-full max-w-[180px] rounded-lg uppercase tracking-wide"
                    >
                      INITIALIZE NEW ATTEMPT
                    </button>
                  </div>
                )}

              </div>

              {/* iOS Home Indicator or Android Nav button bar */}
              {deviceOS === "ios" ? (
                <div className="absolute bottom-1 inset-x-0 flex justify-center z-20 pointer-events-none">
                  <div className="w-28 h-1 bg-white/70 rounded-full" />
                </div>
              ) : (
                <div className="absolute bottom-1 inset-x-0 h-4 px-12 z-20 flex justify-between items-center text-[11px] text-slate-500 pointer-events-none">
                  <span>◀</span>
                  <span>●</span>
                  <span>■</span>
                </div>
              )}

            </div>
          </div>

          {/* Quick Emulator status indicators */}
          <div className="w-full flex justify-between items-center bg-slate-900/30 border border-slate-800/80 p-3 rounded-lg text-xs">
            <span className="text-slate-400 font-medium">Safe Margins Protection:</span>
            <div className="flex gap-2">
              <button
                onClick={() => setSafeAreaEnabled(!safeAreaEnabled)}
                className={`px-3 py-1 rounded font-bold uppercase ${
                  safeAreaEnabled ? "bg-cyan-500/10 text-cyan-400 border border-cyan-500/30" : "bg-slate-950 text-slate-500 border border-slate-800"
                }`}
              >
                {safeAreaEnabled ? "Safe Areas [ACTIVE]" : "Safe Areas [OFF]"}
              </button>

              <button
                onClick={() => {
                  setShipPosition({ x: 150, y: 150 });
                  triggerHapticSim("light");
                }}
                className="bg-slate-950 text-slate-300 hover:text-white border border-slate-800 px-3 py-1 rounded flex items-center gap-1.5"
              >
                <RefreshCw className="h-3 w-3" /> Center Ship
              </button>
            </div>
          </div>
        </section>

        {/* RIGHT PANEL (Col 8.5-12): Godot 4 developer Workstation & AI Assistant */}
        <section className="lg:col-span-4 flex flex-col gap-6 order-3">
          
          {/* Godot 4 Tool Tab Header */}
          <div className="bg-slate-900/40 border border-slate-800/80 rounded-xl p-5 shadow-lg flex-1 flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between border-b border-slate-850 pb-3 mb-4">
                <h2 className="text-sm font-bold uppercase tracking-wider text-slate-200 flex items-center gap-2">
                  <Code2 className="h-4 w-4 text-cyan-400" /> Godot 4 workstation
                </h2>
                <div className="flex gap-1.5 bg-slate-950 p-1 rounded-lg border border-slate-800">
                  <button
                    onClick={() => { setGodotTab("shaders"); triggerHapticSim("light"); }}
                    className={`text-[10px] px-2 py-1 rounded font-bold uppercase ${
                      godotTab === "shaders" ? "bg-slate-800 text-cyan-400" : "text-slate-500"
                    }`}
                  >
                    Shaders
                  </button>
                  <button
                    onClick={() => { setGodotTab("gdscripts"); triggerHapticSim("light"); }}
                    className={`text-[10px] px-2 py-1 rounded font-bold uppercase ${
                      godotTab === "gdscripts" ? "bg-slate-800 text-cyan-400" : "text-slate-500"
                    }`}
                  >
                    GDScript
                  </button>
                  <button
                    onClick={() => { setGodotTab("mobile_optimizations"); triggerHapticSim("light"); }}
                    className={`text-[10px] px-2 py-1 rounded font-bold uppercase ${
                      godotTab === "mobile_optimizations" ? "bg-slate-800 text-cyan-400" : "text-slate-500"
                    }`}
                  >
                    Mobile Project
                  </button>
                </div>
              </div>

              {/* Godot tab view representation */}
              {godotTab === "shaders" && (
                <div className="space-y-3">
                  <div className="flex justify-between items-center">
                    <span className="text-[11px] font-mono text-slate-400">NEON_MOBILE_GLOW.GDSHADER</span>
                    <button
                      onClick={() => copyToClipboard(PRE_LOADED_SHADERS.mobileGlowShader)}
                      className="text-slate-400 hover:text-white flex items-center gap-1 text-[10px]"
                    >
                      {copiedText ? (
                        <span className="text-emerald-400 flex items-center gap-1"><Check className="h-3 w-3" /> Copied!</span>
                      ) : (
                        <span className="flex items-center gap-1"><Copy className="h-3 w-3" /> Copy</span>
                      )}
                    </button>
                  </div>
                  <pre className="bg-slate-950 p-3.5 rounded-lg border border-slate-800 text-[10px] font-mono overflow-x-auto text-slate-300 max-h-56 leading-relaxed">
                    {PRE_LOADED_SHADERS.mobileGlowShader}
                  </pre>
                  <div className="flex items-start gap-2 bg-cyan-500/5 p-3 rounded-lg border border-cyan-500/10 text-[11px] text-cyan-400 leading-normal">
                    <Info className="h-4 w-4 flex-shrink-0 mt-0.5" />
                    <span>
                      <strong>Performance Note:</strong> This shader avoids dynamic for-loops or texture blur kernels that choke mobile GPUs. Uses high-performance vector boundaries for optimal haptic rendering context.
                    </span>
                  </div>
                </div>
              )}

              {godotTab === "gdscripts" && (
                <div className="space-y-3">
                  <div className="flex justify-between items-center">
                    <span className="text-[11px] font-mono text-slate-400">HAPTIC_CONTROLLER.GD</span>
                    <button
                      onClick={() => copyToClipboard(PRE_LOADED_SHADERS.hapticScript)}
                      className="text-slate-400 hover:text-white flex items-center gap-1 text-[10px]"
                    >
                      {copiedText ? (
                        <span className="text-emerald-400 flex items-center gap-1"><Check className="h-3 w-3" /> Copied!</span>
                      ) : (
                        <span className="flex items-center gap-1"><Copy className="h-3 w-3" /> Copy</span>
                      )}
                    </button>
                  </div>
                  <pre className="bg-slate-950 p-3.5 rounded-lg border border-slate-800 text-[10px] font-mono overflow-x-auto text-slate-300 max-h-56 leading-relaxed">
                    {PRE_LOADED_SHADERS.hapticScript}
                  </pre>
                  <div className="flex items-start gap-2 bg-emerald-500/5 p-3 rounded-lg border border-emerald-500/10 text-[11px] text-emerald-400 leading-normal">
                    <Cpu className="h-4 w-4 flex-shrink-0 mt-0.5" />
                    <span>
                      <strong>Haptic Timing:</strong> Trigger <code>light_impact</code> when passing minor vector particles, and medium/heavy on gates formulas collision tags.
                    </span>
                  </div>
                </div>
              )}

              {godotTab === "mobile_optimizations" && (
                <div className="space-y-3">
                  <div className="flex justify-between items-center">
                    <span className="text-[11px] font-mono text-slate-400">PROJECT_OVERGLOW.CFG</span>
                    <button
                      onClick={() => copyToClipboard(PRE_LOADED_SHADERS.mobileOptimizations)}
                      className="text-slate-400 hover:text-white flex items-center gap-1 text-[10px]"
                    >
                      {copiedText ? (
                        <span className="text-emerald-400 flex items-center gap-1"><Check className="h-3 w-3" /> Copied!</span>
                      ) : (
                        <span className="flex items-center gap-1"><Copy className="h-3 w-3" /> Copy</span>
                      )}
                    </button>
                  </div>
                  <pre className="bg-slate-950 p-3.5 rounded-lg border border-slate-800 text-[10px] font-mono overflow-x-auto text-slate-300 max-h-56 leading-relaxed">
                    {PRE_LOADED_SHADERS.mobileOptimizations}
                  </pre>
                  <div className="flex items-start gap-2 bg-amber-500/5 p-3 rounded-lg border border-amber-500/10 text-[11px] text-amber-400 leading-normal">
                    <Smartphone className="h-4 w-4 flex-shrink-0 mt-0.5" />
                    <span>
                      <strong>OLED Settings Tip:</strong> For AMOLED battery savings, set the viewport clear color to pitch black. Avoid bloom rendering in low-power modes.
                    </span>
                  </div>
                </div>
              )}
            </div>

            {/* AI Assistant response section */}
            <div className="border-t border-slate-850 pt-4 mt-4">
              <div className="flex items-center justify-between mb-2">
                <span className="text-[10px] font-bold text-slate-400 tracking-wider font-mono">NEON CO-DESIGNER TERMINAL</span>
                {aiResponse && (
                  <button
                    onClick={() => setAiResponse(null)}
                    className="text-slate-500 hover:text-slate-300 font-bold text-[9px] uppercase tracking-tighter"
                  >
                    Clear Feed
                  </button>
                )}
              </div>

              {aiResponse ? (
                <div className="bg-slate-950 p-3.5 rounded-lg border border-slate-850 text-xs text-slate-300 leading-relaxed overflow-y-auto max-h-60 mt-2 font-mono scrollbar-thin">
                  <div className="bg-cyan-950/20 text-cyan-400 border border-cyan-500/20 p-2 rounded mb-2 flex items-center gap-1.5 text-[10px]">
                    <Sparkles className="h-3.5 w-3.5" /> Compiled Code Engine Guidelines
                  </div>
                  <div className="space-y-2 whitespace-pre-wrap">{aiResponse}</div>
                </div>
              ) : (
                <div className="text-center py-6 text-slate-500 text-xs italic">
                  Ask the Neon Co-Designer for custom shaders, touch-drag algorithms, or haptic triggers.
                </div>
              )}

              {/* Prompt Query Area */}
              <div className="mt-3 flex gap-2">
                <input
                  type="text"
                  placeholder="Ask for custom Godot 4 Swipe Controls..."
                  value={promptInput}
                  onChange={(e) => setPromptInput(e.target.value)}
                  className="flex-1 bg-slate-950 border border-slate-800 text-xs text-white rounded-lg px-3 py-2 focus:border-cyan-500 outline-none"
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleGenerateAI();
                  }}
                />
                <button
                  onClick={handleGenerateAI}
                  disabled={isAiLoading}
                  className="bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-black text-xs px-3 rounded-lg flex items-center justify-center cursor-pointer disabled:opacity-50"
                  title="Generate dynamic response"
                >
                  {isAiLoading ? <RefreshCw className="h-4 w-4 animate-spin text-slate-950" /> : <Wand2 className="h-4 w-4" fill="currentColor" />}
                </button>
              </div>
            </div>

          </div>

          {/* Quick specs section */}
          <div className="bg-slate-900/20 border border-slate-850 rounded-xl p-4 text-xs font-mono">
            <h3 className="font-bold text-slate-300 mb-2 uppercase tracking-wide flex items-center gap-1">
              <Cpu className="h-3.5 w-3.5 text-cyan-400" /> Phone Specifications Profile
            </h3>
            <ul className="space-y-1 text-slate-400 text-[11px]">
              <li className="flex justify-between">
                <span>Viewport Ratio Range:</span>
                <span className="text-white">19.5:9 to 16:9 Adaptability</span>
              </li>
              <li className="flex justify-between">
                <span>Core Target Devices:</span>
                <span className="text-white">iPhone 14/15/16 Pro, Galaxy S23/S24</span>
              </li>
              <li className="flex justify-between">
                <span>Frame Rate Target:</span>
                <span className="text-white">60 V-Sync / 120Hz ProMotion</span>
              </li>
              <li className="flex justify-between">
                <span>Graphics Backend:</span>
                <span className="text-white">OpenGL ES 3.0 Mobile compatibility</span>
              </li>
            </ul>
          </div>

        </section>

      </div>

      {/* Retro-cybernetic grid footer lines */}
      <footer className="mt-auto border-t border-slate-900 bg-slate-900/40 p-4 text-center text-xs text-slate-500">
        <div className="max-w-7xl mx-auto flex flex-col sm:flex-row justify-between items-center gap-2">
          <span>&copy; {new Date().getFullYear()} Neon Splicer Design Workstation. Built with Google Gemini & Antigravity Agent.</span>
          <div className="flex gap-4">
            <span className="text-cyan-400/80">iOS SDK v17.0+</span>
            <span className="text-emerald-400/80">Android NDK API v33+</span>
            <span className="text-purple-400/80">Godot Engine 4.2+ compatible</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
