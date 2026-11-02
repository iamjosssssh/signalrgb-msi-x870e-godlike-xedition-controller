// MSI MEG X870E GODLIKE X EDITION (MS-7E48) lighting for SignalRGB. Mystic Light controller 0DB0:0076.
//
// Differs from SignalRGB's built-in MSI plugin in two ways:
//  1. JPIPE4 stays off in the setup report. This board reports only JPIPE1-3, and turning JPIPE4
//     on as well leaves the logos dark.
//  2. No feature read after each color update. The built-in plugin reads 727 bytes, smaller than
//     the board's largest feature report (761), and each read stalls for 5 seconds.
//
// Writes nothing on any other board. Only two kinds of write exist: the 290-byte setup report and
// the 727-byte per-LED report. Community plugin, not affiliated with MSI or WhirlwindFX.

import systeminfo from "@SignalRGB/systeminfo";
import permissions from "@SignalRGB/permissions";

export function Name() { return "MSI Mystic Light Controller"; }
export function VendorId() { return 0x0DB0; }
export function ProductId() { return 0x0076; }
export function Publisher() { return "Community"; }
export function Documentation() { return "troubleshooting/msi"; }
export function Size() { return [1, 1]; }
export function Type() { return "Hid"; }
export function DefaultPosition() { return [0, 0]; }
export function DefaultScale() { return 8.0; }
export function DeviceType() { return "motherboard"; }
export function ImageUrl() { return "https://assets.signalrgb.com/devices/brands/msi/motherboards/motherboard.png"; }
export function ConflictingProcesses() {
	return ["LedKeeper.exe", "Dragon Center", "DCv2.exe", "LightKeeperService.exe", "LightKeeperService2.exe"];
}

/* global
shutdownColor:readonly
LightingMode:readonly
forcedColor:readonly
*/
export function ControllableParameters() {
	return [
		{"property":"shutdownColor", "group":"lighting", "label":"Shutdown Color", "description":"Applied when the system or SignalRGB shuts down", "min":"0", "max":"360", "type":"color", "default":"#000000"},
		{"property":"LightingMode", "group":"lighting", "label":"Lighting Mode", "description":"Canvas follows the active effect. Forced uses one color", "type":"combobox", "values":["Canvas", "Forced"], "default":"Canvas"},
		{"property":"forcedColor", "group":"lighting", "label":"Forced Color", "min":"0", "max":"360", "type":"color", "default":"#009bde"},
	];
}

export function LedNames() { return []; }
export function LedPositions() { return []; }

export function Validate(endpoint) {
	return endpoint.interface === 0 || endpoint.interface === 2;
}

const SUPPORTED_BOARD = "MEG X870E GODLIKE X EDITION (MS-7E48)";
const SETUP_REPORT = 0x50;
const SETUP_SIZE = 290;
const LED_REPORT = 0x51;
const LED_SIZE = 727;
const MAX_LEDS_PER_REPORT = 240;
// The board holds its colors with no traffic, so this only recovers from a missed write.
const REFRESH_MS = 30000;
// Writes can take 5 seconds to fail if MSI's CC_Engine is using the controller too, which also
// stalls RAM lighting. See scripts\stop-msi-engine.ps1.
const MIN_SEND_MS = 100;

const TARGET_ARGB = 0x04;
const TARGET_ONBOARD = 0x06;
const TARGET_EZ = 0x08;
const ARGB_HEADER = "ARGB Header 1";
const EZ_CONNECTOR = "EZ Connector 1";

// All 37 logo LEDs travel in one onboard packet, in this order.
const LOGOS = [
	{ name: "Dragon Logo", leds: 12 },
	{ name: "MEG Logo", leds: 5 },
	{ name: "Enthusiast Logo", leds: 15 },
	{ name: "Godlike Logo", leds: 5 },
];

// Setup rows are 16 bytes each and start at byte 1.
const ROW_JARGB = [0x09, 0xff, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x03, 0x15, 0x78];
const ROW_ACTIVE = [0x09, 0xff, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x03, 0x95, 0x1e];
const ROW_OFF = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1e];

// JARGB1-3, JAF, JPIPE1-3, then JPIPE4-5, JRGB1-2, Onboard1-6 off, then select all.
function buildSetupReport() {
	const rows = [ROW_JARGB, ROW_JARGB, ROW_JARGB, ROW_JARGB, ROW_ACTIVE, ROW_ACTIVE, ROW_ACTIVE];
	while (rows.length < 17) {
		rows.push(ROW_OFF);
	}
	rows.push(ROW_ACTIVE);
	return [SETUP_REPORT].concat(...rows, [0x00]);
}

