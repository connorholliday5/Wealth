import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Storage is a single JSON file holding AES-256-GCM-encrypted Plaid tokens and
// per-item sync cursors. This deliberately avoids a native database module
// (better-sqlite3) so the server needs zero compilation and runs on any Node
// version — a single-user proxy stores only a handful of tokens, so a file is
// plenty. The encryption is unchanged from the previous SQLite version.

const keyHex = process.env.TOKEN_ENCRYPTION_KEY;
if (!keyHex || keyHex.length !== 64) {
  throw new Error("TOKEN_ENCRYPTION_KEY must be a 64-character hex string (openssl rand -hex 32)");
}
const key = Buffer.from(keyHex, "hex");

// Anchor the file next to the server code, NOT the process working directory —
// otherwise starting the server from a different folder silently reads a fresh
// empty store and every linked bank appears to vanish.
const serverRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const storePath = process.env.TOKENS_DB_PATH ?? path.join(serverRoot, "tokens.json");

interface StoredItem {
  institutionName: string | null;
  encrypted: string;
  iv: string;
  authTag: string;
  createdAt: string;
}

interface Store {
  items: Record<string, StoredItem>;
  cursors: Record<string, string>;
}

function loadStore(): Store {
  try {
    const raw = fs.readFileSync(storePath, "utf8");
    const parsed = JSON.parse(raw) as Partial<Store>;
    return { items: parsed.items ?? {}, cursors: parsed.cursors ?? {} };
  } catch {
    // Missing or unreadable file => start empty.
    return { items: {}, cursors: {} };
  }
}

const store: Store = loadStore();

function persist() {
  // Atomic write: write to a temp file, then rename over the target so a crash
  // mid-write can't corrupt the store.
  const tmp = `${storePath}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, storePath);
}

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
  store.items[itemId] = {
    institutionName,
    encrypted,
    iv,
    authTag,
    createdAt: store.items[itemId]?.createdAt ?? new Date().toISOString(),
  };
  persist();
}

export function getAccessToken(itemId: string): string | undefined {
  const item = store.items[itemId];
  if (!item) return undefined;
  return decrypt(item.encrypted, item.iv, item.authTag);
}

export function listItems(): Array<{ itemId: string; institutionName: string | null }> {
  return Object.entries(store.items).map(([itemId, item]) => ({
    itemId,
    institutionName: item.institutionName,
  }));
}

export function deleteItem(itemId: string) {
  delete store.items[itemId];
  persist();
}

export function getCursor(itemId: string): string | undefined {
  return store.cursors[itemId];
}

export function setCursor(itemId: string, cursor: string) {
  store.cursors[itemId] = cursor;
  persist();
}

export function clearCursor(itemId: string) {
  delete store.cursors[itemId];
  persist();
}
