.pragma library

// Coalesce at 30 Hz. More than 10 events in 100 ms → storm snapshot.

var HZ = 30
var TICK_MS = Math.round(1000 / HZ)
var WINDOW_MS = 100
var STORM_N = 10

function create() {
    return { times: [], pending: 0, lastFlush: 0, lastStorm: 0 }
}

function ingest(tracker, nowMs, n) {
    if (!tracker)
        tracker = create()
    var now = nowMs || Date.now()
    var add = n === undefined ? 1 : n
    for (var i = 0; i < add; i++)
        tracker.times.push(now)
    tracker.pending += add
    var cutoff = now - WINDOW_MS
    var kept = []
    for (var j = 0; j < tracker.times.length; j++) {
        if (tracker.times[j] >= cutoff)
            kept.push(tracker.times[j])
    }
    tracker.times = kept
    return tracker
}

function isStorm(tracker) {
    return !!(tracker && tracker.times && tracker.times.length > STORM_N)
}

function shouldFlush(tracker, nowMs) {
    var now = nowMs || Date.now()
    if (!tracker || tracker.pending <= 0)
        return false
    if (isStorm(tracker))
        return true
    return (now - (tracker.lastFlush || 0)) >= TICK_MS
}

function consume(tracker, nowMs) {
    var now = nowMs || Date.now()
    var storm = isStorm(tracker)
    var n = tracker ? tracker.pending : 0
    if (tracker) {
        tracker.pending = 0
        tracker.lastFlush = now
        if (storm) {
            tracker.lastStorm = now
            tracker.times = []
        }
    }
    return { storm: storm, n: n, windowMs: WINDOW_MS }
}

function eventCountInDiff(diff) {
    if (!diff)
        return 0
    function len(a) { return a && a.length ? a.length : 0 }
    return len(diff.addNodes) + len(diff.remNodes) + len(diff.updNodes)
        + len(diff.addPorts) + len(diff.remPorts) + len(diff.updPorts)
        + len(diff.addLinks) + len(diff.remLinks) + len(diff.updLinks)
}
