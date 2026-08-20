.pragma library

// Deterministic rank layout. Sources left, filters middle, sinks right.
// Vertical order by serial with collision nudging. User positions win.

var NODE_W = 196
var NODE_H = 88
var PORT_H = 24
var COL_GAP = 280
var ROW_GAP = 24
var ORIGIN_X = 48
var ORIGIN_Y = 48

function rankOf(kind) {
    if (kind === "source")
        return 0
    if (kind === "filter")
        return 1
    if (kind === "sink")
        return 2
    return 1
}

function nodeHeight(node) {
    var ins = (node && node.inCount) || 0
    var outs = (node && node.outCount) || 0
    var ports = Math.max(ins, outs, 1)
    return Math.max(NODE_H, 40 + ports * PORT_H)
}

function countPorts(node, ports) {
    var ins = 0
    var outs = 0
    for (var i = 0; i < (ports || []).length; i++) {
        var p = ports[i]
        if (p.node !== node.id || p.monitor)
            continue
        if (p.dir === "in")
            ins++
        else
            outs++
    }
    node.inCount = ins
    node.outCount = outs
    return node
}

function overlap(a, b) {
    return a.x < b.x + NODE_W && a.x + NODE_W > b.x
        && a.y < b.y + b.h && a.y + a.h > b.y
}

function layout(nodes, ports, positions) {
    var list = nodes || []
    var cols = [[], [], []]
    var i
    for (i = 0; i < list.length; i++) {
        countPorts(list[i], ports)
        var r = rankOf(list[i].kind)
        cols[r].push(list[i])
    }
    for (var c = 0; c < 3; c++) {
        cols[c].sort(function (a, b) {
            var sa = a.serial !== undefined ? a.serial : a.id
            var sb = b.serial !== undefined ? b.serial : b.id
            return sa - sb
        })
    }
    var placed = []
    var maxY = ORIGIN_Y
    var maxX = ORIGIN_X + COL_GAP * 2 + NODE_W
    for (c = 0; c < 3; c++) {
        var y = ORIGIN_Y
        for (i = 0; i < cols[c].length; i++) {
            var n = cols[c][i]
            var h = nodeHeight(n)
            var x = ORIGIN_X + c * COL_GAP
            var ident = n.identity
            var user = ident && positions && positions[ident] ? positions[ident] : null
            if (user && typeof user.x === "number" && typeof user.y === "number") {
                n.x = user.x
                n.y = user.y
                n.userPlaced = true
            } else {
                n.x = x
                n.y = y
                n.userPlaced = false
                y += h + ROW_GAP
            }
            n.w = NODE_W
            n.h = h
            // Collision nudge against already placed nodes in this pass.
            var guard = 0
            while (guard < 24) {
                var hit = false
                for (var p = 0; p < placed.length; p++) {
                    if (overlap(n, placed[p])) {
                        n.y = placed[p].y + placed[p].h + ROW_GAP
                        hit = true
                    }
                }
                if (!hit)
                    break
                guard++
            }
            placed.push({ x: n.x, y: n.y, h: n.h, id: n.id })
            if (n.y + h > maxY)
                maxY = n.y + h
            if (n.x + NODE_W > maxX)
                maxX = n.x + NODE_W
        }
    }
    return {
        nodes: list,
        width: maxX + ORIGIN_X,
        height: maxY + ORIGIN_Y
    }
}

function portAnchor(node, port, index, count, side) {
    var n = count < 1 ? 1 : count
    var idx = index < 0 ? 0 : index
    var top = (node.h - n * PORT_H) / 2
    if (top < 28)
        top = 28
    var y = node.y + top + idx * PORT_H + PORT_H / 2
    var x = side === "in" ? node.x : node.x + node.w
    return { x: x, y: y }
}

function indexOfPort(node, ports, portId, dir) {
    var idx = 0
    for (var i = 0; i < (ports || []).length; i++) {
        var p = ports[i]
        if (p.node !== node.id || p.monitor)
            continue
        if (p.dir !== dir)
            continue
        if (p.id === portId)
            return idx
        idx++
    }
    return 0
}

function countDir(node, ports, dir) {
    var n = 0
    for (var i = 0; i < (ports || []).length; i++) {
        if (ports[i].node === node.id && !ports[i].monitor && ports[i].dir === dir)
            n++
    }
    return n
}