function buildLedReport(target, index, rgb) {
	return [LED_REPORT, 0x09, target, index, 0x00, 0x00, rgb.length / 3].concat(rgb);
}

let supported = false;
let initialized = false;
let lastSent = {};

function lightingAllowed() {
	const all = permissions.permissions() || {};
	return !all.MSI || all.MSI.lighting !== false;
}

function boardName() {
	for (let attempt = 0; attempt < 10; attempt++) {
		const info = systeminfo.GetMotherboardInfo();
		if (info && info.model) {
			return info.model;
		}
		device.pause(500);
	}
	return "";
}

function initializeBoard() {
	for (const logo of LOGOS) {
		const names = [];
		const positions = [];
		for (let i = 0; i < logo.leds; i++) {
			names.push(`LED ${i + 1}`);
			positions.push([0, i]);
		}
		logo.positions = positions;
		device.createSubdevice(logo.name);
		device.setSubdeviceName(logo.name, `Mystic Light Controller - ${logo.name}`);
		device.setSubdeviceLeds(logo.name, names, positions);
		device.setSubdeviceSize(logo.name, 1, logo.leds);
	}
	device.SetLedLimit(480);
	device.addChannel(ARGB_HEADER, 120);
	device.addChannel(EZ_CONNECTOR, 120);
	device.send_report(buildSetupReport(), SETUP_SIZE);
	initialized = true;
}

export function Initialize() {
	const model = boardName();
	supported = model === SUPPORTED_BOARD;
	device.log(`Board: ${model}. Supported: ${supported}`, { toFile: true });
	if (!supported) {
		device.notify("Unsupported motherboard", `This plugin only supports the ${SUPPORTED_BOARD}. Remove it to use SignalRGB's built-in MSI plugin.`, 1);
		return;
	}
	device.setName(`MSI ${model}`);
	if (lightingAllowed()) {
		initializeBoard();
	}
}

export function Render() {
	if (!supported || !lightingAllowed()) {
		return;
	}
	if (!initialized) {
		initializeBoard();
	}
	sendAll();
}

export function Shutdown(SystemSuspending) {
	if (initialized && lightingAllowed()) {
		lastSent = {};
		sendAll(SystemSuspending ? "#000000" : shutdownColor);
	}
}

function hexToRgb(hex) {
	const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
	return [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)];
}

function logoColors(override) {
	const fixed = override ? hexToRgb(override) : (LightingMode === "Forced" ? hexToRgb(forcedColor) : null);
	const rgb = [];
	for (const logo of LOGOS) {
		for (const [x, y] of logo.positions) {
			const c = fixed || device.subdeviceColor(logo.name, x, y);
			rgb.push(c[0], c[1], c[2]);
		}
	}
	return rgb;
}

function channelColors(name, override) {
	const channel = device.channel(name);
	const count = channel.LedCount();
	if (override) {
		return device.createColorArray(override, count, "Inline");
	}
	if (LightingMode === "Forced") {
		return device.createColorArray(forcedColor, count, "Inline");
	}
	if (channel.shouldPulseColors()) {
		return device.createColorArray(device.getChannelPulseColor(name), 80, "Inline");
	}
	return channel.getColors("Inline");
}

// Sends a report only when its colors changed, or every REFRESH_MS, and never more often than
// MIN_SEND_MS.
function sendIfDue(key, target, index, rgb) {
	if (rgb.length === 0 || rgb.length > MAX_LEDS_PER_REPORT * 3) {
		return;
	}
	const now = Date.now();
	const signature = rgb.join(",");
	const last = lastSent[key];
	if (last && (now - last.at < MIN_SEND_MS || (last.signature === signature && now - last.at < REFRESH_MS))) {
		return;
	}
	lastSent[key] = { signature, at: now };
	device.send_report(buildLedReport(target, index, rgb), LED_SIZE);
}

function sendAll(override) {
	sendIfDue("argb", TARGET_ARGB, 0, channelColors(ARGB_HEADER, override));
	sendIfDue("ez", TARGET_EZ, 0, channelColors(EZ_CONNECTOR, override));
	sendIfDue("logos", TARGET_ONBOARD, 0, logoColors(override));
}
