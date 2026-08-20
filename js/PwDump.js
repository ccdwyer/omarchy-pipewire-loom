.pragma library

// Parse `pw-dump` JSON into the Loom graph schema. The CLI backend's
// guaranteed path: no libpipewire, just this.

function propsOf(item) {
    var p = {}
    if (!item || typeof item !== "object")
        return p
    if (item.props && typeof item.props === "object")
        copy(p, item.props)
    if (item.info && item.info.props && typeof item.info.props === "object")
        copy(p, item.info.props)
    return p
}

function copy(dst, src) {
    var keys = Object.keys(src)
    for (var i = 0; i < keys.length; i++)
        dst[keys[i]] = src[keys[i]]
}

function str(v, fallback) {
    if (v === undefined || v === null)
        return fallback || ""
    return String(v)
}

function num(v, fallback) {
    var n = Number(v)
    return isFinite(n) ? n : (fallback || 0)
}

function parseFraction(s) {
    var t = String(s || "")
    var m = t.match(/^(\d+)\s*\/\s*(\d+)/)
    if (!m)
        return null
    var q = Number(m[1])
    var r = Number(m[2])
    if (!q || !r)
        return null
    return { quantum: q, rate: r }
}

function parseNodeLatency(props, info) {
    var out = { quantum: 0, rate: 0 }
    if (props["clock.quantum"])
        out.quantum = num(props["clock.quantum"], 0)
    if (props["clock.rate"])
        out.rate = num(props["clock.rate"], 0)
    var frac = parseFraction(props["node.latency"] || props["process.latency"] || "")
    if (frac) {
        if (!out.quantum)
            out.quantum = frac.quantum
        if (!out.rate)
            out.rate = frac.rate
    }
    var params = info && info.params ? info.params : null
    if (params && params.Props) {
        var list = Array.isArray(params.Props) ? params.Props : [params.Props]
        for (var i = 0; i < list.length; i++) {
            var pr = list[i]
            if (!pr)
                continue
            var f2 = parseFraction(pr.latency || pr["node.latency"] || "")
            if (f2) {
                if (!out.quantum)
                    out.quantum = f2.quantum
                if (!out.rate)
                    out.rate = f2.rate
            }
        }
    }
    return out
}

function routeLatencyMs(src, dst, graph) {
    var gq = (graph && graph.quantum) || 1024
    var gr = (graph && graph.rate) || 48000
    var q = 0
    var r = 0
    if (src && src.quantum)
        q = src.quantum
    else if (dst && dst.quantum)
        q = dst.quantum
    if (src && src.rate)
        r = src.rate
    else if (dst && dst.rate)
        r = dst.rate
    if (!r)
        r = gr
    if (!q)
        return null
    if (q === gq && r === gr)
        return null
    return Math.round((q / r) * 1000 * 1000) / 1000
}

function classify(mediaClass) {
    var c = str(mediaClass)
    if (!c)
        return "other"
    if (c.indexOf("Midi") >= 0 || c.indexOf("MIDI") >= 0)
        return "midi"
    if (c.indexOf("Video") === 0)
        return "video"
    if (c.indexOf("Stream/Output") === 0 || c === "Audio/Source" || c.indexOf("Audio/Source/") === 0)
        return "source"
    if (c.indexOf("Stream/Input") === 0 || c === "Audio/Sink" || c.indexOf("Audio/Sink/") === 0)
        return "sink"
    if (c.indexOf("Audio/Duplex") === 0 || c.indexOf("Stream/Duplex") === 0)
        return "filter"
    if (c.indexOf("Audio/") === 0 || c.indexOf("Stream/") === 0)
        return "filter"
    return "other"
}

function parseState(info) {
    if (!info)
        return "unknown"
    var s = info.state
    if (typeof s === "string")
        return normalizeState(s)
    if (s && typeof s === "object")
        return normalizeState(s.name || s.state || "")
    return "unknown"
}

