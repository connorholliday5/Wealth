import { Router } from "express";
import { plaidClient } from "../plaidClient.js";
import { getAccessToken, listItems } from "../db.js";
import { handlePlaidError } from "./link.js";

export const accountsRouter = Router();

// Returns balances/accounts for every linked item, tagged with institution name.
// Items are isolated: one bank erroring (e.g. needs re-login) must not take
// down balances for every other bank in the same response.
accountsRouter.get("/", async (_req, res) => {
  const items = listItems();
  const settled = await Promise.allSettled(
    items.map(async (item) => {
      const accessToken = getAccessToken(item.itemId);
      if (!accessToken) throw new Error("missing token");
      const resp = await plaidClient.accountsBalanceGet({ access_token: accessToken });
      return {
        itemId: item.itemId,
        institutionName: item.institutionName,
        accounts: resp.data.accounts,
      };
    })
  );

  const ok = settled.flatMap((result) => (result.status === "fulfilled" ? [result.value] : []));
  const failed = settled
    .map((result, index) => ({ result, item: items[index] }))
    .filter(({ result }) => result.status === "rejected")
    .map(({ result, item }) => {
      const reason = (result as PromiseRejectedResult).reason as {
        response?: { data?: { error_code?: string } };
      };
      console.error(`accountsBalanceGet failed for ${item.itemId}:`, reason?.response?.data ?? reason);
      return {
        itemId: item.itemId,
        institutionName: item.institutionName,
        code: reason?.response?.data?.error_code ?? "UNKNOWN",
      };
    });

  res.json({ items: ok, failures: failed });
});
