//! Optional libpipewire subscriber.
//!
//! Isolated behind `--features pipewire`. The crate API of `pipewire` 0.8
//! varies slightly across point releases, so this module is a thin
//! registry listener that dirties the graph and re-parses via `pw-dump`
//! (same schema as the CLI path). Mutations still go through wpctl.
//!
//! If this file fails to compile on a given Arch image, `build.sh` drops
//! the feature and ships the CLI binary.

#![cfg(feature = "pipewire")]

use crate::cli::{dump_once, emit, handle_command};
use crate::schema;
use serde_json::Value;
use std::io::{self, BufRead};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub fn run() -> Result<(), String> {
    pipewire::init();
    let mainloop = pipewire::MainLoop::new(None).map_err(|e| format!("mainloop: {e}"))?;
    let context = pipewire::Context::new(&mainloop).map_err(|e| format!("context: {e}"))?;
    let core = context
        .connect(None)
        .map_err(|e| format!("connect: {e}"))?;
    let registry = core.get_registry();

    let dirty = Arc::new(AtomicBool::new(true));
    let dirty_add = dirty.clone();
    let dirty_rm = dirty.clone();

    let _listener = registry
        .add_listener_local()
        .global(move |_global| {
            dirty_add.store(true, Ordering::SeqCst);
        })
        .global_remove(move |_id| {
            dirty_rm.store(true, Ordering::SeqCst);
        })
        .register();

    emit(&schema::hello("loomd", false));

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

    let mut graph = dump_once(None).unwrap_or_default();
    graph.gen = 1;
    emit(&schema::snapshot(&graph));

    // Drive pw mainloop in this thread with short iterate timeouts, and
    // service stdin + dumps between iterations.
    loop {
        mainloop.iterate(Duration::from_millis(16));
        while let Ok(line) = rx.try_recv() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            match serde_json::from_str::<crate::schema::Command>(line) {
                Ok(cmd) => {
                    let ev = handle_command(&graph, &cmd);
                    emit(&ev);
                    dirty.store(true, Ordering::SeqCst);
                }
                Err(_) => emit(&schema::err("", "", "parse", line)),
            }
        }
        if dirty.swap(false, Ordering::SeqCst) {
            if let Ok(mut next) = dump_once(None) {
                next.gen = graph.gen + 1;
                emit(&schema::snapshot(&next));
                graph = next;
            }
        }
        let _ = Value::Null;
    }
}
