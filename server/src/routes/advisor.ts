import { Router } from "express";
import Anthropic from "@anthropic-ai/sdk";

export const advisorRouter = Router();

// The Anthropic client reads ANTHROPIC_API_KEY from the environment. If the key
// isn't set, the cloud advisor is simply disabled (the endpoint reports it as
// unavailable) — the rest of the server keeps working. The key never leaves the
// server; the app only ever sees the model's reply text.
const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;

// The cloud advisor is dormant by default (no API key = disabled) — the app's
// deterministic rules engine is the primary advisor. If you ever do enable
// this, the default model is the cheapest one; override via ADVISOR_MODEL.
const MODEL = process.env.ADVISOR_MODEL ?? "claude-haiku-4-5";

advisorRouter.get("/available", (_req, res) => {
  res.json({ available: client !== null });
});

interface ChatBody {
  system?: string;
  messages?: Array<{ role: "user" | "advisor"; content: string }>;
}

advisorRouter.post("/chat", async (req, res) => {
  if (!client) {
    res.status(503).json({
      error: "Cloud advisor isn't configured. Set ANTHROPIC_API_KEY on the Wealth server.",
    });
    return;
  }

  const { system, messages } = req.body as ChatBody;
  if (!messages || messages.length === 0) {
    res.status(400).json({ error: "messages is required" });
    return;
  }

  try {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 1024,
      system,
      // The transcript alternates starting from the user; map our "advisor"
      // role to the API's "assistant".
      messages: messages.map((m) => ({
        role: m.role === "advisor" ? ("assistant" as const) : ("user" as const),
        content: m.content,
      })),
    });

    const reply = response.content
      .filter((block): block is Anthropic.TextBlock => block.type === "text")
      .map((block) => block.text)
      .join("\n");

    res.json({ reply });
  } catch (err) {
    const anyErr = err as { message?: string };
    console.error("Anthropic error:", anyErr.message ?? err);
    res.status(502).json({ error: "Advisor request failed. Check the server logs." });
  }
});
