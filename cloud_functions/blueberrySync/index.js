const tcb = require("@cloudbase/node-sdk");

const app = tcb.init({
  env: tcb.SYMBOL_DEFAULT_ENV
});

const db = app.database();
const records = db.collection("records");

const APP_SECRET = process.env.BLUEBERRY_SYNC_SECRET || "xiaolanmei-family-2026";
const FAMILY_ID = "xiaolanmei";

exports.main = async function (event) {
  try {
    const request = parseRequest(event);
    if (request.method === "GET") {
      return ok({ ok: true, message: "blueberrySync is running", action: "ping" });
    }

    if (request.secret !== APP_SECRET) {
      return fail(401, "unauthorized");
    }

    switch (request.action) {
      case "ping":
        return ok({ ok: true, message: "pong", server_time: Date.now() });
      case "pull":
        return ok({ ok: true, records: await pullRecords(Number(request.since || 0)) });
      case "upsert":
        return ok({ ok: true, record: await upsertRecord(request.record || {}) });
      case "delete":
        return ok({ ok: true, record: await deleteRecord(String(request.record_id || "")) });
      case "sync":
        return ok(await syncRecords(Array.isArray(request.records) ? request.records : [], Number(request.since || 0)));
      default:
        return fail(400, "unknown action");
    }
  } catch (error) {
    console.error(error);
    return fail(500, error.message || "server error");
  }
};

function parseRequest(event) {
  const method = String(event.httpMethod || event.method || "POST").toUpperCase();
  let body = {};
  if (typeof event.body === "string" && event.body.trim() !== "") {
    body = JSON.parse(event.body);
  } else if (event.body && typeof event.body === "object") {
    body = event.body;
  } else if (event.queryStringParameters) {
    body = event.queryStringParameters;
  }
  body.method = method;
  return body;
}

async function pullRecords(since) {
  let query = records.where({ family_id: FAMILY_ID });
  if (since > 0) {
    query = query.where({ family_id: FAMILY_ID, updated_at: db.command.gt(since) });
  }
  const result = await query.orderBy("updated_at", "asc").limit(1000).get();
  return result.data || [];
}

async function syncRecords(localRecords, since) {
  const saved = [];
  for (const localRecord of localRecords) {
    saved.push(await upsertRecord(localRecord));
  }
  return {
    ok: true,
    saved,
    records: await pullRecords(since)
  };
}

async function upsertRecord(input) {
  const now = Date.now();
  const recordId = sanitizeId(input.record_id || input.id);
  if (!recordId) {
    throw new Error("record_id is required");
  }

  const existing = await records.doc(recordId).get().catch(() => ({ data: [] }));
  const current = Array.isArray(existing.data) && existing.data.length > 0 ? existing.data[0] : null;
  const incomingUpdatedAt = Number(input.updated_at || now);
  if (current && Number(current.updated_at || 0) > incomingUpdatedAt) {
    return current;
  }

  const record = {
    record_id: recordId,
    family_id: FAMILY_ID,
    kind: String(input.kind || ""),
    date: String(input.date || ""),
    data: input.data && typeof input.data === "object" ? input.data : {},
    deleted: Boolean(input.deleted),
    created_at: Number(input.created_at || (current && current.created_at) || now),
    updated_at: Math.max(incomingUpdatedAt, now),
    updated_by: String(input.updated_by || "app")
  };

  await records.doc(recordId).set(record);
  return record;
}

async function deleteRecord(recordIdRaw) {
  const recordId = sanitizeId(recordIdRaw);
  if (!recordId) {
    throw new Error("record_id is required");
  }
  const existing = await records.doc(recordId).get().catch(() => ({ data: [] }));
  const current = Array.isArray(existing.data) && existing.data.length > 0 ? existing.data[0] : {};
  const record = {
    ...current,
    record_id: recordId,
    family_id: FAMILY_ID,
    deleted: true,
    updated_at: Date.now(),
    updated_by: "app"
  };
  await records.doc(recordId).set(record);
  return record;
}

function sanitizeId(value) {
  return String(value || "").replace(/[^a-zA-Z0-9_.:-]/g, "_").slice(0, 120);
}

function ok(payload) {
  return {
    statusCode: 200,
    headers: jsonHeaders(),
    body: JSON.stringify(payload)
  };
}

function fail(statusCode, message) {
  return {
    statusCode,
    headers: jsonHeaders(),
    body: JSON.stringify({ ok: false, error: message })
  };
}

function jsonHeaders() {
  return {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
  };
}
