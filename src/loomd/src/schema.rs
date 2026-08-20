use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Node {
    pub id: u32,
    pub serial: u32,
    pub name: String,
    pub nick: String,
    pub app: String,
    #[serde(rename = "mediaClass")]
    pub media_class: String,
    pub kind: String,
    pub state: String,
    pub mute: bool,
    pub volume: f64,
    #[serde(rename = "isDefault")]
    pub is_default: bool,
    #[serde(rename = "isCapture")]
    pub is_capture: bool,
    #[serde(rename = "isLoom")]
    pub is_loom: bool,
    pub channels: Vec<String>,
    pub identity: String,
    #[serde(rename = "moduleId", skip_serializing_if = "Option::is_none")]
    pub module_id: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Port {
    pub id: u32,
    pub node: u32,
    pub name: String,
    pub dir: String,
    pub channel: String,
    pub monitor: bool,
    pub physical: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Link {
    pub id: u32,
    pub from: u32,
    pub to: u32,
    #[serde(rename = "fromNode")]
    pub from_node: u32,
    #[serde(rename = "toNode")]
    pub to_node: u32,
    pub kind: String,
    pub live: bool,
    pub muted: bool,
    #[serde(rename = "latencyMs")]
    pub latency_ms: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Defaults {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sink: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<u32>,
    #[serde(rename = "sinkName", default)]
    pub sink_name: String,
    #[serde(rename = "sourceName", default)]
    pub source_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphInfo {
    pub quantum: u32,
    pub rate: u32,
    #[serde(rename = "latencyMs")]
    pub latency_ms: f64,
}

impl Default for GraphInfo {
    fn default() -> Self {
        Self {
            quantum: 1024,
            rate: 48000,
            latency_ms: 21.333,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Graph {
    #[serde(default)]
    pub gen: u64,
    #[serde(default)]
    pub nodes: Vec<Node>,
    #[serde(default)]
    pub ports: Vec<Port>,
    #[serde(default)]
    pub links: Vec<Link>,
    #[serde(default)]
    pub defaults: Defaults,
    #[serde(default)]
    pub graph: GraphInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Command {
    pub op: String,
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub stream: Option<u32>,
    #[serde(default)]
    pub target: Option<u32>,
    #[serde(default)]
    pub from: Option<u32>,
    #[serde(default)]
    pub to: Option<u32>,
    #[serde(rename = "fromNode", default)]
    pub from_node: Option<u32>,
    #[serde(rename = "toNode", default)]
    pub to_node: Option<u32>,
    #[serde(default)]
    pub link: Option<u32>,
    #[serde(default)]
    pub node: Option<u32>,
    #[serde(default)]
    pub vol: Option<f64>,
    #[serde(default)]
    pub mute: Option<bool>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(rename = "moduleId", default)]
    pub module_id: Option<u32>,
    #[serde(default)]
    pub nodes: Option<Vec<u32>>,
}

pub fn hello(backend: &str, compat: bool) -> Value {
    serde_json::json!({
        "t": "hello",
        "backend": backend,
        "version": SCHEMA_VERSION,
        "compat": compat,
    })
}

pub fn snapshot(graph: &Graph) -> Value {
    serde_json::json!({
        "t": "snapshot",
        "gen": graph.gen,
        "nodes": graph.nodes,
        "ports": graph.ports,
        "links": graph.links,
        "defaults": graph.defaults,
        "graph": graph.graph,
    })
}

pub fn storm(gen: u64, n: usize) -> Value {
    serde_json::json!({ "t": "storm", "gen": gen, "n": n, "windowMs": 100 })
}

pub fn ok(id: &str, op: &str) -> Value {
    serde_json::json!({ "t": "ok", "id": id, "op": op })
}

pub fn err(id: &str, op: &str, err: &str, msg: &str) -> Value {
    serde_json::json!({ "t": "err", "id": id, "op": op, "err": err, "msg": msg })
}

#[allow(dead_code)]
pub fn toast(msg: &str, level: &str) -> Value {
    serde_json::json!({ "t": "toast", "level": level, "msg": msg })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_roundtrip() {
        let v = hello("cli", true);
        assert_eq!(v["t"], "hello");
        assert_eq!(v["backend"], "cli");
        assert_eq!(v["compat"], true);
        assert_eq!(v["version"], 1);
    }

    #[test]
    fn command_parse_move() {
        let c: Command = serde_json::from_str(r#"{"op":"move","id":"1","stream":77,"target":55}"#).unwrap();
        assert_eq!(c.op, "move");
        assert_eq!(c.stream, Some(77));
        assert_eq!(c.target, Some(55));
    }
}
