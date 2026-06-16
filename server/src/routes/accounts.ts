import { Router } from "express";
import { plaidClient } from "../plaidClient.js";
import { getAccessToken, listItems } from "../db.js";
import { handlePlaidError } from "./link.js";

export const accountsRouter = Router();

// Returns balances/accounts for every linked item, tagged with institution name.
accountsRouter.get("/", async (_req, res) => {
  try {
    const items = listItems();
    const results = await Promise.all(
      items.map(async (item) => {
        const accessToken = getAccessToken(item.itemId);
        if (!accessToken) return null;
        const resp = await plaidClient.accountsBalanceGet({ access_token: accessToken });
        return {
          itemId: item.itemId,
          institutionName: item.institutionName,
          accounts: resp.data.accounts,
        };
      })
    );
    res.json({ items: results.filter(Boolean) });
  } catch (err) {
    handlePlaidError(res, err);
  }
});
