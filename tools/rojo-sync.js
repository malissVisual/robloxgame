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
 *   POST /api/serialize        → záchranná cesta pluginu: instance, které ve Studiu
 *                                nešly změnit, pošleme celé jako .rbxm (writeRbxm)
 *   POST /api/ref-patch        → k tomu Ref vlastnosti (u nás žádné: prázdný patch)
 *   POST /api/open/{id}        → "otevři skript v editoru"
 *   POST /api/rojo-sync/stop   → náš vlastní: nově spuštěný rojo-sync tím vypne starý
 *
 * Strom se čte z disku znovu při každém Connect ze Studia, při každé změně
 * v src/ a pro jistotu každých 5 s — po `git pull` už není potřeba nic
 * restartovat.
 *
 * SKRIPTY SE NEPŘEPISUJÍ, ALE VYTVÁŘEJÍ ZNOVU (8.7)
 * Plugin 7.7.0 zapisuje Source přes ScriptEditorService:UpdateSourceAsync
 * uvnitř task.spawn a hned hlásí úspěch (plugin/rbx_dom_lua/customProperties.lua).
 * Když se zápis do EXISTUJÍCÍHO skriptu ve Studiu nepovede nebo neprojeví,
 * plugin to nepozná: nic nehlásí, záchranná cesta /api/serialize se nespustí
 * a další Connect to zkusí stejnou cestou (hydrate podle jména + diff přes
 * GetEditorSource + stejný zápis). Tak ve Studiu třikrát zůstal mix starých
 * a nových skriptů. Spolehlivě fungovala jen NOVĚ vytvořená instance (smazat
 * Shared / Server / Client a Connect). Proto teď:
 *   - změněný skript posíláme jako update s changedClassName = jeho vlastní
 *     třída: plugin ho podle protokolu vytvoří znovu (Instance.new, Source,
 *     Parent — stejná cesta jako při tom ručním smazání), přestěhuje do něj
 *     děti a starou instanci odpojí;
 *   - po každém Connect takhle znovu vytvoříme VŠECHNY skripty, ať po hydrate
 *     a diffu zůstalo ve Studiu cokoli;
 *   - na konec každé dávky dáme kontrolní update s changedMetadata, který plugin
 *     použít neumí, takže si dotyčné skripty stáhne celé přes /api/serialize.
 *     Ten požadavek je potvrzení, že Studio dávku převzalo („✓ Studio
 *     převzalo …“); když nepřijde, terminál řekne, co dělat. Kontrolní jsou
 *     skripty nad PIECE_BYTES (Config, World, …), takže ty Studio dostane ještě
 *     jednou celé přes HTTP, nezávisle na WebSocketu.
 * Jen pro Studio v editaci: druhé souběžné spojení (Play test s Auto Connect)
 * dostává obyčejné přepsání, jinak by v běžící hře Script proběhl podruhé.
 * Přepínač --in-place vrátí staré chování (skripty jen přepisovat).
 *
 * Pozor na dvě pasti, na kterých se to jinak zasekne:
 *   1) Všechno je MessagePack, ne JSON.
 *   2) Instance má klíče PascalCase (Id, Parent, Name, ClassName, Properties,
 *      Children, Metadata), ale úplně všechno ostatní je camelCase.
 *
 * Spuštění:  node tools/rojo-sync.js                  (projekt default.project.json v kořeni)
 *            node tools/rojo-sync.js zombie-delivery  (jiný projekt: složka s vlastním default.project.json)
 *            node tools/rojo-sync.js zombie-delivery --in-place
 * Test:      node tools/rojo-sync.test.js
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");

// První argument bez "--" je složka projektu, přepínače mohou být kdekoli.
function parseArgs(argv) {
	const options = { project: null, inPlace: false, unknown: [] };
	for (const arg of argv) {
		if (arg === "--in-place") {
			options.inPlace = true;
		} else if (arg.startsWith("--")) {
			options.unknown.push(arg);
		} else if (!options.project) {
			options.project = arg;
		}
	}
	return options;
}

