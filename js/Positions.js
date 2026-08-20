.pragma library

// Best-effort user positions keyed by composite identity.
// identity = application.name + media.class + serial-order-within-app
// Bare node.name is unstable for Chrome/Electron streams.

function appOf(node) {
    if (!node)
        return "unknown"
    return String(node.app || node.nick || node.name || "unknown")
}

function identityOf(node, nodes) {
    if (!node)
        return "unknown||0"
    if (node.identity)
        return String(node.identity)
    var app = appOf(node)
    var cls = String(node.mediaClass || "")
    var peers = []
    var list = nodes || []
    for (var i = 0; i < list.length; i++) {
        var n = list[i]
        if (appOf(n) === app && String(n.mediaClass || "") === cls)
            peers.push(n)
    }
    peers.sort(function (a, b) {
        var sa = a.serial !== undefined ? a.serial : a.id
        var sb = b.serial !== undefined ? b.serial : b.id
        return sa - sb
    })
    var idx = 0
    for (var j = 0; j < peers.length; j++) {
        if (peers[j].id === node.id) {
            idx = j
            break
        }
    }
    return app + "|" + cls + "|" + idx
}

function stamp(nodes) {
    var list = nodes || []
    for (var i = 0; i < list.length; i++)
        list[i].identity = identityOf(list[i], list)
    return list
}

function emptyState() {
    return { version: 1, positions: {}, loomModules: {} }
}

function load(raw) {
    var data = raw
    if (typeof raw === "string") {
        try {
            data = JSON.parse(raw)
        } catch (e) {
            return emptyState()
        }
    }
    if (!data || typeof data !== "object")
        return emptyState()
    var pos = data.positions && typeof data.positions === "object" ? data.positions : {}
    var mods = data.loomModules && typeof data.loomModules === "object" ? data.loomModules : {}
    return { version: 1, positions: pos, loomModules: mods }
}

function serialize(state) {
    var s = state || emptyState()
    return JSON.stringify({
        version: 1,
        positions: s.positions || {},
        loomModules: s.loomModules || {}
    })
}

function get(state, identity) {
    if (!state || !state.positions || !identity)
        return null
    var p = state.positions[identity]
    if (!p)
        return null
    if (typeof p.x !== "number" || typeof p.y !== "number")
        return null
    return { x: p.x, y: p.y }
}

function set(state, identity, x, y) {
    var next = emptyState()
    var src = (state && state.positions) || {}
    var keys = Object.keys(src)
    for (var i = 0; i < keys.length; i++)
        next.positions[keys[i]] = src[keys[i]]
    next.loomModules = (state && state.loomModules) || {}
    if (identity && typeof x === "number" && typeof y === "number")
        next.positions[identity] = { x: x, y: y }
    return next
}

function clear(state, identity) {
    if (!state || !state.positions || !identity)
        return state
    delete state.positions[identity]
    return state
}
