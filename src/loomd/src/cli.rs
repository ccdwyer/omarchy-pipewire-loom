use crate::graph::{auto_map, node_ports, parse_pw_dump, sanitize_sink_name, stream_ids};
use crate::schema::{self, Command, Graph};
use serde_json::Value;
use std::io::{self, BufRead, Write};
use std::process::{Command as Proc, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

pub fn run_pw_dump() -> Result<String, String> {
    let out = Proc::new("pw-dump")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| format!("pw-dump: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "pw-dump exited {}",
            out.status.code().unwrap_or(-1)
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub fn emit(v: &Value) {
    let mut stdout = io::stdout().lock();
    let _ = writeln!(stdout, "{v}");
    let _ = stdout.flush();
}

fn run_cmd(argv: &[&str]) -> Result<String, String> {
    if argv.is_empty() {
        return Err("empty argv".into());
    }
    let out = Proc::new(argv[0])
        .args(&argv[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| format!("{}: {e}", argv[0]))?;
    let body = String::from_utf8_lossy(&out.stdout).into_owned();
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(if err.trim().is_empty() {
            body
        } else {
            err.into_owned()
        });
    }
    Ok(body)
}

fn node_exists(g: &Graph, id: u32) -> bool {
    g.nodes.iter().any(|n| n.id == id)
}

fn port_exists(g: &Graph, id: u32) -> bool {
    g.ports.iter().any(|p| p.id == id)
}

pub fn handle_command(g: &Graph, cmd: &Command) -> Value {
    match cmd.op.as_str() {
        "dump" => schema::snapshot(g),
        "move" => {
            let stream = match cmd.stream {
                Some(s) if node_exists(g, s) => s,
                _ => return schema::err(&cmd.id, "move", "gone", "stream"),
            };
            let target = match cmd.target {
                Some(t) if node_exists(g, t) => t,
                _ => return schema::err(&cmd.id, "move", "gone", "target"),
            };
            let sid = stream.to_string();
            let tid = target.to_string();
            match run_cmd(&["wpctl", "set-target", &sid, &tid]) {
                Ok(_) => schema::ok(&cmd.id, "move"),
                Err(_) => match run_cmd(&["pw-metadata", &sid, "target.object", &tid]) {
                    Ok(_) => schema::ok(&cmd.id, "move"),
                    Err(e) => schema::err(&cmd.id, "move", "exec", &e),
                },
            }
        }
        "link" => {
            if let (Some(from), Some(to)) = (cmd.from, cmd.to) {
                if !port_exists(g, from) || !port_exists(g, to) {
                    return schema::err(&cmd.id, "link", "gone", "port");
                }
                let a = from.to_string();
                let b = to.to_string();
                return match run_cmd(&["pw-link", "-I", &a, &b]) {
                    Ok(_) => schema::ok(&cmd.id, "link"),
                    Err(e) => schema::err(&cmd.id, "link", "exec", &e),
                };
            }
            if let (Some(fnid), Some(tnid)) = (cmd.from_node, cmd.to_node) {
                if !node_exists(g, fnid) || !node_exists(g, tnid) {
                    return schema::err(&cmd.id, "link", "gone", "node");
                }
                let from: Vec<_> = node_ports(&g.ports, fnid, "out")
                    .into_iter()
                    .cloned()
                    .collect();
                let to: Vec<_> = node_ports(&g.ports, tnid, "in")
                    .into_iter()
                    .cloned()
                    .collect();
                match auto_map(&from, &to) {
                    Err(d) => schema::err(&cmd.id, "link", "ambiguous", &d),
                    Ok(pairs) => {
                        for p in pairs {
                            let a = p.from.to_string();
                            let b = p.to.to_string();
                            if let Err(e) = run_cmd(&["pw-link", "-I", &a, &b]) {
                                return schema::err(&cmd.id, "link", "exec", &e);
                            }
                        }
                        schema::ok(&cmd.id, "link")
                    }
                }
            } else {
                schema::err(&cmd.id, "link", "parse", "need ports or nodes")
            }
        }
        "unlink" => {
            if let (Some(from), Some(to)) = (cmd.from, cmd.to) {
                let a = from.to_string();
                let b = to.to_string();
                return match run_cmd(&["pw-link", "-d", "-I", &a, &b]) {
                    Ok(_) => schema::ok(&cmd.id, "unlink"),
                    Err(e) => schema::err(&cmd.id, "unlink", "exec", &e),
                };
            }
            if let Some(id) = cmd.link {
                let s = id.to_string();
                return match run_cmd(&["pw-cli", "destroy", &s]) {
                    Ok(_) => schema::ok(&cmd.id, "unlink"),
                    Err(e) => schema::err(&cmd.id, "unlink", "exec", &e),
                };
            }
            schema::err(&cmd.id, "unlink", "parse", "need link or ports")
        }
        "volume" => {
            let node = match cmd.node {
                Some(n) if node_exists(g, n) => n,
                _ => return schema::err(&cmd.id, "volume", "gone", "node"),
            };
            let vol = cmd.vol.unwrap_or(1.0).clamp(0.0, 1.0);
            let a = node.to_string();
            let b = format!("{vol}");
            match run_cmd(&["wpctl", "set-volume", &a, &b]) {
                Ok(_) => schema::ok(&cmd.id, "volume"),
                Err(e) => schema::err(&cmd.id, "volume", "exec", &e),
            }
        }
        "mute" => {
            let node = match cmd.node {
                Some(n) if node_exists(g, n) => n,
                _ => return schema::err(&cmd.id, "mute", "gone", "node"),
            };
            let on = cmd.mute.unwrap_or(true);
            let a = node.to_string();
            let b = if on { "1" } else { "0" };
            match run_cmd(&["wpctl", "set-mute", &a, b]) {
                Ok(_) => schema::ok(&cmd.id, "mute"),
                Err(e) => schema::err(&cmd.id, "mute", "exec", &e),
            }
        }
        "muteSubgraph" => {
            let start = match cmd.node {
                Some(n) if node_exists(g, n) => n,
                _ => return schema::err(&cmd.id, "muteSubgraph", "gone", "node"),
            };
            let ids = cmd.nodes.clone().unwrap_or_else(|| stream_ids(g, start));
            let on = cmd.mute.unwrap_or(true);
            let flag = if on { "1" } else { "0" };
            for id in ids {
                let a = id.to_string();
                if let Err(e) = run_cmd(&["wpctl", "set-mute", &a, flag]) {
                    return schema::err(&cmd.id, "muteSubgraph", "exec", &e);
                }
            }
            schema::ok(&cmd.id, "muteSubgraph")
        }
        "spawnSink" => {
            let name = sanitize_sink_name(cmd.name.as_deref().unwrap_or("Mix"));
            let arg = format!("sink_name={name}");
            let desc = format!("sink_properties=device.description={name}");
            match run_cmd(&["pactl", "load-module", "module-null-sink", &arg, &desc]) {
                Ok(body) => serde_json::json!({
                    "t": "ok",
                    "id": cmd.id,
                    "op": "spawnSink",
                    "name": name,
                    "moduleId": body.trim().parse::<u32>().ok()
                }),
                Err(e) => schema::err(&cmd.id, "spawnSink", "exec", &e),
            }
        }
        "destroySink" => {
            let name = cmd.name.clone().unwrap_or_default();
            if !name.starts_with("Loom-") && cmd.module_id.is_none() {
                return schema::err(&cmd.id, "destroySink", "denied", "not a Loom sink");
            }
            if let Some(mid) = cmd.module_id {
                let a = mid.to_string();
                return match run_cmd(&["pactl", "unload-module", &a]) {
                    Ok(_) => schema::ok(&cmd.id, "destroySink"),
                    Err(e) => schema::err(&cmd.id, "destroySink", "exec", &e),
                };
            }
            schema::err(&cmd.id, "destroySink", "denied", "missing module id")
        }
        "cleanupOrphans" => {
            let listing = match run_cmd(&["pactl", "list", "short", "modules"]) {
                Ok(t) => t,
                Err(e) => return schema::err(&cmd.id, "cleanupOrphans", "exec", &e),
            };
            let live = crate::graph::parse_loom_modules(&listing);
            let destroy = cmd.destroy.unwrap_or(false);
            let mut adopted = Vec::new();
            let mut removed = Vec::new();
            for (id, name) in live {
                if destroy {
                    let sid = id.to_string();
                    if let Err(e) = run_cmd(&["pactl", "unload-module", &sid]) {
                        return schema::err(&cmd.id, "cleanupOrphans", "exec", &e);
                    }
                    removed.push(serde_json::json!({ "name": name, "moduleId": id }));
                } else {
                    adopted.push(serde_json::json!({ "name": name, "moduleId": id }));
                }
            }
            serde_json::json!({
                "t": "ok",
                "id": cmd.id,
                "op": "cleanupOrphans",
                "destroy": destroy,
                "adopted": adopted,
                "removed": removed
            })
        }
        other => schema::err(&cmd.id, other, "unsupported", other),
    }
}

pub fn dump_once(from_file: Option<&str>) -> Result<Graph, String> {
    let raw = if let Some(path) = from_file {
        std::fs::read_to_string(path).map_err(|e| e.to_string())?
    } else {
        run_pw_dump()?
    };
    Ok(parse_pw_dump(&raw))
}

pub fn run_daemon(poll_ms: u64, from_file: Option<String>, dry: bool) -> Result<(), String> {
    let (tx, rx) = mpsc::channel::<String>();
    thread::spawn(move || {
        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            match line {
                Ok(l) => {
                    if tx.send(l).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    emit(&schema::hello("cli", true));
    let mut graph = dump_once(from_file.as_deref()).unwrap_or_default();
    graph.gen = 1;
    emit(&schema::snapshot(&graph));

    let poll = Duration::from_millis(poll_ms.max(250));
    let mut last = Instant::now();
    loop {
        match rx.recv_timeout(Duration::from_millis(33)) {
            Ok(line) => {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                match serde_json::from_str::<Command>(line) {
                    Ok(cmd) => {
                        if dry && cmd.op != "dump" {
                            emit(&schema::ok(&cmd.id, &cmd.op));
                        } else {
                            let ev = handle_command(&graph, &cmd);
                            emit(&ev);
                            if cmd.op != "dump" {
                                if let Ok(mut next) = dump_once(from_file.as_deref()) {
                                    next.gen = graph.gen;
                                    emit_diff_or_snap(&graph, &next);
                                    graph = next;
                                }
                            }
                        }
                    }
                    Err(_) => emit(&schema::err("", "", "parse", line)),
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if last.elapsed() >= poll {
                    last = Instant::now();
                    if let Ok(mut next) = dump_once(from_file.as_deref()) {
                        next.gen = graph.gen;
                        emit_diff_or_snap(&graph, &next);
                        graph = next;
                    }
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
    Ok(())
}

fn emit_diff_or_snap(prev: &Graph, next: &Graph) {
    let n = crate::graph::change_count(prev, next);
    if n == 0 {
        return;
    }
    if n > 10 {
        let mut snap = next.clone();
        snap.gen = prev.gen + 1;
        emit(&schema::storm(snap.gen, n));
        emit(&schema::snapshot(&snap));
        return;
    }
    // Small change: still snapshot. Diff construction lives in the JS
    // engine; keeping loomd's poller honest and simple avoids two
    // reconcilers drifting. Generation stays put so the UI applies it as
    // a replace of the same gen (Graph.applySnapshot bumps if present).
    let mut snap = next.clone();
    snap.gen = prev.gen + 1;
    emit(&schema::snapshot(&snap));
}

pub fn run_cmd_once(json: &str, from_file: Option<&str>) -> Result<(), String> {
    let graph = dump_once(from_file).unwrap_or_default();
    let cmd: Command = serde_json::from_str(json).map_err(|e| e.to_string())?;
    emit(&handle_command(&graph, &cmd));
    Ok(())
}
