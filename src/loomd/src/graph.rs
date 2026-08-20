use crate::schema::{Defaults, Graph, GraphInfo, Link, Node, Port};
use serde_json::Value;

pub fn classify(media_class: &str) -> &'static str {
    let c = media_class;
    if c.contains("Midi") || c.contains("MIDI") {
        return "midi";
    }
    if c.starts_with("Video") {
        return "video";
    }
    if c.starts_with("Stream/Output") || c == "Audio/Source" || c.starts_with("Audio/Source/") {
        return "source";
    }
    if c.starts_with("Stream/Input") || c == "Audio/Sink" || c.starts_with("Audio/Sink/") {
        return "sink";
    }
    if c.contains("Duplex") {
        return "filter";
    }
    if c.starts_with("Audio/") || c.starts_with("Stream/") {
        return "filter";
    }
    "other"
}

pub fn is_loom_name(name: &str, nick: &str) -> bool {
    name.starts_with("Loom-") || nick.starts_with("Loom-")
}

pub fn parse_state(info: &Value) -> String {
    let s = info.get("state");
    let raw = match s {
        Some(Value::String(t)) => t.as_str(),
        Some(Value::Object(o)) => o
            .get("name")
            .or_else(|| o.get("state"))
            .and_then(|v| v.as_str())
            .unwrap_or(""),
        _ => "",
    };
    match raw.to_ascii_lowercase().as_str() {
        "running" | "active" => "running".into(),
        "idle" => "idle".into(),
        "suspended" | "creating" => "suspended".into(),
        "error" => "error".into(),
        other if !other.is_empty() => other.into(),
        _ => "unknown".into(),
    }
}

fn props_of(item: &Value) -> serde_json::Map<String, Value> {
    let mut p = serde_json::Map::new();
    if let Some(obj) = item.get("props").and_then(|v| v.as_object()) {
        for (k, v) in obj {
            p.insert(k.clone(), v.clone());
        }
    }
    if let Some(obj) = item
        .pointer("/info/props")
        .and_then(|v| v.as_object())
    {
        for (k, v) in obj {
            p.insert(k.clone(), v.clone());
        }
    }
    p
}

fn prop_str(p: &serde_json::Map<String, Value>, key: &str) -> String {
    p.get(key)
        .and_then(|v| v.as_str().map(|s| s.to_string()).or_else(|| {
            if v.is_number() || v.is_boolean() {
                Some(v.to_string())
            } else {
                None
            }
        }))
        .unwrap_or_default()
}

fn prop_u32(p: &serde_json::Map<String, Value>, key: &str) -> Option<u32> {
    p.get(key).and_then(|v| {
        v.as_u64()
            .map(|n| n as u32)
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    })
}

fn prop_bool(p: &serde_json::Map<String, Value>, key: &str) -> bool {
    match p.get(key) {
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => s == "true" || s == "1",
        Some(Value::Number(n)) => n.as_u64() == Some(1),
        _ => false,
    }
}

fn parse_meta_name(v: &Value) -> String {
    match v {
        Value::String(s) => {
            if s.starts_with('{') {
                serde_json::from_str::<Value>(s)
                    .ok()
                    .and_then(|o| {
                        o.get("name")
                            .or_else(|| o.get("value"))
                            .and_then(|x| x.as_str())
                            .map(|t| t.to_string())
                    })
                    .unwrap_or_else(|| s.clone())
            } else {
                s.clone()
            }
        }
        Value::Object(o) => o
            .get("name")
            .or_else(|| o.get("value"))
            .and_then(|x| x.as_str())
            .unwrap_or("")
            .to_string(),
        _ => String::new(),
    }
}

fn volume_from_params(info: &Value) -> (bool, f64, Vec<String>) {
    let list = info
        .pointer("/params/Props")
        .or_else(|| info.pointer("/params/props"))
        .cloned()
        .unwrap_or(Value::Array(vec![]));
    let arr = match list {
        Value::Array(a) => a,
        other => vec![other],
    };
    let mut mute = false;
    let mut volume = 1.0;
    let mut channels = Vec::new();
    for pr in arr {
        if let Some(m) = pr.get("mute").and_then(|v| v.as_bool()) {
            mute = m;
        }
        if let Some(vols) = pr.get("channelVolumes").and_then(|v| v.as_array()) {
            let sum: f64 = vols.iter().filter_map(|x| x.as_f64()).sum();
            let n = vols.len().max(1) as f64;
            volume = (sum / n).cbrt();
        } else if let Some(v) = pr.get("volume").and_then(|x| x.as_f64()) {
            volume = if v > 1.0 { v.cbrt() } else { v };
        }
        if let Some(map) = pr.get("channelMap").and_then(|v| v.as_array()) {
            channels = map
                .iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect();
        }
    }
    volume = volume.clamp(0.0, 1.0);
    (mute, volume, channels)
}