const OPTIONS = parseArgs(process.argv.slice(2));
const PROJECT_ROOT = OPTIONS.project ? path.resolve(OPTIONS.project) : path.resolve(__dirname, "..");
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
// Záchranná cesta pluginu: co z patche nešlo použít (instance, kterou nenašel
// nebo nevytvořil, vlastnost, kterou nejde zapsat, changedMetadata), si plugin
// vyžádá celé jako model (/api/serialize) a vymění to. Pozor: změnu Source tahle
// cesta NEZACHRÁNÍ — plugin 7.7.0 zápis Source vždy hlásí jako úspěšný (viz
// hlavička), takže ji sám nikdy nespustí. Používáme ji proto i úmyslně, jako
// potvrzení dávky (kontrolní update s changedMetadata, viz probeMessage).
// Formát je Roblox Binary Model v0 (rbx-dom, docs/binary.md): složka →
// ObjectValue pojmenovaná id (Value = kopie) → kopie (Name, Source), přesně
// jako to dělá `rojo serve`. Ověřeno nezávislým čtenářem v rojo-sync.test.js
// (i s 500 kB Source) a knihovnou rbx_binary, kterou čte `rojo serve`.

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
		console.warn(`  ! chybí ${path.relative(tree.projectRoot, diskPath)}`);
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
		const diskPath = path.resolve(tree.projectRoot, node.$path);
		tree.pathRoots.push(id);
		tree.scopes.push(path.relative(tree.projectRoot, diskPath).split(path.sep).join("/"));
		// Obsah $path složky se nalepí přímo na tenhle uzel.
		const temp = { instances: {}, projectRoot: tree.projectRoot };
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

// pathRoots: uzly s $path (u Zombie Delivery Shared, Server, Client) — ty radíme
// smazat, když Studio nepotvrdí změny; scopes: jejich složky relativně ke kořeni
// projektu, ať watcher pozná své soubory i při spuštění bez argumentu.
function buildTree(projectFile = PROJECT_FILE) {
	const project = JSON.parse(fs.readFileSync(projectFile, "utf8"));
	const tree = {
		instances: {},
		rootId: null,
		projectName: project.name || "Project",
		projectRoot: path.dirname(path.resolve(projectFile)),
		pathRoots: [],
		scopes: [],
	};
	tree.rootId = buildFromNode(tree, project.tree, "/", NULL_REF, project.name || "Project", true);
	return tree;
}

// "ReplicatedStorage.Shared" — cesta ve Studiu bez kořene DataModelu.
function fullName(tree, id) {
	const names = [];
	let current = tree.instances[id];
	while (current && current.Parent !== NULL_REF) {
		names.unshift(current.Name);
		current = tree.instances[current.Parent];
	}
	return names.join(".");
}

// Verze hry na disku (ModuleScript Config, řádek Version = "…"): terminál ji
// ukáže, ať se dá porovnat s tím, co hra po Play napíše do Output. Když je
// stará už tady, selhal `git pull`, ne synchronizace.
function diskVersion(tree) {
	for (const instance of Object.values(tree.instances)) {
		const source = instance.Properties.Source;
		if (instance.Name === "Config" && instance.ClassName === "ModuleScript" && source) {
			const match = /\bVersion\s*=\s*"([^"]+)"/.exec(source.String);
			if (match) {
				return match[1];
			}
		}
	}
	return null;
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

// ──────────────────────────────────────────────────────── Rozdělení patche ──

// Velký patch (git pull změní desítky velkých skriptů naráz) neposíláme jednou
// zprávou: smazání zvlášť, přidané instance po dávkách do ~256 kB a každý
// změněný skript zvlášť. Plugin zprávy jednoho paketu aplikuje za sebou a chyba
// v jedné by zahodila i ty po ní — proto i každý paket nese jen jednu zprávu.
//
// Přidaný PODSTROM (nová složka i se skripty, skript s dětmi, instance znovu
// vytvořená kvůli změně třídy) ale musí přijít celý v JEDNÉ zprávě: plugin
// staví novou instanci i s dětmi podle jejího seznamu Children a každé dítě
// hledá ve stejné zprávě. Dřív se dávky dělily podle hloubky, takže složka
// mohla přijít bez dětí → "Cannot reify an instance not present in
// virtualInstances", zpráva spadla, složka ve Studiu chyběla a její děti v další
// zprávě neměly rodiče (další chyba). Teď se dělí jen mezi celými podstromy.
//
// Instance znovu vytvořená kvůli změně třídy (foo.luau → foo.server.luau) má
// stejné id ve "removed" i v "added" — a to musí jet v TÉŽE zprávě: plugin ve
// zprávě nejdřív maže, pak přidává. Ve dvou zprávách by se mohly prohodit
// (náhled patche v pluginu umí uprostřed zprávy počkat na další snímek a mezitím
// se pustí další zpráva): přidání by se přeskočilo („už existuje“) a smazání pak
// instanci odstranilo úplně.
const PIECE_BYTES = 256 * 1024;

