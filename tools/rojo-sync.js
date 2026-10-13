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
 *   POST /api/serialize        → záchranná cesta: instance, které ve Studiu nešlo
 *                                přepsat, pošleme celé jako .rbxm (writeRbxm)
 *   POST /api/ref-patch        → k tomu Ref vlastnosti (u nás žádné: prázdný patch)
 *   POST /api/open/{id}        → "otevři skript v editoru"
 *   POST /api/rojo-sync/stop   → náš vlastní: nově spuštěný rojo-sync tím vypne starý
 *
 * Strom se čte z disku znovu při každém Connect ze Studia, při každé změně
 * v src/ a pro jistotu každých 5 s — po `git pull` už není potřeba nic
 * restartovat.
 *
 * Pozor na dvě pasti, na kterých se to jinak zasekne:
 *   1) Všechno je MessagePack, ne JSON.
 *   2) Instance má klíče PascalCase (Id, Parent, Name, ClassName, Properties,
 *      Children, Metadata), ale úplně všechno ostatní je camelCase.
 *
 * Spuštění:  node tools/rojo-sync.js              (Merge Blades, default.project.json v kořeni)
 *            node tools/rojo-sync.js zombie-delivery  (jiný projekt: složka s vlastním default.project.json)
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");

const PROJECT_ROOT = process.argv[2] ? path.resolve(process.argv[2]) : path.resolve(__dirname, "..");
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

// Decode — jen pro těla záchranné cesty pluginu (/api/serialize, /api/ref-patch):
// mapa { sessionId, ids }. Umí všechny běžné typy kromě ext.
function decode(buffer) {
	let offset = 0;
	const u8 = () => buffer[offset++];
	const take = (n) => {
		const slice = buffer.subarray(offset, offset + n);
		offset += n;
		return slice;
	};
	const array = (n) => {
		const out = [];
		for (let i = 0; i < n; i++) out.push(read());
		return out;
	};
	const map = (n) => {
		const out = {};
		for (let i = 0; i < n; i++) {
			const key = read();
			out[String(key)] = read();
		}
		return out;
	};
	function read() {
		const b = u8();
		if (b === undefined) throw new Error("msgpack: konec dat");
		if (b <= 0x7f) return b;
		if (b >= 0xe0) return b - 0x100;
		if ((b & 0xf0) === 0x80) return map(b & 0x0f);
		if ((b & 0xf0) === 0x90) return array(b & 0x0f);
		if ((b & 0xe0) === 0xa0) return take(b & 0x1f).toString("utf8");
		let n;
		switch (b) {
			case 0xc0: return null;
			case 0xc2: return false;
			case 0xc3: return true;
			case 0xc4: return Buffer.from(take(u8()));
			case 0xc5: n = buffer.readUInt16BE(offset); offset += 2; return Buffer.from(take(n));
			case 0xc6: n = buffer.readUInt32BE(offset); offset += 4; return Buffer.from(take(n));
			case 0xca: n = buffer.readFloatBE(offset); offset += 4; return n;
			case 0xcb: n = buffer.readDoubleBE(offset); offset += 8; return n;
			case 0xcc: return u8();
			case 0xcd: n = buffer.readUInt16BE(offset); offset += 2; return n;
			case 0xce: n = buffer.readUInt32BE(offset); offset += 4; return n;
			case 0xcf: n = Number(buffer.readBigUInt64BE(offset)); offset += 8; return n;
			case 0xd0: n = buffer.readInt8(offset); offset += 1; return n;
			case 0xd1: n = buffer.readInt16BE(offset); offset += 2; return n;
			case 0xd2: n = buffer.readInt32BE(offset); offset += 4; return n;
			case 0xd3: n = Number(buffer.readBigInt64BE(offset)); offset += 8; return n;
			case 0xd9: return take(u8()).toString("utf8");
			case 0xda: n = buffer.readUInt16BE(offset); offset += 2; return take(n).toString("utf8");
			case 0xdb: n = buffer.readUInt32BE(offset); offset += 4; return take(n).toString("utf8");
			case 0xdc: n = buffer.readUInt16BE(offset); offset += 2; return array(n);
			case 0xdd: n = buffer.readUInt32BE(offset); offset += 4; return array(n);
			case 0xde: n = buffer.readUInt16BE(offset); offset += 2; return map(n);
			case 0xdf: n = buffer.readUInt32BE(offset); offset += 4; return map(n);
		}
		throw new Error(`msgpack: neznámý typ 0x${b.toString(16)}`);
	}
	return read();
}

