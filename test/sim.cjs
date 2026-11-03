// Runs the plugin against a fake HID device. No hardware involved.
const fs = require("fs");
const path = require("path");

let fails = 0;
let checks = 0;
function ok(cond, name) {
	checks++;
	if (!cond) {
		fails++;
	}
	console.log(`${cond ? "ok  " : "FAIL"} ${name}`);
}

const source = fs.readFileSync(path.join(__dirname, "..", "plugin", "MSI_185Byte_Controller_0x0DB0.js"), "utf8");

function load(model, allowed = true) {
	const state = { now: 1000, sends: [], other: [], color: [10, 20, 30], notes: [] };
	const channel = { LedCount: () => 0, shouldPulseColors: () => false, getColors: () => [] };
	const device = {
		log: () => {},
		pause: (ms) => { state.now += ms; },
		notify: (t) => state.notes.push(t),
		setName: () => {},
		createSubdevice: () => {},
		setSubdeviceName: () => {},
		setSubdeviceLeds: () => {},
		setSubdeviceSize: () => {},
		SetLedLimit: () => {},
		addChannel: () => {},
		channel: () => channel,
		createColorArray: () => [],
		subdeviceColor: () => state.color,
		send_report: (data, size) => { state.sends.push({ data: data.slice(), size }); return size; },
		get_report: (...a) => { state.other.push(["get_report", a]); return []; },
		write: (...a) => { state.other.push(["write", a]); },
		read: (...a) => { state.other.push(["read", a]); return []; },
	};
	const systeminfo = { GetMotherboardInfo: () => ({ model }) };
	const permissions = { permissions: () => ({ MSI: { lighting: allowed } }) };
	const code = source.replace(/^import .*$/gm, "").replace(/^export function /gm, "function ");
	const run = new Function("device", "systeminfo", "permissions", "Date", "LightingMode", "forcedColor", "shutdownColor",
		`${code}\nreturn { Initialize, Render, Shutdown, buildSetupReport };`);
	return { state, api: run(device, systeminfo, permissions, { now: () => state.now }, "Canvas", "#009bde", "#000000") };
}

const BOARD = "MEG X870E GODLIKE X EDITION (MS-7E48)";

console.log("--- setup report");
{
	const { state, api } = load(BOARD);
	api.Initialize();
	const setup = state.sends[0];
	ok(state.sends.length === 1 && setup.size === 290 && setup.data.length === 290 && setup.data[0] === 0x50, "one 290-byte 0x50 report at startup");
	const row = (i) => setup.data.slice(1 + i * 16, 17 + i * 16);
	const hex = (a) => a.map((b) => b.toString(16).padStart(2, "0")).join(" ");
	const jargb = "09 ff 00 00 00 ff 00 00 00 ff ff ff ff 03 15 78";
	const active = "09 ff 00 00 00 ff 00 00 00 ff ff ff ff 03 95 1e";
	const off = "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1e";
	ok([0, 1, 2, 3].every((i) => hex(row(i)) === jargb), "JARGB1-3 and JAF match the built-in plugin's bytes");
	ok([4, 5, 6].every((i) => hex(row(i)) === active), "JPIPE1-3 on, as the board itself reports");
	ok(hex(row(7)) === off, "JPIPE4 off");
	ok([8, 9, 10, 11, 12, 13, 14, 15, 16].every((i) => hex(row(i)) === off), "JPIPE5, JRGB1-2 and Onboard1-6 off");
	ok(hex(row(17)) === active, "select-all row on");
	ok(setup.data[289] === 0x00, "trailing byte is zero");
}

console.log("--- color reports");
{
	const { state, api } = load(BOARD);
	api.Initialize();
	state.sends.length = 0;
	api.Render();
	ok(state.sends.length === 1, "only logos are sent when no header has LEDs");
	const p = state.sends[0];
	ok(p.size === 727, "727-byte report");
	ok(p.data.slice(0, 7).join() === [0x51, 0x09, 0x06, 0, 0, 0, 37].join(), "header is 51 09 06 00 00 00 25, 37 LEDs");
	ok(p.data.length === 7 + 37 * 3 && p.data[7] === 10 && p.data[8] === 20 && p.data[9] === 30, "colors follow the header");
	api.Render();
	ok(state.sends.length === 1, "unchanged colors are not resent");
	state.now += 1001;
	api.Render();
	ok(state.sends.length === 1, "a steady color isn't resent every second");
	state.now += 30000;
	api.Render();
	ok(state.sends.length === 2, "colors are refreshed every 30 seconds");
	state.color = [1, 2, 3];
	api.Render();
	ok(state.sends.length === 2, "changed colors wait out the minimum gap");
	state.now += 100;
	api.Render();
	ok(state.sends.length === 3 && state.sends[2].data[7] === 1, "changed colors go out after the gap");
	const before = state.sends.length;
	for (let frame = 0; frame < 60; frame++) {
		state.color = [frame, 2, 3];
		state.now += 16;
		api.Render();
	}
	const sent = state.sends.length - before;
	ok(sent >= 8 && sent <= 10, `a 60 fps effect sends about 10 reports a second (sent ${sent})`);
	ok(state.other.length === 0, "no feature reads, reads or plain writes");
	api.Shutdown(false);
	const last = state.sends[state.sends.length - 1];
	ok(last.data[6] === 37 && last.data[7] === 0 && last.data[8] === 0 && last.data[9] === 0, "shutdown sends the shutdown color");
}