const SCRIPT_CLASSES = new Set(["Script", "LocalScript", "ModuleScript"]);

function isScript(instance) {
	return Boolean(instance) && SCRIPT_CLASSES.has(instance.ClassName);
}

function sourceBytes(instance) {
	const source = instance.Properties.Source;
	return source && typeof source.String === "string" ? Buffer.byteLength(source.String, "utf8") : 0;
}

function sizeOf(value) {
	try {
		return encode(value).length;
	} catch (err) {
		return PIECE_BYTES;
	}
}

// Update, po kterém plugin skript NEPŘEPÍŠE, ale vytvoří znovu. Pro plugin je to
// běžná změna třídy (tu posílá i `rojo serve`, když se ze souboru .luau stane
// .server.luau), jen na tutéž třídu: v applyPatch zavolá reifyInstance (nová
// instance, Name, všechny vlastnosti z changedProperties, Parent), přestěhuje
// do ní děti a starou dá na Parent = nil. Nová instance dostane jen vlastnosti
// z changedProperties, proto posíláme všechny (u nás jen Source).
function recreateUpdate(instance, changedName) {
	const update = {
		id: instance.Id,
		changedClassName: instance.ClassName,
		changedProperties: instance.Properties,
	};
	if (changedName !== undefined) {
		update.changedName = changedName;
	}
	return update;
}

// Přidané instance seskupené do celých podstromů: [{ ids, size, removed }],
// každý podstrom od nejvyšší přidané instance (její rodič ve Studiu už je) dolů,
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
		units.push({ ids, size: ids.reduce((sum, member) => sum + sizeOf(added[member]), 0), removed: [] });
	}
	// Co by nebylo dosažitelné přes Children (nemělo by se stát), jde samo.
	for (const id of Object.keys(added)) {
		if (!placed.has(id)) {
			placed.add(id);
			units.push({ ids: [id], size: sizeOf(added[id]), removed: [] });
		}
	}
	return units;
}

// tree = strom PO změně (z něj se berou celé vlastnosti znovu vytvářených
// skriptů); options.recreate = false je staré chování (--in-place).
function splitPatch(patch, tree, options) {
	const recreate = !options || options.recreate !== false;
	const pieces = [];
	const units = addedSubtrees(patch.added);

	const removedSet = new Set(patch.removed);
	const travelling = new Set();
	for (const unit of units) {
		if (removedSet.has(unit.ids[0])) {
			unit.removed.push(unit.ids[0]);
			travelling.add(unit.ids[0]);
		}
	}

	const removed = patch.removed.filter((id) => !travelling.has(id));
	if (removed.length) {
		pieces.push({ added: {}, removed, updated: [] });
	}

	let batch = {};
	let batchRemoved = [];
	let batchSize = 0;
	const flush = () => {
		if (batchSize > 0) {
			pieces.push({ added: batch, removed: batchRemoved, updated: [] });
		}
		batch = {};
		batchRemoved = [];
		batchSize = 0;
	};
	for (const unit of units) {
		if (batchSize > 0 && batchSize + unit.size > PIECE_BYTES) {
			flush();
		}
		for (const id of unit.ids) {
			batch[id] = patch.added[id];
		}
		batchRemoved.push(...unit.removed);
		batchSize += Math.max(unit.size, 1);
	}
	flush();

	for (const update of patch.updated) {
		const instance = tree && tree.instances[update.id];
		if (recreate && isScript(instance)) {
			pieces.push({ added: {}, removed: [], updated: [recreateUpdate(instance, update.changedName)] });
		} else {
			pieces.push({ added: {}, removed: [], updated: [update] });
		}
	}
	return pieces.length ? pieces : [patch];
}