// ──────────────────────────────────────────────────── Binární model (.rbxm) ──
// Záchranná cesta pluginu: když ve Studiu nejde přepsat vlastnost (typicky
// Source skriptu otevřeného v editoru se zapnutým Collaborative Editing), plugin
// si vyžádá celé instance jako model (/api/serialize) a vymění je. Dřív jsme to
// odmítali (400) a takové změny se tiše ztratily: ve Studiu zůstal mix starých
// a nových skriptů. Formát je Roblox Binary Model v0 (rbx-dom, docs/binary.md):
// složka → ObjectValue pojmenovaná id (Value = kopie) → kopie (Name, Source),
// přesně jako to dělá `rojo serve`.

// LZ4 blok jen s literály: platný LZ4, jen nic nezmenší (zápis je pak jednoduchý).
function lz4Literals(data) {
	const head = [];
	const length = data.length;
	head.push((Math.min(length, 15) << 4) & 0xff);
	if (length >= 15) {
		let rest = length - 15;
		while (rest >= 255) {
			head.push(255);
			rest -= 255;
		}
		head.push(rest);
	}
	return Buffer.concat([Buffer.from(head), data]);
}

function rbxmChunk(name, data, compress) {
	const header = Buffer.alloc(16);
	header.write(name, 0, 4, "latin1");
	const body = compress ? lz4Literals(data) : data;
	header.writeUInt32LE(compress ? body.length : 0, 4);
	header.writeUInt32LE(data.length, 8);
	return Buffer.concat([header, body]);
}

function rbxmString(text) {
	const bytes = Buffer.from(text, "utf8");
	const length = Buffer.alloc(4);
	length.writeUInt32LE(bytes.length, 0);
	return Buffer.concat([length, bytes]);
}

// Pole Int32: zigzag, big-endian, prokládané po bajtech; referenty navíc jako
// rozdíly od předchozího (čtou se sčítáním).
function rbxmInt32s(values, accumulate) {
	const n = values.length;
	const out = Buffer.alloc(n * 4);
	let previous = 0;
	values.forEach((value, i) => {
		const stored = accumulate ? value - previous : value;
		previous = value;
		const zigzag = ((stored << 1) ^ (stored >> 31)) >>> 0;
		out[i] = (zigzag >>> 24) & 0xff;
		out[i + n] = (zigzag >>> 16) & 0xff;
		out[i + 2 * n] = (zigzag >>> 8) & 0xff;
		out[i + 3 * n] = zigzag & 0xff;
	});
	return out;
}

function uint32LE(value) {
	const b = Buffer.alloc(4);
	b.writeUInt32LE(value, 0);
	return b;
}

// instances: [{ ref, className, parent (ref nebo -1), props: { jméno: { string } | { ref } } }]
function writeRbxm(instances) {
	const classes = [];
	const byClass = new Map();
	for (const instance of instances) {
		if (!byClass.has(instance.className)) {
			byClass.set(instance.className, []);
			classes.push(instance.className);
		}
		byClass.get(instance.className).push(instance);
	}
	const chunks = [];
	classes.forEach((className, classId) => {
		const members = byClass.get(className);
		chunks.push(rbxmChunk("INST", Buffer.concat([
			uint32LE(classId),
			rbxmString(className),
			Buffer.from([0]),
			uint32LE(members.length),
			rbxmInt32s(members.map((m) => m.ref), true),
		]), true));
	});
	classes.forEach((className, classId) => {
		const members = byClass.get(className);
		const names = [];
		for (const m of members) {
			for (const key of Object.keys(m.props)) {
				if (!names.includes(key)) names.push(key);
			}
		}
		for (const name of names) {
			const first = members.find((m) => m.props[name]).props[name];
			let type;
			let values;
			if ("ref" in first) {
				type = 0x13;
				values = rbxmInt32s(members.map((m) => (m.props[name] ? m.props[name].ref : -1)), true);
			} else {
				type = 0x01; // String; Source (ProtectedString) se v souboru ukládá stejně
				values = Buffer.concat(members.map((m) => rbxmString(m.props[name] ? m.props[name].string : "")));
			}
			chunks.push(rbxmChunk("PROP", Buffer.concat([uint32LE(classId), rbxmString(name), Buffer.from([type]), values]), true));
		}
	});
	chunks.push(rbxmChunk("PRNT", Buffer.concat([
		Buffer.from([0]),
		uint32LE(instances.length),
		rbxmInt32s(instances.map((m) => m.ref), true),
		rbxmInt32s(instances.map((m) => m.parent), true),
	]), true));
	chunks.push(rbxmChunk("END\0", Buffer.from("</roblox>", "latin1"), false));
	const header = Buffer.alloc(32);
	header.write("<roblox!", 0, 8, "latin1");
	Buffer.from([0x89, 0xff, 0x0d, 0x0a, 0x1a, 0x0a]).copy(header, 8);
	header.writeUInt16LE(0, 14);
	header.writeInt32LE(classes.length, 16);
	header.writeInt32LE(instances.length, 20);
	return Buffer.concat([header, ...chunks]);
}

