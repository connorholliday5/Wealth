import { Router } from "express";
import { plaidClient } from "../plaidClient.js";
import { getAccessToken, getCursor, setCursor } from "../db.js";
import { handlePlaidError } from "./link.js";

export const transactionsRouter = Router();

// Incremental sync: the app passes back nothing, the server remembers the cursor
// per item and only returns what changed since the last call.
transactionsRouter.get("/sync", async (req, res) => {
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
    let cursor = getCursor(itemId);
    let added: unknown[] = [];
    let modified: unknown[] = [];
    let removed: unknown[] = [];
    let hasMore = true;

    while (hasMore) {
      const resp = await plaidClient.transactionsSync({
        access_token: accessToken,
        cursor,
      });
      added = added.concat(resp.data.added);
      modified = modified.concat(resp.data.modified);
      removed = removed.concat(resp.data.removed);
      hasMore = resp.data.has_more;
      cursor = resp.data.next_cursor;
    }

    if (cursor) setCursor(itemId, cursor);
    res.json({ added, modified, removed });
  } catch (err) {
    handlePlaidError(res, err);
  }
});
