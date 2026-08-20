.pragma library

// BFS over the undirected link graph. Mute is applied to stream nodes only
// (wpctl set-mute), never to hardware devices.

function isStream(node) {
    if (!node)
        return false
    var c = String(node.mediaClass || "")
    return c.indexOf("Stream/") === 0
}

function neighbors(links, nodeId) {
    var out = []
    for (var i = 0; i < (links || []).length; i++) {
        var l = links[i]
        if (l.fromNode === nodeId)
            out.push(l.toNode)
        else if (l.toNode === nodeId)
            out.push(l.fromNode)
    }
    return out
}

function subgraph(nodes, links, startId) {
    var byId = {}
    for (var i = 0; i < (nodes || []).length; i++)
        byId[nodes[i].id] = nodes[i]
    if (!byId[startId])
        return []
    var seen = {}
    var queue = [startId]
    seen[startId] = true
    var order = []
    while (queue.length) {
        var id = queue.shift()
        order.push(id)
        var next = neighbors(links, id)
        for (var n = 0; n < next.length; n++) {
            if (seen[next[n]])
                continue
            if (!byId[next[n]])
                continue
            seen[next[n]] = true
            queue.push(next[n])
        }
    }
    return order
}

function streamIds(nodes, links, startId) {
    var ids = subgraph(nodes, links, startId)
    var byId = {}
    for (var i = 0; i < (nodes || []).length; i++)
        byId[nodes[i].id] = nodes[i]
    var streams = []
    for (var j = 0; j < ids.length; j++) {
        var node = byId[ids[j]]
        if (isStream(node))
            streams.push(ids[j])
    }
    return streams
}