// Odpověď na /api/serialize: kopie instancí stromu (bez dětí, ty plugin
// přestěhuje ze staré instance) pod ObjectValue pojmenovanými jejich id.
// Pořadí v PRNT je post-order (děti před rodiči), jak to chce Studio.
function serializeIds(tree, ids) {
	const instances = [];
	const root = { ref: 0, className: "Folder", parent: -1, props: { Name: { string: "Folder" } } };
	let next = 1;
	for (const id of ids) {
		const source = tree.instances[id];
		if (!source) {
			continue;
		}
		const holderRef = next++;
		const copyRef = next++;
		const props = { Name: { string: source.Name } };
		for (const [key, value] of Object.entries(source.Properties || {})) {
			if (value && typeof value.String === "string") {
				props[key] = { string: value.String };
			}
		}
		instances.push({ ref: copyRef, className: source.ClassName, parent: holderRef, props });
		instances.push({ ref: holderRef, className: "ObjectValue", parent: 0, props: { Name: { string: id }, Value: { ref: copyRef } } });
	}
	instances.push(root);
	return instances;
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
		// Každé Connect ve Studiu dostane přesně to, co je teď na disku. Strom
		// v paměti se jinak mění jen podle událostí watcheru, a ty se na Windows
		// při velkém `git pull` ztrácejí — Studio pak drželo mix starých a nových
		// skriptů a ani Disconnect / Connect to nespravilo.
		rescan();
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

	if (req.method === "POST" && urlPath === "/api/rojo-sync/stop") {
		// Druhé spuštění rojo-syncu převezme port: starý proces se tu ukončí.
		req.resume();
		req.on("end", () => {
			respond(res, 200, { sessionId });
			console.log("■ spuštěn nový rojo-sync — tenhle končí");
			setTimeout(() => process.exit(0), 100);
		});
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
		// Záchranná cesta pluginu (viz writeRbxm): co nešlo ve Studiu přepsat,
		// pošleme jako nové instance. Ref vlastnosti v našem stromu nejsou, takže
		// ref-patch je vždy prázdný.
		const chunks = [];
		req.on("data", (chunk) => chunks.push(chunk));
		req.on("end", () => {
			let ids = [];
			try {
				const body = decode(Buffer.concat(chunks));
				ids = Array.isArray(body && body.ids) ? body.ids.filter((id) => typeof id === "string") : [];
			} catch (err) {
				respond(res, 400, { kind: "BadRequest", details: `Bad request body: ${err.message}` });
				return;
			}
			if (urlPath === "/api/ref-patch") {
				respond(res, 200, { sessionId, patch: { removed: [], added: {}, updated: [] } });
				return;
			}
			const known = ids.filter((id) => tree.instances[id]);
			respond(res, 200, { sessionId, modelContents: writeRbxm(serializeIds(tree, known)) });
			const names = known.slice(0, 5).map((id) => tree.instances[id].Name).join(", ");
			console.log(`↺ Studio nešlo přepsat ${known.length} instancí (${names}${known.length > 5 ? ", …" : ""}) → poslány celé`);
		});
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

	// Doženeme, co plugin zmeškal. Každou zprávu zvlášť: plugin zprávy jednoho
	// paketu aplikuje za sebou bez pcall, takže chyba v jedné by zahodila i
	// všechny po ní (a s nimi změny skriptů).
	if (Number.isInteger(cursor) && cursor >= 0 && cursor < messages.length) {
		for (let index = cursor; index < messages.length; index++) {
			socket.write(
				frameBinary(
					encode({
						sessionId,
						packetType: "messages",
						body: { messageCursor: index + 1, messages: [messages[index]] },
					})
				)
			);
		}
	}
});