fn parse_channel(p: &serde_json::Map<String, Value>, name: &str) -> String {
    let ch = prop_str(p, "audio.channel");
    if !ch.is_empty() {
        return ch.to_ascii_uppercase();
    }
    let upper = name.to_ascii_uppercase();
    for tag in ["FL", "FR", "FC", "LFE", "RL", "RR", "SL", "SR", "MONO"] {
        if upper.ends_with(tag) {
            return tag.into();
        }
    }
    if upper.contains("LEFT") {
        return "FL".into();
    }
    if upper.contains("RIGHT") {
        return "FR".into();
    }
    upper
}

fn stamp_identities(nodes: &mut [Node]) {
    let mut keys: Vec<(String, u32, usize)> = nodes
        .iter()
        .enumerate()
        .map(|(i, n)| {
            let app = if n.app.is_empty() {
                n.name.clone()
            } else {
                n.app.clone()
            };
            (format!("{}|{}", app, n.media_class), n.serial, i)
        })
        .collect();
    keys.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    let mut last = String::new();
    let mut idx = 0u32;
    for (key, _, i) in keys {
        if key != last {
            idx = 0;
            last = key.clone();
        }
        nodes[i].identity = format!("{}|{}", key, idx);
        idx += 1;
    }
}

pub fn parse_pw_dump(raw: &str) -> Graph {
    let data: Value = serde_json::from_str(raw).unwrap_or(Value::Array(vec![]));
    parse_pw_value(&data)
}

