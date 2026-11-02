// Stdio bridge for SignalRGB's MCP server. SignalRGB 2.5.84 answers MCP requests without a
// Content-Type header, which Claude's HTTP client rejects, so Claude talks to this over
// stdio and it forwards to http://127.0.0.1:16037/mcp. No dependencies.
const http = require("http");
const readline = require("readline");

const HOST = "127.0.0.1";
const PORT = 16037;
const PATH = "/mcp";

let sessionId = null;
let initMessage = null;

function post(text) {
	return new Promise((resolve, reject) => {
		const headers = {
			"Content-Type": "application/json",
			"Accept": "application/json, text/event-stream",
			"Content-Length": Buffer.byteLength(text),
		};
		if (sessionId) {
			headers["Mcp-Session-Id"] = sessionId;
		}
		const req = http.request({ host: HOST, port: PORT, path: PATH, method: "POST", headers, timeout: 30000 }, (res) => {
			const chunks = [];
			res.on("data", (c) => chunks.push(c));
			res.on("end", () => {
				if (res.headers["mcp-session-id"]) {
					sessionId = res.headers["mcp-session-id"];
				}
				resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString("utf8") });
			});
		});
		req.on("timeout", () => req.destroy(new Error("SignalRGB MCP request timed out")));
		req.on("error", reject);
		req.end(text);
	});
}

// Replies are plain JSON today. SSE framing is handled in case that changes.
function extractMessages(body) {
	const text = body.trim();
	if (!text) {
		return [];
	}
	if (text.startsWith("{") || text.startsWith("[")) {
		return [text];
	}
	return text.split(/\r?\n/).filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).filter(Boolean);
}

// SignalRGB forgets sessions when it restarts, so start a new one and retry once.
async function forward(text, isInit) {
	let res = await post(text);
	if ((res.status === 404 || res.status === 400) && !isInit && initMessage) {
		sessionId = null;
		await post(initMessage);
		await post(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }));
		res = await post(text);
	}
	if (res.status >= 400) {
		throw new Error(`SignalRGB MCP returned HTTP ${res.status}`);
	}
	return extractMessages(res.body);
}

async function handle(line) {
	let msg;
	try {
		msg = JSON.parse(line);
	} catch (e) {
		return;
	}
	const isInit = msg.method === "initialize";
	if (isInit) {
		initMessage = line;
		sessionId = null;
	}
	try {
		for (const out of await forward(line, isInit)) {
			process.stdout.write(out + "\n");
		}
	} catch (e) {
		if (msg.id !== undefined) {
			process.stdout.write(JSON.stringify({
				jsonrpc: "2.0",
				id: msg.id,
				error: { code: -32000, message: `${e.message}. Is SignalRGB running?` },
			}) + "\n");
		}
	}
}

let queue = Promise.resolve();
readline.createInterface({ input: process.stdin }).on("line", (line) => {
	if (line.trim()) {
		queue = queue.then(() => handle(line));
	}
}).on("close", () => {
	queue.then(() => process.exit(0));
});
