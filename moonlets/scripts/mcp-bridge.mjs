#!/usr/bin/env node
/**
 * Stdio ↔ HTTP MCP bridge.
 *
 * Claude Code launches this script and pipes JSON-RPC messages over stdio.
 * The bridge HMAC-signs each message and POSTs it to the moonlets server's
 * /mcp endpoint, then streams the response back over stdout. This keeps the
 * user's hook_secret on their machine — it never travels over the wire,
 * matching the auth posture of `moonlets-hook.sh` and `moonlets-statusline.sh`.
 *
 * Required env (typically set in shell rc, same vars as the hook script):
 *   MOONLETS_USER_ID
 *   MOONLETS_HOOK_SECRET
 *   MOONLETS_BASE_URL    (optional, default https://moonlets.laughingman.ai)
 */

import { createHmac } from "node:crypto";
import { createInterface } from "node:readline";

const userId = process.env.MOONLETS_USER_ID;
const secret = process.env.MOONLETS_HOOK_SECRET;
const baseUrl = process.env.MOONLETS_BASE_URL ?? "https://moonlets.laughingman.ai";

if (!userId || !secret) {
    process.stderr.write(
        "moonlets MCP bridge: MOONLETS_USER_ID and MOONLETS_HOOK_SECRET must be set in the environment.\n" +
            "Run `/moonlets-setup` or copy the values from your dashboard at " +
            (baseUrl.replace(/\/$/, "") + "/dashboard") +
            ".\n",
    );
    process.exit(1);
}

/** One signed POST per JSON-RPC message — keeps the bridge stateless. */
async function forward(message) {
    const ts = Math.floor(Date.now() / 1000);
    const canonical = `POST|/mcp|${userId}|${ts}`;
    const sig = createHmac("sha256", secret).update(canonical).digest("base64");
    const res = await fetch(`${baseUrl}/mcp`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            accept: "application/json, text/event-stream",
            "x-moonlets-user-id": userId,
            "x-moonlets-timestamp": String(ts),
            "x-moonlets-signature": sig,
        },
        body: message,
    });
    const text = await res.text();
    if (!text) return null;
    // The server is in JSON mode (not SSE), so the body is a single
    // JSON-RPC response. Pass it through line-delimited.
    return text;
}

const rl = createInterface({ input: process.stdin, terminal: false });

rl.on("line", async (line) => {
    if (!line.trim()) return;
    try {
        const out = await forward(line);
        if (out) process.stdout.write(out + "\n");
    } catch (err) {
        // Don't crash the bridge on a single bad message — surface a
        // JSON-RPC error response so the MCP client can show it.
        let id = null;
        try {
            id = JSON.parse(line).id ?? null;
        } catch {
            /* unparseable input — leave id null */
        }
        const errBody = JSON.stringify({
            jsonrpc: "2.0",
            id,
            error: {
                code: -32603,
                message: `moonlets bridge: ${err instanceof Error ? err.message : String(err)}`,
            },
        });
        process.stdout.write(errBody + "\n");
    }
});

rl.on("close", () => process.exit(0));
