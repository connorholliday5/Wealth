import { Router } from "express";
import { CountryCode, Products } from "plaid";
import { plaidClient } from "../plaidClient.js";
import { saveItem, deleteItem } from "../db.js";

export const linkRouter = Router();

// Step 1: app asks for a link_token to open Plaid Link.
linkRouter.post("/token/create", async (req, res) => {
  try {
    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: "wealth-app-single-user" },
      client_name: "Wealth",
      products: [Products.Transactions, Products.Liabilities, Products.Investments],
      country_codes: [CountryCode.Us],
      language: "en",
    });
    res.json({ linkToken: response.data.link_token });
  } catch (err) {
    handlePlaidError(res, err);
  }
});

// Step 2: app exchanges the public_token returned by Plaid Link for an access_token,
// which never leaves this server.
linkRouter.post("/token/exchange", async (req, res) => {
  const { publicToken } = req.body as { publicToken?: string };
  if (!publicToken) {
    res.status(400).json({ error: "publicToken is required" });
    return;
  }
  try {
    const exchange = await plaidClient.itemPublicTokenExchange({ public_token: publicToken });
    const { access_token: accessToken, item_id: itemId } = exchange.data;

    let institutionName: string | null = null;
    try {
      const itemResp = await plaidClient.itemGet({ access_token: accessToken });
      const institutionId = itemResp.data.item.institution_id;
      if (institutionId) {
        const instResp = await plaidClient.institutionsGetById({
          institution_id: institutionId,
          country_codes: [CountryCode.Us],
        });
        institutionName = instResp.data.institution.name;
      }
    } catch {
      // Institution lookup is best-effort; missing name shouldn't block linking.
    }

    saveItem(itemId, accessToken, institutionName);
    res.json({ itemId, institutionName });
  } catch (err) {
    handlePlaidError(res, err);
  }
});

linkRouter.delete("/item/:itemId", (req, res) => {
  deleteItem(req.params.itemId);
  res.status(204).send();
});

export function handlePlaidError(res: import("express").Response, err: unknown) {
  const anyErr = err as { response?: { data?: unknown }; message?: string };
  console.error("Plaid error:", anyErr.response?.data ?? anyErr.message ?? err);
  res.status(502).json({ error: "Plaid request failed", detail: anyErr.response?.data });
}
