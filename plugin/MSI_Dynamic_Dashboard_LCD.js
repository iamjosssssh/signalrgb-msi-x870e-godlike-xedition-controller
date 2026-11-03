// MSI MEG X870E GODLIKE Dynamic Dashboard for SignalRGB. USB 0DB0:F53A and 0DB0:84DF.
// Shows whatever SignalRGB's LCD tab is set to. Community plugin, not affiliated with MSI or WhirlwindFX.
//
// A plugin can't send this panel's commands, so frames go to GodlikeLcdBridge.exe over 127.0.0.1.
// The panel takes whole picture files rather than a video stream, so this is a slowly updating screen.
import LCD from "@SignalRGB/lcd";
import udp from "@SignalRGB/udp";

export function Name() { return "MSI Dynamic Dashboard LCD"; }
export function VendorId() { return 0x0DB0; }
export function ProductId() { return [0xF53A, 0x84DF]; }
export function Publisher() { return "Community"; }
export function Documentation() { return ""; }
export function Size() { return [1, 1]; }
// One canvas unit is 3 mm, and this screen is about 42 x 91 mm.
export function DefaultPosition() { return [10, 10]; }
export function DefaultScale() { return 14.0; }
export function DeviceType() { return "lcd"; }
export function Type() { return "hid"; }
export function ImageUrl() { return "https://raw.githubusercontent.com/iamjosssssh/signalrgb-msi-x870e-godlike-xedition-controller/main/assets/devices/dynamic-dashboard.png"; }
export function ConflictingProcesses() { return ["DCv2.exe"]; }
export function Validate() { return true; }
export function LedNames() { return []; }
export function LedPositions() { return []; }

/* global
UpdateSeconds:readonly
JpegQuality:readonly
*/
export function ControllableParameters() {
	return [
		{"property":"UpdateSeconds", "group":"", "label":"Update Every (seconds)", "description":"How often a changed picture is sent. Each one is written to the panel, and how well its storage copes with constant writes isn't known, so slower is safer.", "type":"combobox", "values":["5", "10", "30", "60"], "default":"10"},
		{"property":"JpegQuality", "group":"", "label":"Picture Quality", "description":"Higher looks better and takes more space on the panel. Everything else is on the LCD tab.", "type":"number", "min":"30", "max":"95", "step":"5", "default":"85"},
	];
}

const LCD_WIDTH = 400;
const LCD_HEIGHT = 864;
const BRIDGE_PORT = 51875;
const BRIDGE_CHUNK = 48000;
const MIN_UPDATE_MS = 5000;
// SignalRGB resets a screen's saved face if it joins before the face scan, about 10 seconds after it starts.
const FACE_SCAN_WAIT_MS = 30000;
const FRAME_RATE = 10;

let startedAt = 0;
let joined = false;
let lastSentAt = 0;
let lastJpeg = null;
let frameId = 0;
let socket = null;
let sent = 0;

function log(msg) {
	device.log(`[DashboardLCD] ${msg}`, {toFile: true});
}

function base64(bytes) {
	const abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	const out = [];
	for (let i = 0; i < bytes.length; i += 3) {
		const n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
		out.push(abc[(n >> 18) & 63], abc[(n >> 12) & 63], i + 1 < bytes.length ? abc[(n >> 6) & 63] : "=", i + 2 < bytes.length ? abc[n & 63] : "=");
	}
	return out.join("");
}

function sameAsLast(jpeg) {
	if (!lastJpeg || lastJpeg.length !== jpeg.length) {
		return false;
	}
	for (let i = 0; i < jpeg.length; i++) {
		if (lastJpeg[i] !== jpeg[i]) {
			return false;
		}
	}
	return true;
}

function sendFrame(jpeg) {
	if (!socket) {
		socket = udp.createSocket();
		socket.on("error", (e) => log(`Bridge socket error: ${e}`));
	}
	const encoded = base64(jpeg);
	frameId = (frameId + 1) % 100000;
	const count = Math.ceil(encoded.length / BRIDGE_CHUNK);
	for (let i = 0; i < count; i++) {
		socket.write(`LLG1|${frameId}|${i}|${count}|${encoded.slice(i * BRIDGE_CHUNK, (i + 1) * BRIDGE_CHUNK)}`, "127.0.0.1", BRIDGE_PORT);
	}
}

export function Initialize() {
	startedAt = Date.now();
	device.setFrameRateTarget(FRAME_RATE);
	log("Started.");
}

export function Render() {
	const now = Date.now();
	if (!joined) {
		if (now - startedAt < FACE_SCAN_WAIT_MS) {
			return;
		}
		LCD.initialize({ width: LCD_WIDTH, height: LCD_HEIGHT });
		joined = true;
	}
	if (now - lastSentAt < Math.max(MIN_UPDATE_MS, (Number(UpdateSeconds) || 10) * 1000)) {
		return;
	}
	const jpeg = LCD.getFrame({ format: "JPEG", quality: Number(JpegQuality) || 85 });
	if (!jpeg || jpeg.length < 4 || jpeg[0] !== 0xFF || jpeg[1] !== 0xD8 || sameAsLast(jpeg)) {
		return;
	}
	sendFrame(jpeg);
	lastJpeg = jpeg.slice();
	lastSentAt = now;
	if (++sent === 1 || sent % 500 === 0) {
		log(`Frames sent: ${sent}, last ${jpeg.length} bytes.`);
	}
}

// The panel keeps showing the last picture.
export function Shutdown() {
	if (socket) {
		socket.close();
	}
	socket = null;
}
