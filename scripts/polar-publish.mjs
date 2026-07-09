#!/usr/bin/env node
// Publish a built .dmg to the Polar "File Downloads" benefit.
//
// Strategy: ADD NEW + DISABLE OLD.
//   - Upload the new dmg via the Files API (create -> S3 multipart PUT -> uploaded).
//   - Append its id to the benefit's `files`, and set `archived[oldId] = true`
//     for every file that was there before. Archived files stay downloadable for
//     customers who already bought (Polar keeps legacy access); only new buyers
//     get the fresh dmg. Nothing is deleted.
//
// Run standalone:
//   POLAR_ACCESS_TOKEN=polar_oat_... POLAR_BENEFIT_ID=<uuid> \
//     node scripts/polar-publish.mjs build/release/agent-caffeine-0.2.3-13.dmg
//
// release.sh calls this automatically as the last step when both env vars are set.
//
// Env:
//   POLAR_ACCESS_TOKEN     required. Org access token with `files:write` + benefits scopes.
//   POLAR_BENEFIT_ID       required. The "File Downloads" benefit uuid (see below).
//   POLAR_ORGANIZATION_ID  optional. Only needed if the token is not org-scoped.
//   POLAR_API_BASE         optional. Defaults to https://api.polar.sh
//                          (use https://sandbox-api.polar.sh for the sandbox).
//
// Find the benefit id once: with the token set,
//   curl -s https://api.polar.sh/v1/benefits/?type=downloadables \
//     -H "Authorization: Bearer $POLAR_ACCESS_TOKEN" | python3 -m json.tool
// and copy the `id` of the caffeinagent File Downloads benefit.

import { readFileSync } from "node:fs";
import { basename } from "node:path";
import { createHash } from "node:crypto";

const API = process.env.POLAR_API_BASE ?? "https://api.polar.sh";
const TOKEN = process.env.POLAR_ACCESS_TOKEN;
const BENEFIT_ID = process.env.POLAR_BENEFIT_ID;
const ORG_ID = process.env.POLAR_ORGANIZATION_ID; // optional
const DMG_PATH = process.argv[2];

// S3 multipart requires every part except the last to be >= 5 MiB. 100 MiB keeps
// part counts tiny; anything under this (every caffeinagent dmg so far) is 1 part.
const CHUNK = 100 * 1024 * 1024;
const MIME = "application/x-apple-diskimage";

function die(msg) {
  console.error(`polar-publish: ${msg}`);
  process.exit(1);
}

if (!TOKEN) die("POLAR_ACCESS_TOKEN is not set");
if (!BENEFIT_ID) die("POLAR_BENEFIT_ID is not set");
if (!DMG_PATH) die("usage: node scripts/polar-publish.mjs <path-to-dmg>");

const sha256b64 = (buf) => createHash("sha256").update(buf).digest("base64");

async function api(method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    die(`${method} ${path} -> ${res.status}\n${text}`);
  }
  return text ? JSON.parse(text) : {};
}

async function main() {
  const bytes = readFileSync(DMG_PATH);
  const name = basename(DMG_PATH);
  const size = bytes.length;

  // Split into parts and checksum each chunk (plus the whole file).
  const parts = [];
  for (let start = 0, number = 1; start < size; start += CHUNK, number++) {
    const end = Math.min(start + CHUNK, size);
    parts.push({
      number,
      chunk_start: start,
      chunk_end: end,
      checksum_sha256_base64: sha256b64(bytes.subarray(start, end)),
    });
  }
  console.log(`polar-publish: ${name} (${size} bytes, ${parts.length} part(s))`);

  // 1. Create the file record -> Polar returns presigned S3 upload targets.
  const created = await api("POST", "/v1/files/", {
    ...(ORG_ID ? { organization_id: ORG_ID } : {}),
    name,
    mime_type: MIME,
    size,
    checksum_sha256_base64: sha256b64(bytes),
    service: "downloadable",
    upload: { parts },
  });
  console.log(`polar-publish: created file ${created.id}`);

  // 2. PUT each chunk to its presigned URL, capturing the S3 ETag per part.
  const uploadedParts = [];
  for (const part of created.upload.parts) {
    const src = parts.find((p) => p.number === part.number);
    const put = await fetch(part.url, {
      method: "PUT",
      headers: part.headers ?? {}, // presigned headers must be sent verbatim
      body: bytes.subarray(src.chunk_start, src.chunk_end),
    });
    if (!put.ok) die(`part ${part.number} PUT -> ${put.status}\n${await put.text()}`);
    uploadedParts.push({
      number: part.number,
      checksum_etag: put.headers.get("etag"),
      checksum_sha256_base64: src.checksum_sha256_base64,
    });
    console.log(`polar-publish: uploaded part ${part.number}/${created.upload.parts.length}`);
  }

  // 3. Tell Polar the upload is done (server completes the S3 multipart upload).
  await api("POST", `/v1/files/${created.id}/uploaded`, {
    id: created.upload.id,
    path: created.upload.path,
    parts: uploadedParts,
  });
  console.log("polar-publish: upload finalized");

  // 4. Read the benefit, then add-new + archive-old.
  const benefit = await api("GET", `/v1/benefits/${BENEFIT_ID}`);
  if (benefit.type !== "downloadables") {
    die(`benefit ${BENEFIT_ID} is type "${benefit.type}", expected "downloadables"`);
  }
  const existing = benefit.properties?.files ?? [];
  const archived = { ...(benefit.properties?.archived ?? {}) };
  for (const id of existing) archived[id] = true; // disable every prior file
  archived[created.id] = false; // keep the new one active

  await api("PATCH", `/v1/benefits/${BENEFIT_ID}`, {
    type: "downloadables",
    properties: {
      files: [...existing, created.id],
      archived,
    },
  });

  console.log(
    `polar-publish: done. benefit ${BENEFIT_ID} now serves ${name} ` +
      `(${existing.length} older file(s) archived, legacy buyers keep access).`
  );
}

main().catch((e) => die(e?.stack || String(e)));
