.pragma library

// Presentation-only filter. Simple view: playback/capture streams + hardware
// devices. No monitor ports, MIDI, video, or virtual-duplex noise.

function isSimpleNode(node) {
    if (!node)
        return false
    var k = node.kind
    if (k === "midi" || k === "video" || k === "other")
        return false
    if (k === "filter")
        return false
    var c = String(node.mediaClass || "")
    if (c.indexOf("Duplex") >= 0)
        return false
    if (c.indexOf("Monitor") >= 0)
        return false
    return k === "source" || k === "sink"
}

function isVisiblePort(port, nodeIds, simple) {
    if (!port)
        return false
    if (simple && port.monitor)
        return false
    if (!nodeIds[port.node])
        return false
    return true
}

function filter(graph, simple) {
    var g = graph || { nodes: [], ports: [], links: [] }
    if (!simple) {
        return {
            nodes: g.nodes || [],
            ports: (g.ports || []).filter(function (p) { return !p.monitor }),
            links: g.links || [],
            defaults: g.defaults || {},
            graph: g.graph || {}
        }
    }
    var nodes = []
    var nodeIds = {}
    var src = g.nodes || []
    for (var i = 0; i < src.length; i++) {
        if (isSimpleNode(src[i])) {
            nodes.push(src[i])
            nodeIds[src[i].id] = true
        }
    }
    var ports = []
    var portIds = {}
    var ps = g.ports || []
    for (var p = 0; p < ps.length; p++) {
        if (isVisiblePort(ps[p], nodeIds, true)) {
            ports.push(ps[p])
            portIds[ps[p].id] = true
        }
    }
    var links = []
    var ls = g.links || []
    for (var l = 0; l < ls.length; l++) {
        var link = ls[l]
        if (portIds[link.from] && portIds[link.to] && nodeIds[link.fromNode] && nodeIds[link.toNode])
            links.push(link)
    }
    return {
        nodes: nodes,
        ports: ports,
        links: links,
        defaults: g.defaults || {},
        graph: g.graph || {}
    }
}

function activeStreamCount(nodes) {
    var n = 0
    for (var i = 0; i < (nodes || []).length; i++) {
        var node = nodes[i]
        var c = String(node.mediaClass || "")
        if (c.indexOf("Stream/Output") === 0 && node.state === "running")
            n++
    }
    return n
}

function captureLive(nodes) {
    for (var i = 0; i < (nodes || []).length; i++) {
        var node = nodes[i]
        if (node.isCapture && node.state === "running")
            return true
        var c = String(node.mediaClass || "")
        if ((c.indexOf("Stream/Input") === 0 || c === "Audio/Source") && node.state === "running")
            return true
    }
    return false
}

function defaultSink(nodes, defaults) {
    if (defaults && defaults.sink) {
        for (var i = 0; i < (nodes || []).length; i++) {
            if (nodes[i].id === defaults.sink)
                return nodes[i]
        }
    }
    for (var j = 0; j < (nodes || []).length; j++) {
        if (nodes[j].isDefault && nodes[j].kind === "sink")
            return nodes[j]
    }
    return null
}
