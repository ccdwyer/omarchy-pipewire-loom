.pragma library

function empty() {
    return {
        gen: 0,
        nodes: [],
        ports: [],
        links: [],
        defaults: { sink: null, source: null, sinkName: "", sourceName: "" },
        graph: { quantum: 1024, rate: 48000, latencyMs: 21.333 }
    }
}

function cloneGraph(g) {
    return {
        gen: g && g.gen ? g.gen : 0,
        nodes: (g && g.nodes ? g.nodes : []).slice(),
        ports: (g && g.ports ? g.ports : []).slice(),
        links: (g && g.links ? g.links : []).slice(),
        defaults: g && g.defaults ? shallow(g.defaults) : empty().defaults,
        graph: g && g.graph ? shallow(g.graph) : empty().graph
    }
}

function shallow(obj) {
    var o = {}
    if (!obj)
        return o
    var keys = Object.keys(obj)
    for (var i = 0; i < keys.length; i++)
        o[keys[i]] = obj[keys[i]]
    return o
}

function indexById(list) {
    var m = {}
    for (var i = 0; i < (list || []).length; i++)
        m[list[i].id] = list[i]
    return m
}

function applySnapshot(state, ev) {
    var next = empty()
    next.gen = ev.gen !== undefined ? ev.gen : ((state && state.gen) || 0) + 1
    next.nodes = (ev.nodes || []).slice()
    next.ports = (ev.ports || []).slice()
    next.links = (ev.links || []).slice()
    next.defaults = ev.defaults ? shallow(ev.defaults) : next.defaults
    next.graph = ev.graph ? shallow(ev.graph) : next.graph
    refreshDerived(next)
    return next
}

function applyDiff(state, ev) {
    if (!state)
        state = empty()
    if (ev.gen !== undefined && state.gen && ev.gen !== state.gen) {
        return { mismatch: true, state: state, want: ev.gen }
    }
    var next = cloneGraph(state)
    if (ev.gen !== undefined)
        next.gen = ev.gen
    next.nodes = applyList(next.nodes, ev.addNodes, ev.remNodes, ev.updNodes)
    next.ports = applyList(next.ports, ev.addPorts, ev.remPorts, ev.updPorts)
    next.links = applyList(next.links, ev.addLinks, ev.remLinks, ev.updLinks)
    if (ev.defaults)
        merge(next.defaults, ev.defaults)
    if (ev.graph)
        merge(next.graph, ev.graph)
    refreshDerived(next)
    return next
}

function applyList(list, add, rem, upd) {
    var out = list.slice()
    var i
    if (rem && rem.length) {
        var drop = {}
        for (i = 0; i < rem.length; i++)
            drop[rem[i]] = true
        var kept = []
        for (i = 0; i < out.length; i++) {
            if (!drop[out[i].id])
                kept.push(out[i])
        }
        out = kept
    }
    if (upd && upd.length) {
        var by = indexById(out)
        for (i = 0; i < upd.length; i++) {
            var u = upd[i]
            if (by[u.id])
                merge(by[u.id], u)
            else
                out.push(u)
        }
    }
    if (add && add.length) {
        var have = indexById(out)
        for (i = 0; i < add.length; i++) {
            if (have[add[i].id])
                merge(have[add[i].id], add[i])
            else
                out.push(add[i])
        }
    }
    return out
}

function merge(dst, src) {
    if (!dst || !src)
        return dst
    var keys = Object.keys(src)
    for (var i = 0; i < keys.length; i++)
        dst[keys[i]] = src[keys[i]]
    return dst
}

function refreshDerived(g) {
    var nodes = indexById(g.nodes)
    for (var i = 0; i < g.links.length; i++) {
        var l = g.links[i]
        var src = nodes[l.fromNode]
        var dst = nodes[l.toNode]
        l.live = !!(src && src.state === "running")
        l.muted = !!(src && src.mute) || !!(dst && dst.mute)
    }
    if (g.defaults && g.defaults.sink) {
        for (var n = 0; n < g.nodes.length; n++) {
            if (g.nodes[n].id === g.defaults.sink)
                g.nodes[n].isDefault = true
        }
    }
    return g
}

