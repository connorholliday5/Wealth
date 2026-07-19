import { Router } from "express";
import { CountryCode, Products } from "plaid";
import { plaidClient } from "../plaidClient.js";
import { saveItem, deleteItem, getAccessToken, clearCursor } from "../db.js";

export const linkRouter = Router();

// Step 1: app asks for a link_token to open Plaid Link.
linkRouter.post("/token/create", async (req, res) => {
  try {
    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: "wealth-app-single-user" },
      client_name: "Wealth",
      // Only Transactions is REQUIRED — listing Liabilities/Investments as
      // required products would hide every bank that doesn't support them
      // from Plaid Link entirely. Optional products attach when available.
      products: [Products.Transactions],
      optional_products: [Products.Liabilities, Products.Investments],
      country_codes: [CountryCode.Us],
      language: "en",
    });
    res.json({ linkToken: response.data.link_token });
  } catch (err) {
    handlePlaidError(res, err);
  }
});

// Re-auth (update mode): when a bank breaks the connection (password change,
// MFA — Plaid surfaces ITEM_LOGIN_REQUIRED), the app reopens Plaid Link with an
// update-mode link token. Passing the item's existing access_token and OMITTING
// the products array is what puts Link into update mode (repair, not add).
linkRouter.post("/token/update", async (req, res) => {
  const { itemId } = req.body as { itemId?: string };
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
    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: "wealth-app-single-user" },
      client_name: "Wealth",
      country_codes: [CountryCode.Us],
      language: "en",
      access_token: accessToken,
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

// Disconnects an institution completely: revokes the item at Plaid (stops
// Plaid billing and data access), then removes the stored token and cursor.
linkRouter.delete("/item/:itemId", async (req, res) => {
  const itemId = req.params.itemId;
  const accessToken = getAccessToken(itemId);
  if (accessToken) {
    try {
      await plaidClient.itemRemove({ access_token: accessToken });
    } catch (err) {
      // Log but continue — the item may already be revoked at Plaid's end,
      // and local cleanup should happen regardless.
      logPlaidError("itemRemove", err);
    }
  }
  deleteItem(itemId);
  clearCursor(itemId);
  res.status(204).send();
});

function logPlaidError(context: string, err: unknown) {
  const anyErr = err as { response?: { data?: unknown }; message?: string };
  console.error(`Plaid error (${context}):`, anyErr.response?.data ?? anyErr.message ?? err);
}

export function handlePlaidError(res: import("express").Response, err: unknown) {
  logPlaidError("request", err);
  const anyErr = err as { response?: { data?: { error_code?: string } } };
  // Upstream detail stays in the server log; clients get only the error code
  // (needed to detect ITEM_LOGIN_REQUIRED), never Plaid's full payload.
  res.status(502).json({
    error: "Plaid request failed",
    code: anyErr.response?.data?.error_code ?? null,
  });
}