pub fn parse_pw_value(data: &Value) -> Graph {
    let items = match data {
        Value::Array(a) => a,
        _ => return Graph::default(),
    };
    let mut graph = Graph {
        graph: GraphInfo::default(),
        ..Graph::default()
    };
    let mut defaults = Defaults::default();

    for item in items {
        let t = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if t == "PipeWire:Interface:Core" || t == "PipeWire:Interface:Profiler" {
            let p = props_of(item);
            if let Some(r) = prop_u32(&p, "clock.rate").or_else(|| prop_u32(&p, "default.clock.rate")) {
                graph.graph.rate = r;
            }
            if let Some(q) = prop_u32(&p, "clock.quantum").or_else(|| prop_u32(&p, "default.clock.quantum"))
            {
                graph.graph.quantum = q;
            }
        }
        if t == "PipeWire:Interface:Metadata" {
            if let Some(entries) = item.get("metadata").and_then(|v| v.as_array()) {
                for e in entries {
                    let key = e.get("key").and_then(|v| v.as_str()).unwrap_or("");
                    let val = e.get("value").map(parse_meta_name).unwrap_or_default();
                    if key == "default.audio.sink" || key == "default.configured.audio.sink" {
                        defaults.sink_name = val;
                    } else if key == "default.audio.source" || key == "default.configured.audio.source"
                    {
                        defaults.source_name = val;
                    }
                }
            }
        }
    }

    for item in items {
        let t = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if t != "PipeWire:Interface:Node" {
            continue;
        }
        let p = props_of(item);
        let info = item.get("info").cloned().unwrap_or(Value::Object(Default::default()));
        let media = prop_str(&p, "media.class");
        let (mute, volume, channels) = volume_from_params(&info);
        let name = prop_str(&p, "node.name");
        let nick = {
            let n = prop_str(&p, "node.nick");
            if !n.is_empty() {
                n
            } else {
                let d = prop_str(&p, "node.description");
                if !d.is_empty() {
                    d
                } else {
                    let a = prop_str(&p, "application.name");
                    if !a.is_empty() {
                        a
                    } else {
                        name.clone()
                    }
                }
            }
        };
        let app = prop_str(&p, "application.name");
        let id = item.get("id").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let serial = prop_u32(&p, "object.serial").unwrap_or(id);
        let kind = classify(&media).to_string();
        let is_capture = media.starts_with("Stream/Input")
            || media == "Audio/Source"
            || media.starts_with("Audio/Source/");
        graph.nodes.push(Node {
            id,
            serial,
            name: name.clone(),
            nick: nick.clone(),
            app,
            media_class: media,
            kind,
            state: parse_state(&info),
            mute,
            volume,
            is_default: false,
            is_capture,
            is_loom: is_loom_name(&name, &nick),
            channels,
            identity: String::new(),
            module_id: prop_u32(&p, "pulse.module"),
        });
    }

    for n in &mut graph.nodes {
        if !defaults.sink_name.is_empty()
            && (n.name == defaults.sink_name || n.nick == defaults.sink_name)
        {
            n.is_default = true;
            defaults.sink = Some(n.id);
        }
        if !defaults.source_name.is_empty()
            && (n.name == defaults.source_name || n.nick == defaults.source_name)
            && n.kind == "source"
        {
            defaults.source = Some(n.id);
        }
    }
    graph.defaults = defaults;

    for item in items {
        let t = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if t != "PipeWire:Interface:Port" {
            continue;
        }
        let p = props_of(item);
        let info = item.get("info").cloned().unwrap_or(Value::Object(Default::default()));
        let dir_raw = info
            .get("direction")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        let dir = if dir_raw.starts_with("in") {
            "in"
        } else {
            "out"
        };
        let name = {
            let n = prop_str(&p, "port.name");
            if n.is_empty() {
                prop_str(&p, "port.alias")
            } else {
                n
            }
        };
        let monitor = prop_bool(&p, "port.monitor") || name.to_ascii_lowercase().contains("monitor");
        let id = item.get("id").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let node = prop_u32(&p, "node.id").unwrap_or(0);
        graph.ports.push(Port {
            id,
            node,
            channel: parse_channel(&p, &name),
            name,
            dir: dir.into(),
            monitor,
            physical: prop_bool(&p, "port.physical"),
        });
    }

    for item in items {
        let t = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if t != "PipeWire:Interface:Link" {
            continue;
        }
        let p = props_of(item);
        let info = item.get("info").cloned().unwrap_or(Value::Object(Default::default()));
        let from = info
            .get("output-port-id")
            .or_else(|| p.get("link.output.port"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as u32;
        let to = info
            .get("input-port-id")
            .or_else(|| p.get("link.input.port"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as u32;
        let from_node = info
            .get("output-node-id")
            .or_else(|| p.get("link.output.node"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as u32;
        let to_node = info
            .get("input-node-id")
            .or_else(|| p.get("link.input.node"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as u32;
        let src = graph.nodes.iter().find(|n| n.id == from_node);
        let dst = graph.nodes.iter().find(|n| n.id == to_node);
        let mut kind = "route".to_string();
        if let (Some(s), Some(d)) = (src, dst) {
            let src_stream = s.media_class.starts_with("Stream/");
            let dst_dev = d.media_class.starts_with("Audio/Sink")
                || d.media_class.starts_with("Audio/Source");
            if !(src_stream && dst_dev) {
                kind = "raw".into();
            }
            if s.is_loom || d.is_loom {
                kind = "raw".into();
            }
        }
        let live = src.map(|s| s.state == "running").unwrap_or(false);
        let muted = src.map(|s| s.mute).unwrap_or(false) || dst.map(|d| d.mute).unwrap_or(false);
        let id = item.get("id").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        graph.links.push(Link {
            id,
            from,
            to,
            from_node,
            to_node,
            kind,
            live,
            muted,
            latency_ms: None,
        });
    }

    if graph.graph.rate > 0 {
        graph.graph.latency_ms =
            ((graph.graph.quantum as f64 / graph.graph.rate as f64) * 1000.0 * 1000.0).round()
                / 1000.0;
    }
    stamp_identities(&mut graph.nodes);
    graph
}

#[derive(Debug, Clone)]
pub struct Pair {
    pub from: u32,
    pub to: u32,
}

pub fn auto_map(from: &[Port], to: &[Port]) -> Result<Vec<Pair>, String> {
    if from.is_empty() || to.is_empty() {
        return Err("no ports".into());
    }
    if from.len() == 1 {
        return Ok(to
            .iter()
            .map(|p| Pair {
                from: from[0].id,
                to: p.id,
            })
            .collect());
    }
    if from.len() == to.len() {
        let mut used = vec![false; to.len()];
        let mut pairs = Vec::new();
        let mut named = true;
        for f in from {
            let want = f.channel.to_ascii_uppercase();
            let found = to.iter().enumerate().find(|(j, p)| {
                !used[*j] && !want.is_empty() && p.channel.to_ascii_uppercase() == want
            });
            if let Some((j, p)) = found {
                used[j] = true;
                pairs.push(Pair {
                    from: f.id,
                    to: p.id,
                });
            } else {
                named = false;
                break;
            }
        }
        if named {
            return Ok(pairs);
        }
        return Ok(from
            .iter()
            .zip(to.iter())
            .map(|(f, t)| Pair {
                from: f.id,
                to: t.id,
            })
            .collect());
    }
    Err(format!("{}→{}", from.len(), to.len()))
}

pub fn node_ports<'a>(ports: &'a [Port], node: u32, dir: &str) -> Vec<&'a Port> {
    ports
        .iter()
        .filter(|p| p.node == node && p.dir == dir && !p.monitor)
        .collect()
}

pub fn stream_ids(graph: &Graph, start: u32) -> Vec<u32> {
    use std::collections::{HashSet, VecDeque};
    let have: HashSet<u32> = graph.nodes.iter().map(|n| n.id).collect();
    if !have.contains(&start) {
        return vec![];
    }
    let mut seen = HashSet::new();
    let mut q = VecDeque::new();
    q.push_back(start);
    seen.insert(start);
    while let Some(id) = q.pop_front() {
        for l in &graph.links {
            let nxt = if l.from_node == id {
                Some(l.to_node)
            } else if l.to_node == id {
                Some(l.from_node)
            } else {
                None
            };
            if let Some(n) = nxt {
                if have.contains(&n) && seen.insert(n) {
                    q.push_back(n);
                }
            }
        }
    }
    let mut streams: Vec<u32> = graph
        .nodes
        .iter()
        .filter(|n| seen.contains(&n.id) && n.media_class.starts_with("Stream/"))
        .map(|n| n.id)
        .collect();
    if streams.is_empty() {
        streams.push(start);
    }
    streams
}

pub fn sanitize_sink_name(name: &str) -> String {
    let mut out = String::new();
    for ch in name.chars() {
        if out.len() >= 32 {
            break;
        }
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            out.push(ch);
        }
    }
    if out.is_empty() {
        out = "Mix".into();
    }
    if out.starts_with("Loom-") {
        out
    } else {
        format!("Loom-{out}")
    }
}

pub fn change_count(a: &Graph, b: &Graph) -> usize {
    fn ids(list: &[u32]) -> std::collections::HashSet<u32> {
        list.iter().copied().collect()
    }
    let an: Vec<u32> = a.nodes.iter().map(|n| n.id).collect();
    let bn: Vec<u32> = b.nodes.iter().map(|n| n.id).collect();
    let ap: Vec<u32> = a.ports.iter().map(|n| n.id).collect();
    let bp: Vec<u32> = b.ports.iter().map(|n| n.id).collect();
    let al: Vec<u32> = a.links.iter().map(|n| n.id).collect();
    let bl: Vec<u32> = b.links.iter().map(|n| n.id).collect();
    let sa = ids(&an);
    let sb = ids(&bn);
    let pa = ids(&ap);
    let pb = ids(&bp);
    let la = ids(&al);
    let lb = ids(&bl);
    sa.symmetric_difference(&sb).count()
        + pa.symmetric_difference(&pb).count()
        + la.symmetric_difference(&lb).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn port(id: u32, node: u32, dir: &str, ch: &str) -> Port {
        Port {
            id,
            node,
            name: ch.into(),
            dir: dir.into(),
            channel: ch.into(),
            monitor: false,
            physical: false,
        }
    }

    #[test]
    fn stereo_name_map() {
        let from = vec![port(1, 10, "out", "FL"), port(2, 10, "out", "FR")];
        let to = vec![port(3, 20, "in", "FL"), port(4, 20, "in", "FR")];
        let pairs = auto_map(&from, &to).unwrap();
        assert_eq!(pairs.len(), 2);
        assert_eq!(pairs[0].from, 1);
        assert_eq!(pairs[0].to, 3);
    }

    #[test]
    fn mono_fanout() {
        let from = vec![port(1, 10, "out", "MONO")];
        let to = vec![port(3, 20, "in", "FL"), port(4, 20, "in", "FR")];
        let pairs = auto_map(&from, &to).unwrap();
        assert_eq!(pairs.len(), 2);
        assert_eq!(pairs[0].from, 1);
        assert_eq!(pairs[1].from, 1);
    }

    #[test]
    fn stereo_to_51_refuses() {
        let from = vec![port(1, 10, "out", "FL"), port(2, 10, "out", "FR")];
        let to = vec![
            port(3, 20, "in", "FL"),
            port(4, 20, "in", "FR"),
            port(5, 20, "in", "FC"),
            port(6, 20, "in", "LFE"),
            port(7, 20, "in", "RL"),
            port(8, 20, "in", "RR"),
        ];
        let err = auto_map(&from, &to).unwrap_err();
        assert!(err.contains("2→6"));
    }

    #[test]
    fn classify_kinds() {
        assert_eq!(classify("Stream/Output/Audio"), "source");
        assert_eq!(classify("Audio/Sink"), "sink");
        assert_eq!(classify("Audio/Duplex"), "filter");
        assert_eq!(classify("Midi/Bridge"), "midi");
    }

    #[test]
    fn sanitize_prefix() {
        assert_eq!(sanitize_sink_name("Recording"), "Loom-Recording");
        assert_eq!(sanitize_sink_name("Loom-Mix"), "Loom-Mix");
        assert_eq!(sanitize_sink_name("a b/c"), "Loom-abc");
    }

    #[test]
    fn subgraph_streams() {
        let mut g = Graph::default();
        g.nodes.push(Node {
            id: 1,
            serial: 1,
            name: "firefox".into(),
            nick: "Firefox".into(),
            app: "Firefox".into(),
            media_class: "Stream/Output/Audio".into(),
            kind: "source".into(),
            state: "running".into(),
            mute: false,
            volume: 1.0,
            is_default: false,
            is_capture: false,
            is_loom: false,
            channels: vec!["FL".into(), "FR".into()],
            identity: "Firefox|Stream/Output/Audio|0".into(),
            module_id: None,
        });
        g.nodes.push(Node {
            id: 2,
            serial: 2,
            name: "speakers".into(),
            nick: "Speakers".into(),
            app: "".into(),
            media_class: "Audio/Sink".into(),
            kind: "sink".into(),
            state: "running".into(),
            mute: false,
            volume: 1.0,
            is_default: true,
            is_capture: false,
            is_loom: false,
            channels: vec!["FL".into(), "FR".into()],
            identity: "speakers|Audio/Sink|0".into(),
            module_id: None,
        });
        g.links.push(Link {
            id: 9,
            from: 11,
            to: 21,
            from_node: 1,
            to_node: 2,
            kind: "route".into(),
            live: true,
            muted: false,
            latency_ms: None,
        });
        let ids = stream_ids(&g, 2);
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn parse_minimal_dump() {
        let dump = r#"
        [
          {"id":55,"type":"PipeWire:Interface:Node","info":{
            "state":"running",
            "props":{"node.name":"alsa_output.hw","node.nick":"Speakers","media.class":"Audio/Sink","object.serial":55}
          }},
          {"id":77,"type":"PipeWire:Interface:Node","info":{
            "state":"running",
            "props":{"node.name":"Firefox","application.name":"Firefox","media.class":"Stream/Output/Audio","object.serial":77}
          }},
          {"id":80,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{"node.id":77,"port.name":"output_FL","audio.channel":"FL"}}},
          {"id":81,"type":"PipeWire:Interface:Port","info":{"direction":"output","props":{"node.id":77,"port.name":"output_FR","audio.channel":"FR"}}},
          {"id":90,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":55,"port.name":"playback_FL","audio.channel":"FL"}}},
          {"id":91,"type":"PipeWire:Interface:Port","info":{"direction":"input","props":{"node.id":55,"port.name":"playback_FR","audio.channel":"FR"}}},
          {"id":200,"type":"PipeWire:Interface:Link","info":{
            "output-port-id":80,"input-port-id":90,"output-node-id":77,"input-node-id":55
          }},
          {"id":0,"type":"PipeWire:Interface:Metadata","props":{"metadata.name":"default"},
           "metadata":[{"key":"default.audio.sink","value":"{\"name\":\"alsa_output.hw\"}"}]}
        ]
        "#;
        let g = parse_pw_dump(dump);
        assert_eq!(g.nodes.len(), 2);
        assert_eq!(g.ports.len(), 4);
        assert_eq!(g.links.len(), 1);
        assert_eq!(g.defaults.sink, Some(55));
        assert!(g.nodes.iter().any(|n| n.is_default && n.id == 55));
        assert_eq!(g.links[0].kind, "route");
        assert_eq!(g.links[0].live, true);
        let ff = g.nodes.iter().find(|n| n.id == 77).unwrap();
        assert_eq!(ff.identity, "Firefox|Stream/Output/Audio|0");
    }
}
