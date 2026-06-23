import express, { Request, Response } from "express";
import path from "path";
import { createServer as createViteServer } from "vite";
import { GoogleGenAI } from "@google/genai";
import dotenv from "dotenv";

dotenv.config();

const app = express();
const PORT = 3000;

app.use(express.json({ limit: "5mb" }));

// Shared Gemini client initializer (Lazy loaded to avoid server crash if key is missing)
let aiClient: GoogleGenAI | null = null;
function getGeminiClient(): GoogleGenAI {
  if (!aiClient) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      throw new Error("GEMINI_API_KEY environment variable is required");
    }
    aiClient = new GoogleGenAI({
      apiKey,
      httpOptions: {
        headers: {
          "User-Agent": "aistudio-build",
        },
      },
    });
  }
  return aiClient;
}

// 1. API: Design evaluation & Godot Code Generation using Gemini
app.post("/api/brainstorm", async (req: Request, res: Response): Promise<void> => {
  try {
    const { 
      themeColors, 
      activeScreen, 
      refinedScope, 
      selectedShape, 
      customPrompt,
      powerupConcept,
      physicsVars 
    } = req.body;

    const client = getGeminiClient();

    const systemPrompt = `You are an expert game designer, mobile UX consultant, and Godot 4 Shader/GDScript developer.
You are helping refine the game "Neon Splicer" (working title: "Neon Splicer"), a gate runner style game where players destroy vector shapes in a neon grids environment (homage to Geometry Wars, but designed for mobile).
The player ship is a sleek cyan light-form vector arrow. The bullet stream is a warm gold swarm. The screen flows include Main Menu, Ship Customizer, HUD visualizers, Game Over, and a newly proposed Power-Up Splicing designer.

Help the developer refine their vision, visual aesthetics, Godot shaders, and GDScript files based on their interactive input.
Keep explanations structured, highly legible (using markdown), professional, and technical, giving them exact, ready-to-use Godot code.`;

    let userPrompt = "";

    if (refinedScope === "powerup") {
      userPrompt = `Brainstorm a new responsive mobile power-up for Neon Splicer.
Concept name is: "${powerupConcept?.name || "Grid Overdrive"}"
Primary effect description: "${powerupConcept?.effect || "Unleashes a hyper-speed slicing laser that multiplies score multipliers for 5 seconds."}"
Ship color accent: ${themeColors?.shipColor || "#00ffff"}
Bullet stream color: ${themeColors?.bulletColor || "#ffaa00"}

Based on this, please provide:
1. DESIGN CONCEPT & FEEDBACK: How it visually fits the mobile gate runner splicing flow of multiplier gates ([+12], [x2], [÷2]).
2. DYNAMIC SHADER OR PARTICLE PARAMETERS (GODOT 4): Code or shader settings for Godot 4 GPUTarticles2D or a fragment shader for the neon power-up aura. Keep code complete and ready to paste!
3. GDSCRIPT COMPONENT: A clean, modular GDScript for Godot 4 to manage the power-up trigger, duration timer, and signal dispatch when splicing through gates. Use modern Godot 4 annotations and syntax (e.g. '@onready', class_name SplicerPowerUp).`;
    } else if (refinedScope === "shape_shader") {
      userPrompt = `Generate a dedicated Godot 4 canvas_item Shader for the high-end Neon shape: "${selectedShape?.name || "Looming Rhombus"}".
Properties chosen in Laboratory:
- Rotation speed scale: ${selectedShape?.rotateSpeed || "1.0"}
- Custom neon bloom overlay scale: ${selectedShape?.bloomScale || "2.0"}
- Vector glow accent color: ${selectedShape?.color || "#ff0055"}
- Speed distortion factor: ${selectedShape?.distortion || "0.4"}

Please provide:
1. SHADER DESCRIPTION: Explain technical optimization methods for mobile devices (e.g., avoiding real-time loop counts, using distance fields or simple edge calculations with cheap mathematical glow).
2. GODOT 4 SHADER CODE: Write a ready-to-use complete Godot 4 shader (.gdshader) with uniforms for the selected accent color, rotation, speed, and glow intensity.
3. GODOT WORLD_ENVIRONMENT RECOMMENDATION: The specific settings for HDR/Bloom in Godot 4 (Glow properties like Intensity, Strength, Blend Mode) to achieve premium Geometry Wars style vector glows on mobile without battery-drain.`;
    } else {
      userPrompt = `General Refinement & Godot Architecture Question:
Current user settings:
- Ship Accent: ${themeColors?.shipColor || "#00ffff"} (Glow: ${themeColors?.shipGlow || "cyan"})
- Enemy Accent: ${themeColors?.enemyColor || "#ff0055"} (Glow: ${themeColors?.enemyGlow || "rose"})
- Bullet Stream Color: ${themeColors?.bulletColor || "#ffea00"}
- Grid Glow Color: ${themeColors?.gridColor || "#0048ff"}
- Active Screen flow examined: "${activeScreen || "Main Menu"}"
- Custom user inquiry: "${customPrompt || "How can I implement standard mobile swipe/drag mechanics to control the ship's position and perform 'splicing' on gates at 60 FPS in Godot v4?"}"

Provide a comprehensive, high-quality, professional game design and Godot technical analysis based on these exact constraints. Provide full copy-pasteable GDScript or Shader solutions.`;
    }

    const response = await client.models.generateContent({
      model: "gemini-3.5-flash",
      contents: userPrompt,
      config: {
        systemInstruction: systemPrompt,
        temperature: 0.7,
      },
    });

    res.json({
      success: true,
      analysis: response.text,
    });
  } catch (error: any) {
    console.error("Gemini Brainstorm Error:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Failed to conduct AI design review.",
    });
  }
});

// Start server initialization & Vite mount
async function startServer() {
  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), "dist");
    app.use(express.static(distPath));
    app.get("*", (req: Request, res: Response) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Neon Splicer backend active on port ${PORT}`);
  });
}

startServer();
