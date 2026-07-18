import "dotenv/config";
import express from "express";
import cors from "cors";
import { linkRouter } from "./routes/link.js";
import { accountsRouter } from "./routes/accounts.js";
import { transactionsRouter } from "./routes/transactions.js";
import { liabilitiesRouter } from "./routes/liabilities.js";
import { investmentsRouter } from "./routes/investments.js";
import { advisorRouter } from "./routes/advisor.js";

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => res.json({ ok: true }));

// When APP_SHARED_SECRET is set, every /api route requires the same value in the
// x-wealth-key header (the iOS app sends it from Settings > Server). Without the
// env var the API stays open — fine for localhost development, not for a deployed
// server. /health stays public for uptime checks.
// Simple fixed-window rate limit (in-memory, per client IP): 120 requests/min
// for the API overall and 10/min for the credit-spending advisor route. A
// personal server doesn't need more, and this bounds the damage if the address
// leaks or the shared secret is misconfigured.
function rateLimit(maxPerMinute: number) {
  const hits = new Map<string, { count: number; windowStart: number }>();
  return (req: import("express").Request, res: import("express").Response, next: import("express").NextFunction) => {
    const now = Date.now();
    const ip = req.ip ?? "unknown";
    const entry = hits.get(ip);
    if (!entry || now - entry.windowStart > 60_000) {
      hits.set(ip, { count: 1, windowStart: now });
      if (hits.size > 10_000) hits.clear(); // bound memory
      next();
      return;
    }
    entry.count += 1;
    if (entry.count > maxPerMinute) {
      res.status(429).json({ error: "Too many requests — slow down." });
      return;
    }
    next();
  };
}
app.use("/api", rateLimit(120));
app.use("/api/advisor", rateLimit(10));

const sharedSecret = process.env.APP_SHARED_SECRET;
if (sharedSecret) {
  app.use("/api", (req, res, next) => {
    if (req.header("x-wealth-key") === sharedSecret) {
      next();
      return;
    }
    res.status(401).json({ error: "Unauthorized: missing or wrong x-wealth-key header" });
  });
} else {
  console.warn("APP_SHARED_SECRET is not set — the API is unauthenticated. Set it before deploying.");
}
app.use("/api/link", linkRouter);
app.use("/api/accounts", accountsRouter);
app.use("/api/transactions", transactionsRouter);
app.use("/api/liabilities", liabilitiesRouter);
app.use("/api/investments", investmentsRouter);
app.use("/api/advisor", advisorRouter);

const port = Number(process.env.PORT ?? 8787);
app.listen(port, () => {
  console.log(`Wealth Plaid proxy listening on http://localhost:${port}`);
});
