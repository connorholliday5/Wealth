import { Router } from "express";
import { plaidClient } from "../plaidClient.js";
import { getAccessToken } from "../db.js";
import { handlePlaidError } from "./link.js";

export const liabilitiesRouter = Router();

// Credit card APR/statement data and student/mortgage loan terms (rate, payment, due date).
liabilitiesRouter.get("/", async (req, res) => {
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
    const resp = await plaidClient.liabilitiesGet({ access_token: accessToken });
    res.json(resp.data.liabilities);
  } catch (err) {
    handlePlaidError(res, err);
  }
});