// Po Connect: každý skript stromu znovu vytvořit, jeden skript = jedna zpráva.
function freshPieces(tree) {
	const pieces = [];
	for (const instance of Object.values(tree.instances)) {
		if (isScript(instance)) {
			pieces.push({ added: {}, removed: [], updated: [recreateUpdate(instance)] });
		}
	}
	return pieces;
}

// Skripty, které dávka posílá (přidané i znovu vytvořené / přepsané).
function scriptIdsOf(tree, pieces) {
	const ids = [];
	for (const piece of pieces) {
		for (const [id, instance] of Object.entries(piece.added)) {
			if (isScript(instance)) {
				ids.push(id);
			}
		}
		for (const update of piece.updated) {
			if (isScript(tree.instances[update.id])) {
				ids.push(update.id);
			}
		}
	}
	return ids;
}

// Kontrolní skripty dávky: všechny nad PIECE_BYTES (ty pak Studio dostane ještě
// jednou celé přes HTTP), jinak jen ten nejmenší (potvrzení skoro zadarmo).
function probeIds(tree, scriptIds) {
	const scripts = [...new Set(scriptIds)].map((id) => tree.instances[id]).filter(isScript);
	if (!scripts.length) {
		return [];
	}
	const big = scripts.filter((instance) => sourceBytes(instance) > PIECE_BYTES);
	if (big.length) {
		return big.map((instance) => instance.Id);
	}
	scripts.sort((a, b) => sourceBytes(a) - sourceBytes(b));
	return [scripts[0].Id];
}

