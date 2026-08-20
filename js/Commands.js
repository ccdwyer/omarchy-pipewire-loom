.pragma library

// Build argv for the CLI backend. Mutations go through stock PipeWire tools.
// Move uses WirePlumber target metadata, never a raw pw-link.

function sanitizeSinkName(name) {
    var s = String(name || "Mix")
    var out = ""
    for (var i = 0; i < s.length && out.length < 32; i++) {
        var ch = s.charAt(i)
        if (/[A-Za-z0-9_-]/.test(ch))
            out += ch
    }
    if (!out)
        out = "Mix"
    if (out.indexOf("Loom-") === 0)
        return out
    return "Loom-" + out
}

function targetKey(node) {
    if (!node)
        return ""
    if (node.serial)
        return String(node.serial)
    if (node.name)
        return String(node.name)
    return ""
}

function move(streamId, targetKey) {
    var key = String(targetKey || "")
    return {
        primary: ["pw-metadata", "-n", "default", String(streamId), "target.object", key]
    }
}

function portLinkName(node, port) {
    // pw-link lists `node.name:port.name` (alsa_output.…:playback_FL), not the
    // human nick alias (`ALC1220 Digital:playback_FL`).
    var p = port && port.name ? String(port.name) : ""
    if (p.indexOf(":") >= 0)
        return p
    var n = node && node.name ? String(node.name) : ""
    if (n && p)
        return n + ":" + p
    if (port && port.alias)
        return String(port.alias)
    return ""
}

function linkPorts(fromId, toId, fromName, toName) {
    // Connect is `pw-link output input` by port name. `-I` is list-ids, not connect-by-id.
    if (fromName && toName)
        return {
            primary: ["pw-link", String(fromName), String(toName)],
            fallback: ["pw-link", String(fromId), String(toId)]
        }
    return { primary: ["pw-link", String(fromId), String(toId)] }
}

function unlinkPorts(fromId, toId) {
    return { primary: ["pw-link", "-d", String(fromId), String(toId)] }
}

function unlinkId(linkId) {
    return { primary: ["pw-link", "-d", String(linkId)] }
}

function clearTarget(streamId) {
    return { primary: ["pw-metadata", "-n", "default", "-d", String(streamId), "target.object"] }
}

function volume(nodeId, vol) {
    var v = Number(vol)
    if (!isFinite(v))
        v = 1
    if (v < 0)
        v = 0
    if (v > 1)
        v = 1
    return { primary: ["wpctl", "set-volume", String(nodeId), String(v)] }
}

function mute(nodeId, on) {
    return { primary: ["wpctl", "set-mute", String(nodeId), on ? "1" : "0"] }
}

function spawnSink(name) {
    var sinkName = sanitizeSinkName(name)
    return {
        sinkName: sinkName,
        primary: [
            "pactl",
            "load-module",
            "module-null-sink",
            "sink_name=" + sinkName,
            "sink_properties=device.description=" + sinkName
        ]
    }
}

function destroyModule(moduleId) {
    return { primary: ["pactl", "unload-module", String(moduleId)] }
}

function verifyDestroySink(name, moduleId, modules) {
    var n = String(name || "")
    if (n.indexOf("Loom-") !== 0)
        return { ok: false, err: "not a Loom sink" }
    if (moduleId === undefined || moduleId === null || String(moduleId).length === 0)
        return { ok: false, err: "missing module id" }
    var live = reconcileLoomModules(modules || [], false).adopted
    var want = String(moduleId)
    for (var i = 0; i < live.length; i++) {
        if (live[i].name === n && String(live[i].moduleId) === want)
            return { ok: true, err: "" }
    }
    return { ok: false, err: "moduleId is not that Loom null-sink" }
}

function listSinks() {
    return { primary: ["pactl", "list", "short", "sinks"] }
}

function listModules() {
    return { primary: ["pactl", "list", "short", "modules"] }
}

function dump() {
    return { primary: ["pw-dump"] }
}

function parsePactlShortSinks(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line)
            continue
        var cols = line.split(/\s+/)
        if (cols.length < 2)
            continue
        out.push({ index: cols[0], name: cols[1] })
    }
    return out
}

function parsePactlShortModules(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line)
            continue
        var cols = line.split(/\s+/)
        if (cols.length < 2)
            continue
        out.push({ id: cols[0], name: cols[1], argument: cols.slice(2).join(" ") })
    }
    return out
}

function loomSinks(sinks) {
    var out = []
    for (var i = 0; i < (sinks || []).length; i++) {
        if (String(sinks[i].name || "").indexOf("Loom-") === 0)
            out.push(sinks[i])
    }
    return out
}

function loomNameFromArgument(argument) {
    var arg = String(argument || "")
    var m = arg.match(/sink_name=([A-Za-z0-9_-]+)/)
    if (m && String(m[1]).indexOf("Loom-") === 0)
        return m[1]
    var parts = arg.split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
        var tok = parts[i]
        if (tok.indexOf("sink_name=") === 0)
            tok = tok.slice(10)
        if (tok.indexOf("Loom-") === 0)
            return tok
    }
    return ""
}

function loomModules(modules) {
    var out = []
    for (var i = 0; i < (modules || []).length; i++) {
        var m = modules[i]
        var blob = String(m.argument || "") + " " + String(m.name || "")
        if (blob.indexOf("Loom-") >= 0 && String(m.name || "").indexOf("module-null-sink") >= 0)
            out.push(m)
    }
    return out
}

function reconcileLoomModules(modules, destroy) {
    var live = loomModules(modules)
    var adopted = []
    for (var i = 0; i < live.length; i++) {
        var name = loomNameFromArgument(live[i].argument)
        if (!name)
            continue
        adopted.push({ name: name, moduleId: live[i].id })
    }
    return { adopted: adopted, destroy: !!destroy }
}

function argvFor(op, cmd) {
    if (op === "move") {
        var key = cmd.targetSerial || cmd.targetName
        if (!key)
            return null
        return move(cmd.stream, key)
    }
    if (op === "link" && cmd.from !== undefined && cmd.to !== undefined)
        return linkPorts(cmd.from, cmd.to, cmd.fromName, cmd.toName)
    if (op === "clearTarget")
        return clearTarget(cmd.stream)
    if (op === "unlink" && cmd.link !== undefined)
        return unlinkId(cmd.link)
    if (op === "unlink" && cmd.from !== undefined && cmd.to !== undefined)
        return unlinkPorts(cmd.from, cmd.to)
    if (op === "volume")
        return volume(cmd.node, cmd.vol)
    if (op === "mute" || op === "muteSubgraph")
        return mute(cmd.node, cmd.mute !== false)
    if (op === "spawnSink")
        return spawnSink(cmd.name)
    if (op === "destroySink" && cmd.moduleId !== undefined)
        return destroyModule(cmd.moduleId)
    if (op === "dump")
        return dump()
    return null
}