function normalizeState(s) {
    s = String(s || "").toLowerCase()
    if (s === "running" || s === "active")
        return "running"
    if (s === "idle")
        return "idle"
    if (s === "suspended" || s === "creating")
        return "suspended"
    if (s === "error")
        return "error"
    return s ? s : "unknown"
}

function avg(arr) {
    if (!arr || !arr.length)
        return 0
    var s = 0
    for (var i = 0; i < arr.length; i++)
        s += num(arr[i], 0)
    return s / arr.length
}

function cubeRoot(x) {
    if (x <= 0)
        return 0
    return Math.pow(x, 1 / 3)
}

function volumeFromProps(params) {
    if (!params)
        return { mute: false, volume: 1, channels: [] }
    var list = params.Props || params.props || []
    if (!Array.isArray(list))
        list = [list]
    var mute = false
    var volume = 1
    var channels = []
    for (var i = 0; i < list.length; i++) {
        var pr = list[i]
        if (!pr || typeof pr !== "object")
            continue
        if (pr.mute !== undefined)
            mute = !!pr.mute
        if (pr.channelVolumes && pr.channelVolumes.length) {
            volume = cubeRoot(avg(pr.channelVolumes))
        } else if (pr.volume !== undefined) {
            volume = num(pr.volume, 1)
            if (volume > 1)
                volume = cubeRoot(volume)
        }
        if (pr.channelMap && pr.channelMap.length)
            channels = pr.channelMap.slice()
    }
    if (volume < 0)
        volume = 0
    if (volume > 1)
        volume = 1
    return { mute: mute, volume: volume, channels: channels }
}

function isLoomName(name, nick) {
    var a = str(name)
    var b = str(nick)
    return a.indexOf("Loom-") === 0 || b.indexOf("Loom-") === 0
}

function parsePortChannel(props, name) {
    var ch = str(props["audio.channel"] || props["port.channel"] || "")
    if (ch)
        return ch.toUpperCase()
    var n = str(name)
    var m = n.match(/(FL|FR|FC|LFE|RL|RR|SL|SR|MONO|AUX\d+)$/i)
    if (m)
        return m[1].toUpperCase()
    if (/monitor/i.test(n))
        return "MON"
    if (/left/i.test(n))
        return "FL"
    if (/right/i.test(n))
        return "FR"
    return n ? n.toUpperCase() : ""
}

function parseMetadataValue(v) {
    if (v === undefined || v === null)
        return ""
    if (typeof v === "object")
        return str(v.name || v.value || "")
    var s = str(v)
    if (s.charAt(0) === "{") {
        try {
            var o = JSON.parse(s)
            return str(o.name || o.value || "")
        } catch (e) {
            return s
        }
    }
    return s
}

function itemType(item) {
    return str(item && item.type)
}