// ───────────────────────────────────────────────────────────── Sledování src ──

let pending = null;

// Vrací false, když se projekt nepodařilo přečíst (typicky uprostřed `git
// pull`: soubor zmizel mezi výpisem složky a čtením) — pojistka to pak zkusí znovu.
function rescan() {
	let next;
	try {
		next = buildTree();
	} catch (err) {
		console.error(`  ! chyba při čtení projektu: ${err.message}`);
		return false;
	}

	const patch = diffTrees(tree, next);
	tree = next;

	if (isEmptyPatch(patch)) {
		return true;
	}

	const parts = [];
	if (Object.keys(patch.added).length) parts.push(`+${Object.keys(patch.added).length}`);
	if (patch.removed.length) parts.push(`-${patch.removed.length}`);
	if (patch.updated.length) parts.push(`~${patch.updated.length}`);

	const pieces = splitPatch(patch);
	for (const piece of pieces) {
		broadcast(piece);
	}
	console.log(`↻ změna (${parts.join(" ")}) → odesláno do Studia${pieces.length > 1 ? ` v ${pieces.length} zprávách` : ""}`);
	return true;
}

// Velký patch (git pull změní desítky velkých skriptů naráz) Studio přes
// WebSocket nemusí převzít celý a tiše ho zahodí — pak ve Studiu zůstane mix
// starých a nových skriptů. Proto ho posíláme po kouscích: smazání zvlášť,
// každá změněná instance zvlášť a přidané instance po dávkách do ~256 kB.
//
// Přidaný PODSTROM (nová složka i se skripty, skript s dětmi, instance znovu
// vytvořená kvůli změně třídy) ale musí přijít celý v JEDNÉ zprávě: plugin
// staví novou instanci i s dětmi podle jejího seznamu Children a každé dítě
// hledá ve stejné zprávě. Dřív se dávky dělily podle hloubky, takže složka
// mohla přijít bez dětí → "Cannot reify an instance not present in
// virtualInstances", zpráva spadla, složka ve Studiu chyběla a její děti v další
// zprávě neměly rodiče (další chyba). Teď se dělí jen mezi celými podstromy.
const PIECE_BYTES = 256 * 1024;

function sizeOf(value) {
	try {
		return encode(value).length;
	} catch (err) {
		return PIECE_BYTES;
	}
}

// Přidané instance seskupené do celých podstromů: [{ ids, size }], každý
// podstrom od nejvyšší přidané instance (její rodič ve Studiu už je) dolů,
// rodič vždy před dětmi.
function addedSubtrees(added) {
	const units = [];
	const placed = new Set();
	for (const id of Object.keys(added)) {
		let top = id;
		while (added[added[top].Parent] && added[top].Parent !== top) {
			top = added[top].Parent;
		}
		if (placed.has(top)) {
			continue;
		}
		const ids = [];
		const visit = (current) => {
			if (placed.has(current) || !added[current]) {
				return;
			}
			placed.add(current);
			ids.push(current);
			for (const child of added[current].Children || []) {
				visit(child);
			}
		};
		visit(top);
		units.push({ ids, size: ids.reduce((sum, member) => sum + sizeOf(added[member]), 0) });
	}
	// Co by nebylo dosažitelné přes Children (nemělo by se stát), jde samo.
	for (const id of Object.keys(added)) {
		if (!placed.has(id)) {
			placed.add(id);
			units.push({ ids: [id], size: sizeOf(added[id]) });
		}
	}
	return units;
}

