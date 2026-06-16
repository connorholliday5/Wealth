import { Router } from "express";
import { plaidClient } from "../plaidClient.js";
import { getAccessToken } from "../db.js";
import { handlePlaidError } from "./link.js";

export const investmentsRouter = Router();

// Holdings for investment accounts, including Roth IRAs.
investmentsRouter.get("/holdings", async (req, res) => {
  const itemId = req.query.itemId as string | undefined;
  if (!itemId) {
    res.status(400).json({ error: "itemId is required" });
    return;
  }
  const accessToken = getAccessToken(itemId);
  if (!accessToken) {
    res.status(404).json({ error: "Unknown itemId" });
    return;
  }
  try {
    const resp = await plaidClient.investmentsHoldingsGet({ access_token: accessToken });
    res.json({
      accounts: resp.data.accounts,
      holdings: resp.data.holdings,
      securities: resp.data.securities,
    });
  } catch (err) {
    handlePlaidError(res, err);
  }
});
