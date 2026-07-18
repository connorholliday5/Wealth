import Database from "better-sqlite3";
import crypto from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const keyHex = process.env.TOKEN_ENCRYPTION_KEY;
if (!keyHex || keyHex.length !== 64) {
  throw new Error("TOKEN_ENCRYPTION_KEY must be a 64-character hex string (openssl rand -hex 32)");
}
const key = Buffer.from(keyHex, "hex");

// Anchor the DB next to the server code, NOT the process working directory —
// otherwise starting the server from a different folder silently creates a
// fresh empty DB and every linked bank appears to vanish.
const serverRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const db = new Database(process.env.TOKENS_DB_PATH ?? path.join(serverRoot, "tokens.sqlite"));
db.exec(`
  CREATE TABLE IF NOT EXISTS items (
    item_id TEXT PRIMARY KEY,
    institution_name TEXT,
    encrypted_token TEXT NOT NULL,
    iv TEXT NOT NULL,
    auth_tag TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

function encrypt(plainText: string): { encrypted: string; iv: string; authTag: string } {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(plainText, "utf8"), cipher.final()]);
  return {
    encrypted: encrypted.toString("hex"),
    iv: iv.toString("hex"),
    authTag: cipher.getAuthTag().toString("hex"),
  };
}

function decrypt(encryptedHex: string, ivHex: string, authTagHex: string): string {
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(ivHex, "hex"));
  decipher.setAuthTag(Buffer.from(authTagHex, "hex"));
  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedHex, "hex")),
    decipher.final(),
  ]);
  return decrypted.toString("utf8");
}

export function saveItem(itemId: string, accessToken: string, institutionName: string | null) {
  const { encrypted, iv, authTag } = encrypt(accessToken);
  db.prepare(
    `INSERT INTO items (item_id, institution_name, encrypted_token, iv, auth_tag)
     VALUES (@itemId, @institutionName, @encrypted, @iv, @authTag)
     ON CONFLICT(item_id) DO UPDATE SET
       institution_name = @institutionName,
       encrypted_token = @encrypted,
       iv = @iv,
       auth_tag = @authTag`
  ).run({ itemId, institutionName, encrypted, iv, authTag });
}

export function getAccessToken(itemId: string): string | undefined {
  const row = db
    .prepare(`SELECT encrypted_token, iv, auth_tag FROM items WHERE item_id = ?`)
    .get(itemId) as { encrypted_token: string; iv: string; auth_tag: string } | undefined;
  if (!row) return undefined;
  return decrypt(row.encrypted_token, row.iv, row.auth_tag);
}

export function listItems(): Array<{ itemId: string; institutionName: string | null }> {
  const rows = db
    .prepare(`SELECT item_id as itemId, institution_name as institutionName FROM items`)
    .all() as Array<{ itemId: string; institutionName: string | null }>;
  return rows;
}

export function deleteItem(itemId: string) {
  db.prepare(`DELETE FROM items WHERE item_id = ?`).run(itemId);
}

db.exec(`
  CREATE TABLE IF NOT EXISTS sync_cursors (
    item_id TEXT PRIMARY KEY,
    cursor TEXT
  )
`);

export function getCursor(itemId: string): string | undefined {
  const row = db.prepare(`SELECT cursor FROM sync_cursors WHERE item_id = ?`).get(itemId) as
    | { cursor: string }
    | undefined;
  return row?.cursor;
}

export function setCursor(itemId: string, cursor: string) {
  db.prepare(
    `INSERT INTO sync_cursors (item_id, cursor) VALUES (?, ?)
     ON CONFLICT(item_id) DO UPDATE SET cursor = excluded.cursor`
  ).run(itemId, cursor);
}

export function clearCursor(itemId: string) {
  db.prepare(`DELETE FROM sync_cursors WHERE item_id = ?`).run(itemId);
}