function applyEvent(state, ev) {
    if (!ev || !ev.t)
        return state || empty()
    if (ev.t === "snapshot")
        return applySnapshot(state, ev)
    if (ev.t === "diff") {
        var r = applyDiff(state, ev)
        if (r && r.mismatch)
            return r
        return r
    }
    if (ev.t === "storm")
        return state || empty()
    return state || empty()
}

function nodeEq(a, b) {
    if (!a || !b)
        return false
    return a.id === b.id && a.state === b.state && a.mute === b.mute
        && a.volume === b.volume && a.isDefault === b.isDefault
        && a.nick === b.nick && a.name === b.name && a.mediaClass === b.mediaClass
}

function portEq(a, b) {
    if (!a || !b)
        return false
    return a.id === b.id && a.node === b.node && a.dir === b.dir
        && a.channel === b.channel && a.monitor === b.monitor
}

function linkEq(a, b) {
    if (!a || !b)
        return false
    return a.id === b.id && a.from === b.from && a.to === b.to
        && a.kind === b.kind && a.live === b.live && a.muted === b.muted
}

function diffList(oldList, newList, eq) {
    var oldBy = indexById(oldList)
    var newBy = indexById(newList)
    var add = []
    var rem = []
    var upd = []
    var i
    for (i = 0; i < (newList || []).length; i++) {
        var n = newList[i]
        if (!oldBy[n.id])
            add.push(n)
        else if (!eq(oldBy[n.id], n))
            upd.push(n)
    }
    for (i = 0; i < (oldList || []).length; i++) {
        if (!newBy[oldList[i].id])
            rem.push(oldList[i].id)
    }
    return { add: add, rem: rem, upd: upd }
}

function diff(prev, next, gen, stormThreshold) {
    var a = prev || empty()
    var b = next || empty()
    var nd = diffList(a.nodes, b.nodes, nodeEq)
    var pd = diffList(a.ports, b.ports, portEq)
    var ld = diffList(a.links, b.links, linkEq)
    var n = nd.add.length + nd.rem.length + nd.upd.length
        + pd.add.length + pd.rem.length + pd.upd.length
        + ld.add.length + ld.rem.length + ld.upd.length
    var threshold = stormThreshold === undefined ? 10 : stormThreshold
    var nextGen = gen !== undefined ? gen : ((a.gen || 0) + (n ? 0 : 0))
    if (!prev || n > threshold) {
        var snapGen = (a.gen || 0) + 1
        return {
            storm: n > threshold && !!prev,
            event: {
                t: "snapshot",
                gen: snapGen,
                nodes: b.nodes,
                ports: b.ports,
                links: b.links,
                defaults: b.defaults,
                graph: b.graph
            },
            n: n
        }
    }
    if (n === 0) {
        var defaultsChanged = JSON.stringify(a.defaults || {}) !== JSON.stringify(b.defaults || {})
        if (!defaultsChanged)
            return { storm: false, event: null, n: 0 }
    }
    return {
        storm: false,
        event: {
            t: "diff",
            gen: a.gen || nextGen || 0,
            addNodes: nd.add,
            remNodes: nd.rem,
            updNodes: nd.upd,
            addPorts: pd.add,
            remPorts: pd.rem,
            updPorts: pd.upd,
            addLinks: ld.add,
            remLinks: ld.rem,
            updLinks: ld.upd,
            defaults: b.defaults,
            graph: b.graph
        },
        n: n
    }
}

function findNode(state, id) {
    var list = state && state.nodes ? state.nodes : []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id)
            return list[i]
    }
    return null
}

function findPort(state, id) {
    var list = state && state.ports ? state.ports : []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id)
            return list[i]
    }
    return null
}

function findLink(state, id) {
    var list = state && state.links ? state.links : []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id)
            return list[i]
    }
    return null
}

function hasSerial(state, id) {
    return !!(findNode(state, id) || findPort(state, id) || findLink(state, id))
}
