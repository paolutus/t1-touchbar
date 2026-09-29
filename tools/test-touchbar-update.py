#!/usr/bin/env python3
"""Exercise the actual driver's update functions in a small userspace harness.

Checks cached-state/forced-resume behavior, not USB or physical hardware.
"""
from pathlib import Path
import re
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "apple-ib-drv/apple-touchbar.c").read_text()


def extract(name):
    start = source.index("static ", source.index(name) - 40)
    opening = source.index("{", source.index(name, start))
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


constants = "\n".join(re.findall(r"^#define APPLETB_(?:CMD|FN)_.*$", source, re.M))
functions = "\n".join(extract(name) for name in (
    "appletb_get_cur_tb_mode", "appletb_get_cur_tb_disp",
    "appletb_get_fn_tb_mode", "appletb_update_touchbar_no_lock",
))
stub = r"""
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
struct appletb_device {
    unsigned char cur_tb_mode, pnd_tb_mode, cur_tb_disp, pnd_tb_disp;
    int idle_timeout, dim_timeout, fn_mode, tb_work;
    bool last_fn_pressed;
};
static bool held;
static int scheduled;
#define dev_dbg_ratelimited(...) ((void)0)
static bool appletb_any_tb_key_pressed(struct appletb_device *d) { return held; }
static void cancel_delayed_work(int *w) { }
static void appletb_schedule_tb_update(struct appletb_device *d, long secs) {
    assert(secs == 0); scheduled++;
}
"""
cases = r"""
int main(void) {
    struct appletb_device d = {
        .cur_tb_mode = APPLETB_CMD_MODE_SPCL, .pnd_tb_mode = APPLETB_CMD_MODE_NONE,
        .cur_tb_disp = APPLETB_CMD_DISP_ON, .pnd_tb_disp = APPLETB_CMD_DISP_NONE,
        .idle_timeout = 300, .dim_timeout = 30, .fn_mode = APPLETB_FN_MODE_NORM
    };
    /* Normal input with unchanged state must not generate writes. */
    appletb_update_touchbar_no_lock(&d, false);
    assert(scheduled == 0);
    /* A reset invalidates the hardware state even if the cache still says ON. */
    appletb_update_touchbar_no_lock(&d, true);
    assert(scheduled == 1);
    assert(d.pnd_tb_mode == APPLETB_CMD_MODE_SPCL);
    assert(d.pnd_tb_disp == APPLETB_CMD_DISP_ON);
    /* Resume cannot be suppressed by stale held-key state. */
    d.pnd_tb_mode = APPLETB_CMD_MODE_NONE;
    d.pnd_tb_disp = APPLETB_CMD_DISP_NONE;
    held = true;
    appletb_update_touchbar_no_lock(&d, true);
    assert(scheduled == 2 && d.pnd_tb_mode == APPLETB_CMD_MODE_SPCL);
    /* Respect an explicitly disabled bar on resume. */
    d.idle_timeout = -2;
    appletb_update_touchbar_no_lock(&d, true);
    assert(d.pnd_tb_mode == APPLETB_CMD_MODE_OFF);
    assert(d.pnd_tb_disp == APPLETB_CMD_DISP_OFF);
    puts("PASS: unchanged state, forced resend, stale keys, disabled bar");
}
"""
with tempfile.TemporaryDirectory(prefix="t1-update-test-") as tmp:
    binary = str(Path(tmp) / "test")
    subprocess.run(["cc", "-std=c11", "-Wall", "-Werror", "-x", "c", "-", "-o", binary],
                   input=stub + constants + "\n" + functions + cases, text=True, check=True)
    subprocess.run([binary], check=True)
