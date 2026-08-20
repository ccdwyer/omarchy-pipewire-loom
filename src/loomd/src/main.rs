//! loomd — PipeWire Loom helper.
//!
//! Default: CLI poller (`pw-dump` + `wpctl`/`pw-link`/`pactl`), NDJSON on
//! stdout, commands on stdin. Optional `--features pipewire` builds a
//! registry-subscribe upgrade that still emits the same schema.
//!
//! Subcommands used by QML when Process.stdin is unavailable:
//!   loomd --cli            daemon (CLI poller)
//!   loomd --dump           oneshot snapshot
//!   loomd --cmd 'json'     oneshot command
//!   loomd --from-dump F    parse a fixture (tests / replay)

mod cli;
mod graph;
#[cfg(feature = "pipewire")]
mod native;
mod schema;

use std::env;
use std::process;

fn print_usage() {
    eprintln!(
        "usage:
  loomd [--cli] [--poll-ms N] [--from-dump FILE] [--dry]
  loomd --dump [--from-dump FILE]
  loomd --cmd JSON [--from-dump FILE]
  loomd --native
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
    let mut native = false;
    let mut force_cli = false;
    let mut cmd: Option<String> = None;
    let mut from_dump: Option<String> = None;
    let mut poll_ms: u64 = 1000;
    let mut dry = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--cli" => force_cli = true,
            "--dump" => dump = true,
            "--native" => native = true,
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
    } else if native && !force_cli {
        #[cfg(feature = "pipewire")]
        {
            native::run()
        }
        #[cfg(not(feature = "pipewire"))]
        {
            eprintln!("loomd: built without --features pipewire; falling back to CLI");
            cli::run_daemon(poll_ms, from_dump, dry)
        }
    } else if !force_cli {
        #[cfg(feature = "pipewire")]
        {
            if from_dump.is_none() && !dry {
                match native::run() {
                    Ok(()) => Ok(()),
                    Err(e) => {
                        eprintln!("loomd: native failed ({e}); CLI poller");
                        cli::run_daemon(poll_ms, from_dump, dry)
                    }
                }
            } else {
                cli::run_daemon(poll_ms, from_dump, dry)
            }
        }
        #[cfg(not(feature = "pipewire"))]
        {
            cli::run_daemon(poll_ms, from_dump, dry)
        }
    } else {
        cli::run_daemon(poll_ms, from_dump, dry)
    };

    if let Err(e) = result {
        eprintln!("loomd: {e}");
        process::exit(1);
    }
}
