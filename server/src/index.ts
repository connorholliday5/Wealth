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
