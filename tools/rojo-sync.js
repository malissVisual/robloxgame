#!/usr/bin/env node
/*
 * rojo-sync — náhrada za `rojo serve` v čistém Node.js.
 *
 * PROČ TOHLE EXISTUJE
 * Na tomhle PC běží Windows Smart App Control, který odmítá spustit nepodepsané
 * binárky — a rojo.exe podepsaný není. Takže mluvíme s oficiálním Rojo pluginem
 * 7.7.0 přímo: stejné endpointy, stejný formát, jen v Node.
 *
 * PROTOKOL (Rojo 7.7.0, protocolVersion 5) — ověřeno ve zdrojácích:
 *   GET  /api/rojo             → handshake (msgpack)
 *   GET  /api/read/{id,id,..}  → celý strom (msgpack)
 *   GET  /api/socket/{cursor}  → WebSocket, binární msgpack rámce se změnami
 *   POST /api/write            → zápis ze Studia zpět (jen potvrzujeme, ignorujeme)
 *   POST /api/open/{id}        → "otevři skript v editoru"
 *
 * Pozor na dvě pasti, na kterých se to jinak zasekne:
 *   1) Všechno je MessagePack, ne JSON.
 *   2) Instance má klíče PascalCase (Id, Parent, Name, ClassName, Properties,
 *      Children, Metadata), ale úplně všechno ostatní je camelCase.
 *
 * Spuštění:  node tools/rojo-sync.js
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const PROJECT_FILE = path.join(PROJECT_ROOT, "default.project.json");
const PORT = Number(process.env.ROJO_PORT || 34872);
const HOST = "127.0.0.1";

const SERVER_VERSION = "7.7.0";
const PROTOCOL_VERSION = 5;
const NULL_REF = "0".repeat(32);

// ───────────────────────────────────────────────────────────── MessagePack ──
// Jen encode — požadavky od pluginu nepotřebujeme číst do detailu.

function encode(value) {
	const chunks = [];
	write(value, chunks);
	return Buffer.concat(chunks);
}

function write(value, out) {
	if (value === null || value === undefined) {
		out.push(Buffer.from([0xc0]));
		return;
	}

	switch (typeof value) {
		case "boolean":
			out.push(Buffer.from([value ? 0xc3 : 0xc2]));
			return;
		case "number":
			writeNumber(value, out);
			return;
		case "string":
			writeString(value, out);
			return;
	}

	if (Buffer.isBuffer(value)) {
		writeBinary(value, out);
		return;
	}

	if (Array.isArray(value)) {
		writeArrayHeader(value.length, out);
		for (const item of value) {
			write(item, out);
		}
		return;
	}

	// Klíče s hodnotou undefined se na drát vůbec nedostanou.
	const keys = Object.keys(value).filter((key) => value[key] !== undefined);
	writeMapHeader(keys.length, out);
	for (const key of keys) {
		writeString(key, out);
		write(value[key], out);
	}
}

function writeNumber(value, out) {
	if (!Number.isInteger(value)) {
		const buffer = Buffer.allocUnsafe(9);
		buffer.writeUInt8(0xcb, 0);
		buffer.writeDoubleBE(value, 1);
		out.push(buffer);
		return;
	}

	if (value >= 0) {
		if (value < 0x80) {
			out.push(Buffer.from([value]));
		} else if (value < 0x100) {
			out.push(Buffer.from([0xcc, value]));
		} else if (value < 0x10000) {
			const b = Buffer.allocUnsafe(3);
			b.writeUInt8(0xcd, 0);
			b.writeUInt16BE(value, 1);
			out.push(b);
		} else if (value < 0x100000000) {
			const b = Buffer.allocUnsafe(5);
			b.writeUInt8(0xce, 0);
			b.writeUInt32BE(value, 1);
			out.push(b);
		} else {
			const b = Buffer.allocUnsafe(9);
			b.writeUInt8(0xcf, 0);
			b.writeBigUInt64BE(BigInt(value), 1);
			out.push(b);
		}
		return;
	}

	if (value >= -32) {
		out.push(Buffer.from([0xe0 | (value + 32)]));
	} else if (value >= -128) {
		const b = Buffer.allocUnsafe(2);
		b.writeUInt8(0xd0, 0);
		b.writeInt8(value, 1);
		out.push(b);
	} else if (value >= -32768) {
		const b = Buffer.allocUnsafe(3);
		b.writeUInt8(0xd1, 0);
		b.writeInt16BE(value, 1);
		out.push(b);
	} else if (value >= -2147483648) {
		const b = Buffer.allocUnsafe(5);
		b.writeUInt8(0xd2, 0);
		b.writeInt32BE(value, 1);
		out.push(b);
	} else {
		const b = Buffer.allocUnsafe(9);
		b.writeUInt8(0xd3, 0);
		b.writeBigInt64BE(BigInt(value), 1);
		out.push(b);
	}
}

function writeString(value, out) {
	const bytes = Buffer.from(value, "utf8");
	const length = bytes.length;

	if (length < 32) {
		out.push(Buffer.from([0xa0 | length]));
	} else if (length < 0x100) {
		out.push(Buffer.from([0xd9, length]));
	} else if (length < 0x10000) {
		const b = Buffer.allocUnsafe(3);
		b.writeUInt8(0xda, 0);
		b.writeUInt16BE(length, 1);
		out.push(b);
	} else {
		const b = Buffer.allocUnsafe(5);
		b.writeUInt8(0xdb, 0);
		b.writeUInt32BE(length, 1);
		out.push(b);
	}
	out.push(bytes);
}

function writeBinary(value, out) {
	const length = value.length;
	if (length < 0x100) {
		out.push(Buffer.from([0xc4, length]));
	} else if (length < 0x10000) {
		const b = Buffer.allocUnsafe(3);
		b.writeUInt8(0xc5, 0);
		b.writeUInt16BE(length, 1);
		out.push(b);
	} else {
		const b = Buffer.allocUnsafe(5);
		b.writeUInt8(0xc6, 0);
		b.writeUInt32BE(length, 1);
		out.push(b);
	}
	out.push(value);
}

function writeArrayHeader(length, out) {
	if (length < 16) {
		out.push(Buffer.from([0x90 | length]));
	} else if (length < 0x10000) {
		const b = Buffer.allocUnsafe(3);
		b.writeUInt8(0xdc, 0);
		b.writeUInt16BE(length, 1);
		out.push(b);
	} else {
		const b = Buffer.allocUnsafe(5);
		b.writeUInt8(0xdd, 0);
		b.writeUInt32BE(length, 1);
		out.push(b);
	}
}

function writeMapHeader(length, out) {
	if (length < 16) {
		out.push(Buffer.from([0x80 | length]));
	} else if (length < 0x10000) {
		const b = Buffer.allocUnsafe(3);
		b.writeUInt8(0xde, 0);
		b.writeUInt16BE(length, 1);
		out.push(b);
	} else {
		const b = Buffer.allocUnsafe(5);
		b.writeUInt8(0xdf, 0);
		b.writeUInt32BE(length, 1);
		out.push(b);
	}
}

// ─────────────────────────────────────────────────────────── Strom projektu ──

// Id musí být 32 hex znaků a musí zůstat stejné mezi překreslením stromu,
// jinak by plugin každou změnu chápal jako "smaž a vytvoř znovu".
function refFor(virtualPath) {
	return crypto.createHash("md5").update(virtualPath).digest("hex");
}

function classForFile(fileName) {
	if (fileName.endsWith(".server.luau") || fileName.endsWith(".server.lua")) {
		return { className: "Script", strip: /\.server\.luau?$/ };
	}
	if (fileName.endsWith(".client.luau") || fileName.endsWith(".client.lua")) {
		return { className: "LocalScript", strip: /\.client\.luau?$/ };
	}
	if (fileName.endsWith(".luau") || fileName.endsWith(".lua")) {
		return { className: "ModuleScript", strip: /\.luau?$/ };
	}
	return null;
}

function readSource(filePath) {
	return fs.readFileSync(filePath, "utf8").replace(/^﻿/, "");
}

// Sestaví jednu instanci a zaregistruje ji do mapy.
function addInstance(tree, virtualPath, parentId, name, className, properties, metadata) {
	const id = refFor(virtualPath);
	tree.instances[id] = {
		Id: id,
		Parent: parentId,
		Name: name,
		ClassName: className,
		Properties: properties || {},
		Children: [],
		Metadata: { ignoreUnknownInstances: metadata !== false },
	};
	if (parentId !== NULL_REF && tree.instances[parentId]) {
		tree.instances[parentId].Children.push(id);
	}
	return id;
}

// Adresář na disku → instance ve Studiu.
function buildFromPath(tree, diskPath, virtualPath, parentId, name) {
	let stat;
	try {
		stat = fs.statSync(diskPath);
	} catch (err) {
		console.warn(`  ! chybí ${path.relative(PROJECT_ROOT, diskPath)}`);
		return null;
	}

	if (stat.isFile()) {
		const info = classForFile(path.basename(diskPath));
		if (!info) {
			return null;
		}
		return addInstance(
			tree,
			virtualPath,
			parentId,
			name,
			info.className,
			{ Source: { String: readSource(diskPath) } },
			false
		);
	}

	if (!stat.isDirectory()) {
		return null;
	}

	// init.luau / init.server.luau → složka se sama stane skriptem.
	const entries = fs.readdirSync(diskPath).filter((entry) => !entry.startsWith("."));
	const initEntry = entries.find((entry) => /^init\.(server|client)?\.?luau?$/.test(entry));

	let className = "Folder";
	let properties = {};
	if (initEntry) {
		const info = classForFile(initEntry === "init.luau" || initEntry === "init.lua" ? "x.luau" : initEntry);
		if (info) {
			className = info.className;
			properties = { Source: { String: readSource(path.join(diskPath, initEntry)) } };
		}
	}

	const id = addInstance(tree, virtualPath, parentId, name, className, properties, false);

	for (const entry of entries.sort()) {
		if (entry === initEntry) {
			continue;
		}
		const childDisk = path.join(diskPath, entry);
		const childStat = fs.statSync(childDisk);

		let childName = entry;
		if (childStat.isFile()) {
			const info = classForFile(entry);
			if (!info) {
				continue;
			}
			childName = entry.replace(info.strip, "");
		}

		buildFromPath(tree, childDisk, `${virtualPath}/${entry}`, id, childName);
	}

	return id;
}

// Uzel z default.project.json.
function buildFromNode(tree, node, virtualPath, parentId, name, isRoot) {
	const className = node.$className || (isRoot ? "DataModel" : name);

	// Služby a organizační uzly necháváme "průhledné" — ať plugin nemaže
	// Workspace, Lighting a další věci, o kterých nic neví.
	const id = addInstance(tree, virtualPath, parentId, name, className, {}, true);

	if (node.$path) {
		const diskPath = path.resolve(PROJECT_ROOT, node.$path);
		// Obsah $path složky se nalepí přímo na tenhle uzel.
		const temp = { instances: {} };
		const builtId = buildFromPath(temp, diskPath, virtualPath, parentId, name);
		if (builtId) {
			// Přebereme třídu, Source a děti z disku, ale necháme si vlastní Id.
			const built = temp.instances[builtId];
			const self = tree.instances[id];
			self.ClassName = built.ClassName;
			self.Properties = built.Properties;
			self.Metadata = built.Metadata;
			for (const [childId, childInstance] of Object.entries(temp.instances)) {
				if (childId === builtId) {
					continue;
				}
				tree.instances[childId] = childInstance;
			}
			self.Children = built.Children;
		}
	}

	for (const [key, child] of Object.entries(node)) {
		if (key.startsWith("$")) {
			continue;
		}
		buildFromNode(tree, child, `${virtualPath}/${key}`, id, key, false);
	}

	return id;
}

function buildTree() {
	const project = JSON.parse(fs.readFileSync(PROJECT_FILE, "utf8"));
	const tree = { instances: {}, rootId: null, projectName: project.name || "Project" };
	tree.rootId = buildFromNode(tree, project.tree, "/", NULL_REF, project.name || "Project", true);
	return tree;
}

// ─────────────────────────────────────────────────────────────────── Rozdíl ──

function sameValue(a, b) {
	return JSON.stringify(a) === JSON.stringify(b);
}

// Všechna id pod danou instancí včetně jí samotné.
function collectSubtree(tree, id, out) {
	const instance = tree.instances[id];
	if (!instance || out[id]) {
		return;
	}
	out[id] = instance;
	for (const childId of instance.Children) {
		collectSubtree(tree, childId, out);
	}
}

function diffTrees(before, after) {
	const added = {};
	const removed = [];
	const updated = [];

	// Nejdřív přetřídění: ClassName se u živé instance změnit nedá (z Folderu
	// se Script neudělá), takže přejmenování foo.luau → foo.server.luau musí
	// projít jako smazání a nové vytvoření — i s celým podstromem pod ním.
	for (const [id, instance] of Object.entries(after.instances)) {
		const previous = before.instances[id];
		if (previous && previous.ClassName !== instance.ClassName) {
			removed.push(id);
			collectSubtree(after, id, added);
		}
	}

	for (const [id, instance] of Object.entries(after.instances)) {
		// Už je v přidaných jako součást znovuvytvořeného podstromu.
		if (added[id]) {
			continue;
		}

		const previous = before.instances[id];
		if (!previous) {
			added[id] = instance;
			continue;
		}

		const changedProperties = {};
		for (const [key, value] of Object.entries(instance.Properties)) {
			if (!sameValue(previous.Properties[key], value)) {
				changedProperties[key] = value;
			}
		}
		for (const key of Object.keys(previous.Properties)) {
			if (!(key in instance.Properties)) {
				changedProperties[key] = null;
			}
		}

		const nameChanged = previous.Name !== instance.Name;
		if (nameChanged || Object.keys(changedProperties).length > 0) {
			const update = { id, changedProperties };
			if (nameChanged) {
				update.changedName = instance.Name;
			}
			updated.push(update);
		}
	}

	for (const id of Object.keys(before.instances)) {
		if (!after.instances[id]) {
			removed.push(id);
		}
	}

	return { added, removed, updated };
}

function isEmptyPatch(patch) {
	return (
		Object.keys(patch.added).length === 0 &&
		patch.removed.length === 0 &&
		patch.updated.length === 0
	);
}

// ──────────────────────────────────────────────────────────────── WebSocket ──

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const sockets = new Set();

function acceptKey(key) {
	return crypto.createHash("sha1").update(key + WS_GUID).digest("base64");
}

function frameBinary(payload) {
	const length = payload.length;
	let header;

	if (length < 126) {
		header = Buffer.from([0x82, length]);
	} else if (length < 0x10000) {
		header = Buffer.allocUnsafe(4);
		header.writeUInt8(0x82, 0);
		header.writeUInt8(126, 1);
		header.writeUInt16BE(length, 2);
	} else {
		header = Buffer.allocUnsafe(10);
		header.writeUInt8(0x82, 0);
		header.writeUInt8(127, 1);
		header.writeBigUInt64BE(BigInt(length), 2);
	}

	return Buffer.concat([header, payload]);
}

// Rámce od klienta nás skoro nezajímají — jen ping a zavření.
function handleClientFrames(socket) {
	let buffer = Buffer.alloc(0);

	socket.on("data", (chunk) => {
		buffer = Buffer.concat([buffer, chunk]);

		while (buffer.length >= 2) {
			const opcode = buffer[0] & 0x0f;
			const masked = (buffer[1] & 0x80) !== 0;
			let length = buffer[1] & 0x7f;
			let offset = 2;

			if (length === 126) {
				if (buffer.length < 4) return;
				length = buffer.readUInt16BE(2);
				offset = 4;
			} else if (length === 127) {
				if (buffer.length < 10) return;
				length = Number(buffer.readBigUInt64BE(2));
				offset = 10;
			}

			const maskLength = masked ? 4 : 0;
			if (buffer.length < offset + maskLength + length) return;
			offset += maskLength;
			buffer = buffer.subarray(offset + length);

			if (opcode === 0x8) {
				socket.end();
				return;
			}
			if (opcode === 0x9) {
				socket.write(Buffer.from([0x8a, 0x00])); // pong
			}
		}
	});
}

// ─────────────────────────────────────────────────────────────────── Server ──

const sessionId = crypto.randomUUID();
let tree = buildTree();
const messages = [];

function instanceCount() {
	return Object.keys(tree.instances).length;
}

function broadcast(patch) {
	messages.push(patch);
	const packet = encode({
		sessionId,
		packetType: "messages",
		body: {
			messageCursor: messages.length,
			messages: [patch],
		},
	});
	const frame = frameBinary(packet);

	for (const socket of sockets) {
		if (socket.destroyed) {
			sockets.delete(socket);
			continue;
		}
		try {
			socket.write(frame);
		} catch (err) {
			sockets.delete(socket);
		}
	}
}

function respond(res, status, payload) {
	const body = encode(payload);
	res.writeHead(status, {
		"Content-Type": "application/msgpack",
		"Content-Length": body.length,
	});
	res.end(body);
}

function notFound(res, urlPath) {
	respond(res, 404, { kind: "NotFound", details: `Route not found: ${urlPath}` });
}

const server = http.createServer((req, res) => {
	const urlPath = (req.url || "").split("?")[0];

	if (req.method === "GET" && urlPath === "/api/rojo") {
		// expectedPlaceIds / gameId / placeId schválně vynecháváme —
		// jinak by plugin přepsal identitu placu nebo odmítl připojení.
		respond(res, 200, {
			sessionId,
			serverVersion: SERVER_VERSION,
			protocolVersion: PROTOCOL_VERSION,
			projectName: tree.projectName,
			rootInstanceId: tree.rootId,
		});
		console.log(`→ handshake (${instanceCount()} instancí)`);
		return;
	}

	if (req.method === "GET" && urlPath.startsWith("/api/read/")) {
		respond(res, 200, {
			sessionId,
			messageCursor: messages.length,
			instances: tree.instances,
		});
		console.log(`→ read: poslán celý strom (${instanceCount()} instancí)`);
		return;
	}

	if (req.method === "POST" && urlPath === "/api/write") {
		// Dvoucestný sync nepodporujeme — změny ze Studia jen potvrdíme.
		req.resume();
		req.on("end", () => respond(res, 200, { sessionId }));
		return;
	}

	if (req.method === "POST" && urlPath.startsWith("/api/open/")) {
		req.resume();
		req.on("end", () => respond(res, 200, { sessionId }));
		return;
	}

	if (req.method === "POST" && (urlPath === "/api/serialize" || urlPath === "/api/ref-patch")) {
		// Záchranná cesta pluginu. Když ji odmítneme, plugin to spolkne.
		req.resume();
		req.on("end", () =>
			respond(res, 400, { kind: "BadRequest", details: "Not supported by rojo-sync" })
		);
		return;
	}

	notFound(res, urlPath);
});

server.on("upgrade", (req, socket) => {
	const urlPath = (req.url || "").split("?")[0];
	const key = req.headers["sec-websocket-key"];

	if (!urlPath.startsWith("/api/socket/") || !key) {
		socket.destroy();
		return;
	}

	const cursor = Number.parseInt(urlPath.slice("/api/socket/".length), 10);

	socket.write(
		[
			"HTTP/1.1 101 Switching Protocols",
			"Upgrade: websocket",
			"Connection: Upgrade",
			`Sec-WebSocket-Accept: ${acceptKey(key)}`,
			"",
			"",
		].join("\r\n")
	);

	socket.setNoDelay(true);
	sockets.add(socket);
	handleClientFrames(socket);

	socket.on("close", () => sockets.delete(socket));
	socket.on("error", () => sockets.delete(socket));

	console.log("✓ Studio připojeno");

	// Doženeme, co plugin zmeškal.
	if (Number.isInteger(cursor) && cursor < messages.length) {
		const missed = messages.slice(cursor);
		socket.write(
			frameBinary(
				encode({
					sessionId,
					packetType: "messages",
					body: { messageCursor: messages.length, messages: missed },
				})
			)
		);
	}
});

// ───────────────────────────────────────────────────────────── Sledování src ──

let pending = null;

function rescan() {
	let next;
	try {
		next = buildTree();
	} catch (err) {
		console.error(`  ! chyba při čtení projektu: ${err.message}`);
		return;
	}

	const patch = diffTrees(tree, next);
	tree = next;

	if (isEmptyPatch(patch)) {
		return;
	}

	const parts = [];
	if (Object.keys(patch.added).length) parts.push(`+${Object.keys(patch.added).length}`);
	if (patch.removed.length) parts.push(`-${patch.removed.length}`);
	if (patch.updated.length) parts.push(`~${patch.updated.length}`);

	broadcast(patch);
	console.log(`↻ změna (${parts.join(" ")}) → odesláno do Studia`);
}

let deadline = null;

function fire() {
	clearTimeout(pending);
	pending = null;
	clearTimeout(deadline);
	deadline = null;
	rescan();
}

// Debounce se STROPEM. Bez toho stropu stačí jeden proud událostí (smazání
// sledované složky jich vysype statisíce za vteřinu) a timer se pořád resetuje
// — rescan by se nespustil už nikdy a sync by tiše umřel.
function schedule() {
	clearTimeout(pending);
	pending = setTimeout(fire, 120);
	if (!deadline) {
		deadline = setTimeout(fire, 1000);
	}
}

// Zajímá nás jen src/ a soubor projektu. fileName chodí relativně,
// na Windows se zpětnými lomítky, a občas je null.
function inScope(fileName) {
	if (!fileName) {
		return false;
	}
	const normalized = fileName.split(path.sep).join("/");
	return normalized === "default.project.json" || normalized === "src" || normalized.startsWith("src/");
}

// Sledujeme kořen projektu, ne src — kořen nezmizí. Kdyby se sledovalo src
// a někdo ho smazal nebo přejmenoval, handle zůstane viset na neexistující
// složce a už se nic nedozvíme.
function watch() {
	let watcher = null;

	const attach = () => {
		try {
			watcher = fs.watch(PROJECT_ROOT, { recursive: true }, (eventType, fileName) => {
				if (inScope(fileName)) {
					schedule();
				}
			});
		} catch (err) {
			console.warn(`  ! nejde sledovat projekt: ${err.message} — zkusím za chvíli`);
			setTimeout(attach, 1000);
			return;
		}

		watcher.on("error", (err) => {
			console.warn(`  ! sledování spadlo: ${err.message} — obnovuju`);
			try {
				watcher.close();
			} catch {}
			setTimeout(() => {
				attach();
				schedule(); // než se watcher vrátil, mohlo se leccos změnit
			}, 500);
		});
	};

	attach();
}

server.listen(PORT, HOST, () => {
	console.log("");
	console.log("  rojo-sync — náhrada rojo serve pro Roblox Studio");
	console.log(`  projekt:  ${tree.projectName}`);
	console.log(`  instancí: ${instanceCount()}`);
	console.log(`  adresa:   http://${HOST}:${PORT}`);
	console.log("");
	console.log("  Ve Studiu: Plugins → Rojo → Connect");
	console.log("");
	watch();
});
