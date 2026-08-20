//! loomd — PipeWire Loom helper (v1.0 = CLI poller only).
//!
//! `pw-dump` + `wpctl` / `pw-link` / `pactl`, NDJSON on stdout, commands
//! on stdin. Native libpipewire subscribe is parked for v1.0 (`native.rs`
//! is not compiled).
//!
//!   loomd --cli            daemon (CLI poller)
//!   loomd --dump           oneshot snapshot
//!   loomd --cmd 'json'     oneshot command
//!   loomd --from-dump F    parse a fixture (tests / replay)

mod cli;
mod graph;
mod schema;

use std::env;
use std::process;

fn print_usage() {
    eprintln!(
        "usage:
  loomd [--cli] [--poll-ms N] [--from-dump FILE] [--dry]
  loomd --dump [--from-dump FILE]
  loomd --cmd JSON [--from-dump FILE]
  loomd --self-test
  loomd --help"
    );
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.iter().any(|a| a == "--help" || a == "-h") {
        print_usage();
        process::exit(0);
    }
    if args.iter().any(|a| a == "--version") {
        println!("loomd 1.0.0");
        process::exit(0);
    }
    if args.iter().any(|a| a == "--self-test") {
        let g = graph::parse_pw_dump("[]");
        assert!(g.nodes.is_empty());
        println!("{{\"t\":\"ok\",\"op\":\"self-test\"}}");
        process::exit(0);
    }

    let mut dump = false;
    let mut cmd: Option<String> = None;
    let mut from_dump: Option<String> = None;
    let mut poll_ms: u64 = 1000;
    let mut dry = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--cli" => {}
            "--dump" => dump = true,
            "--native" => {
                eprintln!("loomd: native mode is parked in v1.0; using CLI poller");
            }
            "--dry" => dry = true,
            "--cmd" => {
                i += 1;
                cmd = args.get(i).cloned();
            }
            "--from-dump" => {
                i += 1;
                from_dump = args.get(i).cloned();
            }
            "--poll-ms" => {
                i += 1;
                poll_ms = args
                    .get(i)
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1000);
            }
            other => {
                eprintln!("loomd: unknown arg {other}");
                print_usage();
                process::exit(2);
            }
        }
        i += 1;
    }

    let result = if dump {
        cli::dump_once(from_dump.as_deref()).map(|mut g| {
            g.gen = 1;
            cli::emit(&schema::hello("cli", true));
            cli::emit(&schema::snapshot(&g));
        })
    } else if let Some(json) = cmd {
        cli::run_cmd_once(&json, from_dump.as_deref())
    } else {
        cli::run_daemon(poll_ms, from_dump, dry)
    };

    if let Err(e) = result {
        eprintln!("loomd: {e}");
        process::exit(1);
    }
}