console.log("--- refusals");
{
	const { state, api } = load("MPG X870E CARBON WIFI (MS-7E49)");
	api.Initialize();
	api.Render();
	api.Shutdown(false);
	ok(state.sends.length === 0 && state.other.length === 0 && state.notes.length === 1, "other board: nothing sent, notice shown");
}
{
	const { state, api } = load(BOARD, false);
	api.Initialize();
	api.Render();
	api.Shutdown(false);
	ok(state.sends.length === 0, "MSI lighting permission off: nothing sent");
}
ok(!/get_report|device\.read|device\.write\(/.test(source), "source has no feature reads, reads or plain writes");
ok((source.match(/send_report\(/g) || []).length === 2, "source has exactly two send paths");

console.log("--- dashboard LCD plugin");
{
	const code = fs.readFileSync(path.join(__dirname, "..", "plugin", "MSI_Dynamic_Dashboard_LCD.js"), "utf8")
		.replace(/^import .*$/gm, "")
		.replace(/^export function /gm, "function ");
	const makeJpeg = (seed) => [0xff, 0xd8, seed & 255, 1, 2, 0xff, 0xd9];
	const start = (update) => {
		const s = { now: 1000, sent: [], init: null, frame: 1 };
		const device = { log: () => {}, setFrameRateTarget: () => {} };
		const udp = { createSocket: () => ({ on: () => {}, close: () => {}, write: (text, host, port) => s.sent.push({ text, host, port }) }) };
		const LCD = { initialize: (o) => { s.init = o; }, getFrame: () => s.jpeg === undefined ? makeJpeg(s.frame) : s.jpeg };
		const run = new Function("device", "udp", "LCD", "Date", "UpdateSeconds", "JpegQuality", `${code}\nreturn { Initialize, Render, ProductId, ControllableParameters };`);
		s.api = run(device, udp, LCD, { now: () => s.now }, update, 85);
		s.go = (ms) => { const end = s.now + ms; while (s.now < end) { s.api.Render(); s.now += 50; } };
		s.api.Initialize();
		return s;
	};
	const s = start("10");
	ok(s.api.ProductId().includes(0xf53a) && s.api.ProductId().includes(0x84df), "covers both dashboard USB IDs");
	s.go(29000);
	ok(!s.init && s.sent.length === 0, "waits for SignalRGB's face scan, so a saved face isn't reset");
	s.go(2000);
	ok(s.init && s.init.width === 400 && s.init.height === 864, "asks SignalRGB for the panel's own 400x864");
	ok(s.sent.length === 1 && s.sent[0].host === "127.0.0.1" && s.sent[0].port === 51875 && s.sent[0].text.startsWith("LLG1|"), "sends the frame to the helper on this PC only");
	s.frame = 2;
	s.go(9000);
	ok(s.sent.length === 1, "holds back a changed frame until the update time");
	s.go(2000);
	ok(s.sent.length === 2, "then sends it");
	s.go(30000);
	ok(s.sent.length === 2, "an unchanged picture is never sent again");
	const fast = start("1");
	fast.go(31000);
	fast.frame = 5;
	fast.go(3000);
	ok(fast.sent.length === 1, "no setting can send more often than every 5 seconds, because rapid uploads make the panel restart");
	const notJpeg = start("10");
	notJpeg.jpeg = [1, 2, 3, 4, 5];
	notJpeg.go(31000);
	ok(notJpeg.sent.length === 0, "anything that isn't a JPEG is not sent");
}
console.log(`\n${checks - fails}/${checks} checks passed`);
process.exit(fails ? 1 : 0);