// Kontrolní zpráva: update jen s changedMetadata (pravdivým — instance ho opravdu
// má). Plugin 7.7.0 metadata zapsat neumí („TODO: Support changing metadata“),
// vezme to jako nepoužitou změnu a — je-li v Rojo zapnutý Sync fallback, což je
// výchozí — si instance vyžádá přes /api/serialize a vymění je za kopie z .rbxm.
// Totéž dělá s metadaty, která posílá `rojo serve`. Požadavek je naše potvrzení.
function probeMessage(tree, ids) {
	return {
		added: {},
		removed: [],
		updated: ids.map((id) => ({
			id,
			changedProperties: {},
			changedMetadata: tree.instances[id].Metadata,
		})),
	};
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
let tree = null;
// Historie zpráv; každá ve dvou podobách: { recreate, inPlace } (viz níže).
const messages = [];

// HLAVNÍ spojení je první, které přijde, když žádné hlavní není: Studio
// v editaci. Spojení, které přijde, když hlavní ještě běží, je skoro jistě
// Play test (Rojo → Settings → Auto Connect Playtest Server: plugin v běžícím
// serveru se připojí jen tehdy, když je editace připojená) nebo druhé okno.
// Tam skripty NIKDY nevytváříme znovu — nový Script by v běžící hře proběhl
// podruhé — a neposíláme ani kontrolu; dostane jen obyčejné přepsání, jako
// od `rojo serve`.
function recreates(socket) {
	return socket.rojoPrimary && !OPTIONS.inPlace;
}

function instanceCount() {
	return Object.keys(tree.instances).length;
}

function formatBytes(bytes) {
	return bytes >= 1024 * 1024 ? `${(bytes / (1024 * 1024)).toFixed(1)} MB` : `${Math.ceil(bytes / 1024)} kB`;
}

function namesOf(ids) {
	const names = ids.slice(0, 5).map((id) => (tree.instances[id] ? tree.instances[id].Name : id));
	return names.join(", ") + (ids.length > 5 ? ", …" : "");
}

function packetFor(patch, cursor) {
	return frameBinary(
		encode({
			sessionId,
			packetType: "messages",
			body: { messageCursor: cursor, messages: [patch] },
		})
	);
}

function liveSockets() {
	for (const socket of sockets) {
		if (socket.destroyed) {
			sockets.delete(socket);
		}
	}
	return [...sockets];
}

function sendFrame(socket, frame) {
	try {
		socket.write(frame);
	} catch (err) {
		sockets.delete(socket);
	}
}

function primarySockets() {
	return liveSockets().filter((socket) => socket.rojoPrimary);
}

// Zpráva do historie (plugin, který se připojí s dřívějším kurzorem, ji dožene)
// a všem připojeným Studiím, každému v jeho podobě. Vrací velikost rámce
// v podobě pro hlavní spojení.
function broadcast(entry) {
	messages.push(entry);
	const frames = {};
	const frameOf = (key) => (frames[key] = frames[key] || packetFor(entry[key], messages.length));
	for (const socket of liveSockets()) {
		sendFrame(socket, frameOf(recreates(socket) ? "recreate" : "inPlace"));
	}
	return frameOf(OPTIONS.inPlace ? "inPlace" : "recreate").length;
}

// ─────────────────────────────────────────── Potvrzení od Studia (kontroly) ──
// Každá dávka skriptů končí kontrolní zprávou (probeMessage). Plugin na ni
// odpoví POST /api/serialize s jejími id — to je potvrzení, že dávku zpracoval.
// Když nepřijde, terminál to řekne a poradí, co udělat ve Studiu.

const ACK_BASE_MS = Number(process.env.ROJO_SYNC_ACK_MS || 15000); // test ho zkracuje
const ACK_PER_MB_MS = 3000;
const waiting = [];

function adviceLines() {
	const roots = tree.pathRoots.map((id) => fullName(tree, id)).filter(Boolean);
	return [
		"    Buď zprávy nedošly, nebo má Rojo ve Studiu vypnutý Sync fallback (Rojo → Settings), přes který potvrzuje.",
		"    Než dáš Play: Rojo → Disconnect, znovu Connect a počkej na „✓ Studio převzalo …“.",
		`    Když ani to nepomůže: Stop, Rojo → Disconnect, ve Studiu smaž ${roots.join(", ")}, pak Connect.`,
	];
}

function sendProbe(targets, ids, entry, bytes) {
	if (!ids.length || !targets.length) {
		return false;
	}
	const frame = packetFor(probeMessage(tree, ids), messages.length);
	for (const socket of targets) {
		sendFrame(socket, frame);
	}
	entry.ids = new Set(ids);
	entry.started = Date.now();
	entry.late = false;
	const wait = ACK_BASE_MS + Math.ceil(bytes / (1024 * 1024)) * ACK_PER_MB_MS;
	entry.timer = setTimeout(() => {
		entry.late = true;
		console.warn("");
		console.warn(`  ! Studio nepotvrdilo ${entry.label} ani po ${Math.round(wait / 1000)} s.`);
		for (const line of adviceLines()) {
			console.warn(line);
		}
		console.warn("");
	}, wait);
	waiting.push(entry);
	return true;
}

// Požadavek /api/serialize s těmito id: potvrdil některou dávku?
function acknowledge(ids) {
	const done = waiting.filter((entry) => ids.some((id) => entry.ids.has(id)));
	for (const entry of done) {
		clearTimeout(entry.timer);
		waiting.splice(waiting.indexOf(entry), 1);
		const seconds = ((Date.now() - entry.started) / 1000).toFixed(1);
		console.log(`✓ Studio převzalo ${entry.label} (za ${seconds} s${entry.late ? ", pozdě" : ""})${entry.after || ""}`);
	}
	return done.length > 0;
}

function forgetWaiting() {
	if (!waiting.length) {
		return;
	}
	for (const entry of waiting.splice(0)) {
		clearTimeout(entry.timer);
	}
	console.warn("✗ Studio se odpojilo dřív, než potvrdilo poslední změny — po Connect je dostane znovu.");
}

// Po Connect pošleme všechny skripty znovu (viz hlavička) a kontrolní zprávu.
function sendFresh(socket) {
	const pieces = freshPieces(tree);
	if (!pieces.length) {
		return;
	}
	let bytes = 0;
	let biggest = 0;
	for (const piece of pieces) {
		const frame = packetFor(piece, messages.length);
		bytes += frame.length;
		biggest = Math.max(biggest, frame.length);
		sendFrame(socket, frame);
	}
	const version = diskVersion(tree);
	const versionText = version ? `, verze ${version}` : "";
	console.log(
		`↻ Connect: všech ${pieces.length} skriptů posílám znovu jako nové instance ` +
			`(${pieces.length} zpráv, ${formatBytes(bytes)}, největší ${formatBytes(biggest)}${versionText})`
	);
	const ids = probeIds(tree, pieces.map((piece) => piece.updated[0].id));
	sendProbe([socket], ids, {
		label: `Connect: ${pieces.length} skriptů z disku${versionText}`,
		after: " — můžeš dát Play",
	}, bytes);
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

let warnedAboutWrites = false;

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
		const version = diskVersion(tree);
		console.log(`→ handshake (${instanceCount()} instancí${version ? `, verze na disku ${version}` : ""})`);
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
		if (!warnedAboutWrites) {
			warnedAboutWrites = true;
			console.warn("  ! Studio posílá změny zpět (Two-Way Sync v Rojo) — rojo-sync je nezapisuje, úpravy dělej na disku.");
		}
		return;
	}

	if (req.method === "POST" && urlPath.startsWith("/api/open/")) {
		req.resume();
		req.on("end", () => respond(res, 200, { sessionId }));
		return;
	}

	if (req.method === "POST" && (urlPath === "/api/serialize" || urlPath === "/api/ref-patch")) {
		// Záchranná cesta pluginu (viz writeRbxm): co nešlo použít, pošleme jako
		// nové instance. Ref vlastnosti v našem stromu nejsou, takže ref-patch je
		// vždy prázdný.
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
			const acked = acknowledge(ids);
			const missing = ids.filter((id) => !tree.instances[id]);
			if (missing.length) {
				// Jako `rojo serve` 7.7.0 (#1272): neúplný model by plugin stejně
				// odmítl („did not return the correct number of Instances“).
				respond(res, 400, { kind: "BadRequest", details: `provided id ${missing[0]} is not in the tree` });
				console.warn(`  ! Studio chtělo vyměnit ${missing.length} instancí, které na disku už nejsou — dej Disconnect a Connect.`);
				return;
			}
			respond(res, 200, { sessionId, modelContents: writeRbxm(serializeIds(tree, ids)) });
			if (!acked) {
				console.log(`↺ Studio nešlo použít změnu ${ids.length} instancí (${namesOf(ids)}) → poslány celé jako .rbxm`);
			}
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
	socket.rojoPrimary = primarySockets().length === 0;
	sockets.add(socket);
	handleClientFrames(socket);

	const closed = () => {
		if (!sockets.delete(socket)) {
			return;
		}
		console.log(socket.rojoPrimary ? "· Studio odpojeno" : "· druhé spojení odpojeno");
		if (socket.rojoPrimary && primarySockets().length === 0) {
			forgetWaiting();
		}
	};
	socket.on("close", closed);
	socket.on("error", closed);
	// HTTP server drží spojení napůl otevřená (allowHalfOpen): když Studio
	// zmizí bez zavíracího rámce, "close" by bez tohohle nepřišlo vůbec.
	socket.on("end", () => socket.end());

	console.log(
		socket.rojoPrimary
			? "✓ Studio připojeno"
			: "✓ Studio připojeno podruhé (Play test s Auto Connect, nebo druhé okno) — sem skripty jen přepisuju"
	);

	// Doženeme, co plugin zmeškal mezi čtením stromu a WebSocketem. Každou zprávu
	// zvlášť: plugin zprávy jednoho paketu aplikuje za sebou bez pcall, takže
	// chyba v jedné by zahodila i všechny po ní (a s nimi změny skriptů).
	if (Number.isInteger(cursor) && cursor >= 0 && cursor < messages.length) {
		for (let index = cursor; index < messages.length; index++) {
			const entry = messages[index];
			sendFrame(socket, packetFor(recreates(socket) ? entry.recreate : entry.inPlace, index + 1));
		}
	}

	if (recreates(socket)) {
		sendFresh(socket);
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
	const previousVersion = diskVersion(tree);
	tree = next;

	if (isEmptyPatch(patch)) {
		return true;
	}

	const parts = [];
	if (Object.keys(patch.added).length) parts.push(`+${Object.keys(patch.added).length}`);
	if (patch.removed.length) parts.push(`-${patch.removed.length}`);
	if (patch.updated.length) parts.push(`~${patch.updated.length}`);
	const what = `změna (${parts.join(" ")})`;

	// Obě podoby mají stejné kousky ve stejném pořadí (liší se jen updaty skriptů),
	// takže kurzor zprávy sedí pro hlavní spojení i pro Play test.
	const pieces = splitPatch(patch, tree, { recreate: true });
	const plain = splitPatch(patch, tree, { recreate: false });
	let bytes = 0;
	let biggest = 0;
	pieces.forEach((piece, index) => {
		const size = broadcast({ recreate: piece, inPlace: plain[index] });
		bytes += size;
		biggest = Math.max(biggest, size);
	});

	const version = diskVersion(tree);
	const versionText = version && version !== previousVersion ? `, verze na disku ${version}` : "";
	const targets = primarySockets();
	if (!targets.length) {
		const others = liveSockets().length ? " (jen do druhého spojení)" : "";
		console.log(`↻ ${what} — Studio v editaci není připojené${others}, dostane ji při Connect${versionText}`);
		return true;
	}

	const scripts = scriptIdsOf(tree, pieces);
	const recreated = OPTIONS.inPlace ? "" : scripts.length ? `, skripty znovu vytvořeny: ${namesOf([...new Set(scripts)])}` : "";
	console.log(
		`↻ ${what} → odesláno do Studia (${pieces.length} ${pieces.length === 1 ? "zpráva" : "zpráv"}, ${formatBytes(bytes)}` +
			`${biggest > PIECE_BYTES ? `, největší ${formatBytes(biggest)}` : ""}${recreated}${versionText})`
	);
	sendProbe(targets, probeIds(tree, scripts), { label: `změnu (${parts.join(" ")})` }, bytes);
	return true;
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

// Zajímají nás jen složky z $path v projektu a soubor projektu. fileName chodí
// relativně ke kořeni projektu, na Windows se zpětnými lomítky, a občas je null.
// (Dřív se tu natvrdo hlídalo "src/" — při spuštění bez argumentu, kdy jsou
// skripty v zombie-delivery/src, pak změny chytala jen 5s pojistka.)
function inScope(fileName, scopes) {
	if (!fileName) {
		// Bez jména chodí i přetečení bufferu (Windows, velký `git pull`):
		// změny se ztratily, takže radši přečteme všechno znovu.
		return true;
	}
	const normalized = fileName.split(path.sep).join("/");
	if (normalized === "default.project.json") {
		return true;
	}
	return scopes.some(
		(dir) =>
			dir === "" ||
			normalized === dir ||
			normalized.startsWith(`${dir}/`) ||
			dir.startsWith(`${normalized}/`) // smazaná nebo přejmenovaná nadřazená složka
	);
}

// Sledujeme kořen projektu, ne src — kořen nezmizí. Kdyby se sledovalo src
// a někdo ho smazal nebo přejmenoval, handle zůstane viset na neexistující
// složce a už se nic nedozvíme.
function watch() {
	let watcher = null;

	const attach = () => {
		try {
			watcher = fs.watch(PROJECT_ROOT, { recursive: true }, (eventType, fileName) => {
				if (inScope(fileName, tree.scopes)) {
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

function main() {
	for (const flag of OPTIONS.unknown) {
		console.warn(`  ! neznámý přepínač ${flag} — ignoruju ho (umím jen --in-place)`);
	}
	tree = buildTree();
	server.listen(PORT, HOST, () => {
		const version = diskVersion(tree);
		console.log("");
		console.log("  rojo-sync — náhrada rojo serve pro Roblox Studio");
		console.log(`  projekt:  ${tree.projectName}`);
		console.log(`  instancí: ${instanceCount()}`);
		if (version) {
			console.log(`  verze:    ${version} (Config.Version na disku)`);
		}
		console.log(`  adresa:   http://${HOST}:${PORT}`);
		console.log(
			OPTIONS.inPlace
				? "  režim:    --in-place (skripty se jen přepisují, jako před 8.7)"
				: "  režim:    skripty se po Connect i při změně vytvářejí znovu (--in-place to vypne)"
		);
		console.log("");
		console.log("  Ve Studiu: Plugins → Rojo → Connect, počkej na „✓ Studio převzalo …“, pak Play");
		console.log("");
		watch();
		lastStamp = diskStamp();
		setInterval(poll, POLL_MS);
	});
}

module.exports = {
	PIECE_BYTES,
	NULL_REF,
	parseArgs,
	encode,
	decode,
	lz4Literals,
	writeRbxm,
	serializeIds,
	buildTree,
	diffTrees,
	diskVersion,
	fullName,
	splitPatch,
	recreateUpdate,
	freshPieces,
	scriptIdsOf,
	probeIds,
	probeMessage,
	inScope,
};

if (require.main === module) {
	main();
}