function splitPatch(patch) {
	const pieces = [];
	if (patch.removed.length) {
		pieces.push({ added: {}, removed: patch.removed, updated: [] });
	}
	let batch = {};
	let batchSize = 0;
	for (const unit of addedSubtrees(patch.added)) {
		if (batchSize > 0 && batchSize + unit.size > PIECE_BYTES) {
			pieces.push({ added: batch, removed: [], updated: [] });
			batch = {};
			batchSize = 0;
		}
		for (const id of unit.ids) {
			batch[id] = patch.added[id];
		}
		batchSize += unit.size;
	}
	if (batchSize > 0) {
		pieces.push({ added: batch, removed: [], updated: [] });
	}
	for (const update of patch.updated) {
		pieces.push({ added: {}, removed: [], updated: [update] });
	}
	return pieces.length ? pieces : [patch];
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
		// Bez jména chodí i přetečení bufferu (Windows, velký `git pull`):
		// změny se ztratily, takže radši přečteme všechno znovu.
		return true;
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

// Pojistka: i kdyby se nějaká událost ztratila, do pár vteřin se to srovná.
// Každých 5 s jen projdeme velikosti a časy souborů (levné) a celý strom
// čteme znovu, jen když se něco z toho pohnulo.
const POLL_MS = 5000;
let lastStamp = null;

function stampOf(diskPath, out) {
	let stat;
	try {
		stat = fs.statSync(diskPath);
	} catch (err) {
		out.push(`${diskPath}:-`);
		return;
	}
	out.push(`${diskPath}:${stat.mtimeMs}:${stat.size}`);
	if (stat.isDirectory()) {
		for (const entry of fs.readdirSync(diskPath).sort()) {
			if (!entry.startsWith(".")) {
				stampOf(path.join(diskPath, entry), out);
			}
		}
	}
}

function diskStamp() {
	const out = [];
	stampOf(PROJECT_FILE, out);
	const visit = (node) => {
		if (node.$path) {
			stampOf(path.resolve(PROJECT_ROOT, node.$path), out);
		}
		for (const [key, child] of Object.entries(node)) {
			if (!key.startsWith("$") && child && typeof child === "object") {
				visit(child);
			}
		}
	};
	try {
		visit(JSON.parse(fs.readFileSync(PROJECT_FILE, "utf8")).tree);
	} catch (err) {
		out.push("!project");
	}
	return out.join("\n");
}

// Razítko se zapamatuje, jen když se strom opravdu přečetl: dřív se uložilo
// předem a po nepovedeném čtení (uprostřed `git pull`) už se k témuž stavu
// disku pojistka nevrátila — Studio zůstalo se starými skripty.
function poll() {
	const stamp = diskStamp();
	if (stamp !== lastStamp && rescan()) {
		lastStamp = stamp;
	}
}

// Port drží jiný rojo-sync (typicky starý v jiném okně PowerShellu). Požádáme
// ho, ať skončí, a port převezmeme — jinak by Studio dál četlo jeho starý strom.
let listenTries = 0;

function askOldToStop(done) {
	const req = http.request(
		{ host: HOST, port: PORT, method: "POST", path: "/api/rojo-sync/stop", timeout: 2000 },
		(res) => {
			res.resume();
			done(res.statusCode === 200);
		}
	);
	req.on("timeout", () => req.destroy());
	req.on("error", () => done(false));
	req.end();
}

function portTaken() {
	console.error("");
	console.error(`  ! Port ${PORT} drží jiný rojo-sync (starý v jiném okně). Zavři ho Ctrl+C a spusť znovu.`);
	console.error("");
	process.exit(1);
}

server.on("error", (err) => {
	if (err.code !== "EADDRINUSE") {
		console.error(`  ! server spadl: ${err.message}`);
		process.exit(1);
	}
	listenTries += 1;
	if (listenTries > 3) {
		portTaken();
		return;
	}
	if (listenTries === 1) {
		console.log(`  port ${PORT} je obsazený — vypínám starý rojo-sync…`);
	}
	askOldToStop((stopped) => {
		if (!stopped && listenTries === 1) {
			portTaken();
			return;
		}
		setTimeout(() => server.listen(PORT, HOST), 500);
	});
});

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
	lastStamp = diskStamp();
	setInterval(poll, POLL_MS);
});