function parse(raw) {
    var data = raw
    if (typeof raw === "string") {
        try {
            data = JSON.parse(raw)
        } catch (e) {
            return emptyGraph()
        }
    }
    if (!Array.isArray(data))
        return emptyGraph()

    var nodes = []
    var ports = []
    var links = []
    var defaults = { sink: null, source: null, sinkName: "", sourceName: "" }
    var graph = { quantum: 1024, rate: 48000, latencyMs: 21.333 }
    var i

    for (i = 0; i < data.length; i++) {
        var item = data[i]
        var t = itemType(item)
        if (t === "PipeWire:Interface:Core" || t === "PipeWire:Interface:Profiler") {
            var cp = propsOf(item)
            if (cp["clock.rate"])
                graph.rate = num(cp["clock.rate"], graph.rate)
            if (cp["clock.quantum"])
                graph.quantum = num(cp["clock.quantum"], graph.quantum)
            if (cp["default.clock.rate"])
                graph.rate = num(cp["default.clock.rate"], graph.rate)
            if (cp["default.clock.quantum"])
                graph.quantum = num(cp["default.clock.quantum"], graph.quantum)
        }
        if (t === "PipeWire:Interface:Metadata") {
            var mdProps = propsOf(item)
            var mdName = str(mdProps["metadata.name"] || (item.props && item.props["metadata.name"]) || "")
            var entries = item.metadata || (item.info && item.info.props && item.info.props.metadata) || []
            if (!Array.isArray(entries))
                entries = []
            for (var m = 0; m < entries.length; m++) {
                var e = entries[m]
                var key = str(e.key || e.name)
                var val = parseMetadataValue(e.value)
                if (key === "default.audio.sink" || key === "default.configured.audio.sink")
                    defaults.sinkName = val
                if (key === "default.audio.source" || key === "default.configured.audio.source")
                    defaults.sourceName = val
            }
            // silence unused
            mdName = mdName
        }
    }

    for (i = 0; i < data.length; i++) {
        item = data[i]
        t = itemType(item)
        if (t !== "PipeWire:Interface:Node")
            continue
        var p = propsOf(item)
        var info = item.info || {}
        var mediaClass = str(p["media.class"])
        var vol = volumeFromProps(info.params)
        var name = str(p["node.name"])
        var nick = str(p["node.nick"] || p["node.description"] || p["application.name"] || name)
        var app = str(p["application.name"])
        var kind = classify(mediaClass)
        var node = {
            id: num(item.id, 0),
            serial: num(p["object.serial"] || p["node.id"] || item.id, item.id),
            name: name,
            nick: nick,
            app: app,
            mediaClass: mediaClass,
            kind: kind,
            state: parseState(info),
            mute: vol.mute,
            volume: vol.volume,
            isDefault: false,
            isCapture: mediaClass.indexOf("Stream/Input") === 0 || mediaClass === "Audio/Source" || mediaClass.indexOf("Audio/Source/") === 0,
            isLoom: isLoomName(name, nick),
            channels: vol.channels.slice(),
            identity: "",
            moduleId: p["pulse.module"] !== undefined ? num(p["pulse.module"], 0) : undefined,
            quantum: p["clock.quantum"] ? num(p["clock.quantum"], 0) : undefined,
            rate: p["clock.rate"] ? num(p["clock.rate"], 0) : undefined
        }
        var lat = parseNodeLatency(p, info)
        if (lat.quantum)
            node.quantum = lat.quantum
        if (lat.rate)
            node.rate = lat.rate
        nodes.push(node)
    }

    for (i = 0; i < nodes.length; i++) {
        if (defaults.sinkName && (nodes[i].name === defaults.sinkName || nodes[i].nick === defaults.sinkName)) {
            nodes[i].isDefault = true
            defaults.sink = nodes[i].id
        }
        if (defaults.sourceName && (nodes[i].name === defaults.sourceName || nodes[i].nick === defaults.sourceName)) {
            if (nodes[i].kind === "source" || nodes[i].mediaClass.indexOf("Audio/Source") === 0) {
                nodes[i].isDefault = nodes[i].isDefault || nodes[i].kind !== "sink"
                defaults.source = nodes[i].id
            }
        }
    }

    for (i = 0; i < data.length; i++) {
        item = data[i]
        t = itemType(item)
        if (t !== "PipeWire:Interface:Port")
            continue
        p = propsOf(item)
        info = item.info || {}
        var dirRaw = str(info.direction || p["port.direction"] || "")
        var dir = dirRaw.toLowerCase().indexOf("in") === 0 ? "in" : "out"
        var pname = str(p["port.name"] || p["port.alias"])
        var mon = p["port.monitor"] === true || p["port.monitor"] === "true" || /monitor/i.test(pname)
        ports.push({
            id: num(item.id, 0),
            node: num(p["node.id"] || info["node.id"], 0),
            name: pname,
            alias: str(p["port.alias"] || p["object.path"] || ""),
            dir: dir,
            channel: parsePortChannel(p, pname),
            monitor: !!mon,
            physical: p["port.physical"] === true || p["port.physical"] === "true"
        })
    }

    var nodeById = {}
    for (i = 0; i < nodes.length; i++)
        nodeById[nodes[i].id] = nodes[i]

    for (i = 0; i < ports.length; i++) {
        var owner = nodeById[ports[i].node]
        if (owner && ports[i].channel && owner.channels.indexOf(ports[i].channel) < 0 && !ports[i].monitor)
            owner.channels.push(ports[i].channel)
    }

    var portById = {}
    for (i = 0; i < ports.length; i++)
        portById[ports[i].id] = ports[i]

    for (i = 0; i < data.length; i++) {
        item = data[i]
        t = itemType(item)
        if (t !== "PipeWire:Interface:Link")
            continue
        info = item.info || {}
        p = propsOf(item)
        var fromPort = num(info["output-port-id"] || info.outputPortId || p["link.output.port"], 0)
        var toPort = num(info["input-port-id"] || info.inputPortId || p["link.input.port"], 0)
        var fromNode = num(info["output-node-id"] || info.outputNodeId || p["link.output.node"], 0)
        var toNode = num(info["input-node-id"] || info.inputNodeId || p["link.input.node"], 0)
        var fp = portById[fromPort]
        var tp = portById[toPort]
        if (fp && !fromNode)
            fromNode = fp.node
        if (tp && !toNode)
            toNode = tp.node
        var srcNode = nodeById[fromNode]
        var dstNode = nodeById[toNode]
        var raw = false
        var factory = str(p["factory.name"] || "")
        if (factory.indexOf("link") >= 0 && str(p["link.passive"]) === "")
            raw = false
        // Explicit pw-link vs session-manager route: PipeWire does not label
        // this cleanly. Heuristic: a link whose source is a stream and dest
        // is a device is a route; stream↔stream, filter taps, and Loom sinks
        // are raw/policy-fragile.
        var kind = "route"
        if (srcNode && dstNode) {
            var srcStream = String(srcNode.mediaClass || "").indexOf("Stream/") === 0
            var dstDevice = String(dstNode.mediaClass || "").indexOf("Audio/Sink") === 0
                || String(dstNode.mediaClass || "").indexOf("Audio/Source") === 0
            if (!(srcStream && dstDevice))
                kind = "raw"
            if (srcNode.isLoom || dstNode.isLoom)
                kind = "raw"
        }
        var live = !!(srcNode && srcNode.state === "running")
        var muted = !!(srcNode && srcNode.mute) || !!(dstNode && dstNode.mute)
        var latencyMs = routeLatencyMs(srcNode, dstNode, graph)
        links.push({
            id: num(item.id, 0),
            from: fromPort,
            to: toPort,
            fromNode: fromNode,
            toNode: toNode,
            kind: kind,
            live: live,
            muted: muted,
            latencyMs: latencyMs
        })
    }

    if (graph.rate > 0 && graph.quantum > 0)
        graph.latencyMs = Math.round((graph.quantum / graph.rate) * 1000 * 1000) / 1000

    stampIdentities(nodes)

    return {
        nodes: nodes,
        ports: ports,
        links: links,
        defaults: defaults,
        graph: graph
    }
}

function stampIdentities(nodes) {
    var groups = {}
    var i
    for (i = 0; i < nodes.length; i++) {
        var key = (nodes[i].app || nodes[i].name || "unknown") + "|" + (nodes[i].mediaClass || "")
        if (!groups[key])
            groups[key] = []
        groups[key].push(nodes[i])
    }
    var keys = Object.keys(groups)
    for (i = 0; i < keys.length; i++) {
        var peers = groups[keys[i]]
        peers.sort(function (a, b) { return a.serial - b.serial })
        for (var j = 0; j < peers.length; j++)
            peers[j].identity = keys[i] + "|" + j
    }
}

function emptyGraph() {
    return {
        nodes: [],
        ports: [],
        links: [],
        defaults: { sink: null, source: null, sinkName: "", sourceName: "" },
        graph: { quantum: 1024, rate: 48000, latencyMs: 21.333 }
    }
}
