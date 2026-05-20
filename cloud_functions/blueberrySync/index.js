const tcb = require("@cloudbase/node-sdk");

const app = tcb.init({
  env: tcb.SYMBOL_DEFAULT_ENV
});

const db = app.database();
const records = db.collection("records");

const APP_SECRET = process.env.BLUEBERRY_SYNC_SECRET || "xiaolanmei-family-2026";
const FAMILY_ID = "xiaolanmei";
const PAGE_SIZE = 100;

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
        return ok(await pullRecords(Number(request.since || 0), String(request.cursor || "")));
      case "upsert":
        return ok({ ok: true, record: await addRecordIfMissing(request.record || {}) });
      case "delete":
        return ok({ ok: true, skipped: true, message: "cloud delete is disabled" });
      case "sync":
        return ok(await syncRecords(Array.isArray(request.records) ? request.records : [], Number(request.since || 0), String(request.cursor || "")));
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

async function pullRecords(since, cursor) {
  let query = records.where({ family_id: FAMILY_ID });
  if (since > 0) {
    query = query.where({ family_id: FAMILY_ID, updated_at: db.command.gt(since) });
  }
  if (cursor) {
    query = query.where({ family_id: FAMILY_ID, updated_at: db.command.gt(Number(cursor)) });
  }
  const result = await query.orderBy("updated_at", "asc").limit(PAGE_SIZE).get();
  const data = result.data || [];
  const last = data.length > 0 ? data[data.length - 1] : null;
  return {
    ok: true,
    records: data,
    next_cursor: data.length >= PAGE_SIZE && last ? String(last.updated_at || "") : "",
    has_more: data.length >= PAGE_SIZE
  };
}

async function syncRecords(localRecords, since, cursor) {
  const saved = [];
  for (const localRecord of localRecords) {
    const result = await addRecordIfMissing(localRecord);
    if (result && result.created) {
      saved.push(result.record);
    }
  }
  const pulled = await pullRecords(since, cursor);
  return { ...pulled, saved };
}

async function addRecordIfMissing(input) {
  const now = Date.now();
  const recordId = sanitizeId(input.record_id || input.id);
  if (!recordId) {
    throw new Error("record_id is required");
  }

  const existing = await records.doc(recordId).get().catch(() => ({ data: [] }));
  const current = Array.isArray(existing.data) && existing.data.length > 0 ? existing.data[0] : null;
  if (current) {
    return { created: false, record: current };
  }

  const record = {
    record_id: recordId,
    family_id: FAMILY_ID,
    kind: String(input.kind || ""),
    date: String(input.date || ""),
    data: input.data && typeof input.data === "object" ? input.data : {},
    deleted: false,
    created_at: Number(input.created_at || now),
    updated_at: Number(input.updated_at || now),
    updated_by: String(input.updated_by || "app")
  };

  await records.doc(recordId).set(record);
  return { created: true, record };
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
