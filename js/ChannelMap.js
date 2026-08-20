.pragma library

// Auto-map output ports of one node onto input ports of another.
// Spec: mono fan-out is allowed; mismatched counts (stereo→5.1 etc.) refuse.

function _chan(p) {
    if (!p)
        return ""
    return String(p.channel || p.name || "").toUpperCase()
}

function _outs(ports, nodeId) {
    var list = []
    for (var i = 0; i < ports.length; i++) {
        var p = ports[i]
        if (p.node === nodeId && p.dir === "out" && !p.monitor)
            list.push(p)
    }
    return list
}

function _ins(ports, nodeId) {
    var list = []
    for (var i = 0; i < ports.length; i++) {
        var p = ports[i]
        if (p.node === nodeId && p.dir === "in" && !p.monitor)
            list.push(p)
    }
    return list
}

function isMono(ports) {
    if (ports.length === 1)
        return true
    if (ports.length === 0)
        return false
    var name = _chan(ports[0])
    return name === "MONO" || name === "AUX0" || name === "FC"
}

function pairByName(fromPorts, toPorts) {
    var used = {}
    var pairs = []
    for (var i = 0; i < fromPorts.length; i++) {
        var want = _chan(fromPorts[i])
        var found = -1
        for (var j = 0; j < toPorts.length; j++) {
            if (used[j])
                continue
            if (_chan(toPorts[j]) === want && want) {
                found = j
                break
            }
        }
        if (found < 0)
            return null
        used[found] = true
        pairs.push({ from: fromPorts[i].id, to: toPorts[found].id, channel: want })
    }
    return pairs
}

function pairByIndex(fromPorts, toPorts) {
    var n = Math.min(fromPorts.length, toPorts.length)
    var pairs = []
    for (var i = 0; i < n; i++)
        pairs.push({ from: fromPorts[i].id, to: toPorts[i].id, channel: _chan(fromPorts[i]) || String(i) })
    return pairs
}

function fanOut(fromPorts, toPorts) {
    var pairs = []
    var src = fromPorts[0]
    for (var i = 0; i < toPorts.length; i++)
        pairs.push({ from: src.id, to: toPorts[i].id, channel: _chan(toPorts[i]) || "FAN" })
    return pairs
}

function autoMap(fromPorts, toPorts) {
    var from = fromPorts || []
    var to = toPorts || []
    if (from.length === 0 || to.length === 0)
        return { ok: false, reason: "ambiguous", detail: "no ports" }

    if (from.length === 1)
        return { ok: true, pairs: fanOut(from, to), mode: "fan-out" }

    if (from.length === to.length) {
        var named = pairByName(from, to)
        if (named)
            return { ok: true, pairs: named, mode: "name" }
        return { ok: true, pairs: pairByIndex(from, to), mode: "index" }
    }

    // Mismatched counts other than mono fan-out: refuse.
    // stereo→5.1, 5.1→stereo, 2→1, 6→2, etc.
    return {
        ok: false,
        reason: "ambiguous",
        detail: from.length + "→" + to.length,
        fromChannels: from.map(_chan),
        toChannels: to.map(_chan)
    }
}

function autoMapNodes(ports, fromNode, toNode) {
    return autoMap(_outs(ports, fromNode), _ins(ports, toNode))
}

function existingLink(links, fromId, toId) {
    for (var i = 0; i < links.length; i++) {
        if (links[i].from === fromId && links[i].to === toId)
            return links[i]
    }
    return null
}
