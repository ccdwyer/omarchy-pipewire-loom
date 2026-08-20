.pragma library

// NDJSON contract. Keep in lockstep with schema.md and src/loomd.

var SCHEMA_VERSION = 1

function commandId() {
    return Date.now().toString(16) + "-" + Math.floor(Math.random() * 0xffffffff).toString(16)
}

function parseLine(line) {
    var s = String(line || "").trim()
    if (!s)
        return null
    var obj
    try {
        obj = JSON.parse(s)
    } catch (e) {
        return { t: "err", err: "parse", msg: "invalid json" }
    }
    if (!obj || typeof obj !== "object" || Array.isArray(obj))
        return { t: "err", err: "parse", msg: "expected object" }
    if (!obj.t && !obj.op)
        return { t: "err", err: "parse", msg: "missing t" }
    return obj
}

function parseStream(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
        var ev = parseLine(lines[i])
        if (ev)
            out.push(ev)
    }
    return out
}

function isEvent(obj) {
    return !!(obj && obj.t)
}

function isCommand(obj) {
    return !!(obj && obj.op)
}

function isSnapshot(ev) {
    return !!(ev && ev.t === "snapshot")
}

function isDiff(ev) {
    return !!(ev && ev.t === "diff")
}

function isStorm(ev) {
    return !!(ev && ev.t === "storm")
}

function makeHello(backend, compat) {
    return {
        t: "hello",
        backend: backend || "cli",
        version: SCHEMA_VERSION,
        compat: !!compat
    }
}

function makeSnapshot(gen, graph) {
    return {
        t: "snapshot",
        gen: gen,
        nodes: (graph && graph.nodes) || [],
        ports: (graph && graph.ports) || [],
        links: (graph && graph.links) || [],
        defaults: (graph && graph.defaults) || {},
        graph: (graph && graph.graph) || {}
    }
}

function makeStorm(gen, n, windowMs) {
    return { t: "storm", gen: gen, n: n || 0, windowMs: windowMs || 100 }
}

function makeOk(id, op) {
    return { t: "ok", id: String(id || ""), op: op || "" }
}

function makeErr(id, op, err, msg) {
    var o = { t: "err", id: String(id || ""), op: op || "", err: err || "exec" }
    if (msg)
        o.msg = String(msg)
    return o
}

function makeToast(msg, level) {
    return { t: "toast", level: level || "info", msg: String(msg || "") }
}

function makeCommand(op, fields) {
    var cmd = { op: String(op || ""), id: commandId() }
    if (fields && typeof fields === "object") {
        var keys = Object.keys(fields)
        for (var i = 0; i < keys.length; i++)
            cmd[keys[i]] = fields[keys[i]]
    }
    return cmd
}

function line(obj) {
    return JSON.stringify(obj)
}
