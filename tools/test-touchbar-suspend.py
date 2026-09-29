#!/usr/bin/env python3
"""Exercise the actual suspend callback with mocked HID/PM, not real hardware."""
from pathlib import Path
import re
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "apple-ib-drv/apple-touchbar.c").read_text()
start = source.index("static int appletb_suspend(")
end = source.index("static int appletb_resume_common(", start)
callback = source[start:end]
constants = "\n".join(re.findall(r"^#define APPLETB_CMD_.*$", source, re.M))
stub = r"""
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef struct { int event; } pm_message_t;
#define PM_EVENT_SUSPEND 1
#define PM_EVENT_FREEZE 2
#define PM_EVENT_AUTO_SUSPEND 3
#define PM_HINT_NORMAL 0
#define THIS_MODULE NULL
#define dev_info(...) ((void)0)
#define spin_lock_irqsave(lock, flags) ((flags) = 0)
#define spin_unlock_irqrestore(lock, flags) ((void)(flags))
struct appletb_device;
struct hid_device { struct appletb_device *data; };
struct appletb_iface_info { struct hid_device *hdev; bool suspended; };
struct appletb_device {
    struct appletb_iface_info mode_iface, disp_iface;
    bool active, is_t1, tb_autopm_off;
    int tb_work, cur_tb_mode, cur_tb_disp;
};
static bool test_skip_suspend_display_off_once, locked;
static int mode_calls, display_calls, power_calls;
static void kernel_param_lock(void *p) { assert(!locked); locked = true; }
static void kernel_param_unlock(void *p) { assert(locked); locked = false; }
static struct appletb_device *hid_get_drvdata(struct hid_device *h) { return h->data; }
static struct appletb_iface_info *appletb_get_iface_info(struct appletb_device *d,
                                                       struct hid_device *h) {
    if (h == d->mode_iface.hdev) return &d->mode_iface;
    if (h == d->disp_iface.hdev) return &d->disp_iface;
    return NULL;
}
static void cancel_delayed_work(int *w) { }
static void flush_delayed_work(int *w) { }
static int hid_hw_power(struct hid_device *h, int hint) {
    assert(h && hint == PM_HINT_NORMAL && !locked);
    power_calls++;
    return 0;
}
static int appletb_set_tb_mode(struct appletb_device *d, int mode) {
    assert(mode == APPLETB_CMD_MODE_OFF && !locked);
    mode_calls++;
    return 0;
}
static int appletb_set_tb_disp(struct appletb_device *d, int disp) {
    assert(disp == APPLETB_CMD_DISP_OFF && !locked);
    display_calls++;
    if (d->tb_autopm_off) {
        hid_hw_power(d->disp_iface.hdev, PM_HINT_NORMAL);
        d->tb_autopm_off = false;
    }
    return 0;
}
"""
cases = r"""
static void reset(struct appletb_device *d) {
    d->is_t1 = d->active = d->tb_autopm_off = true;
    d->mode_iface.suspended = d->disp_iface.suspended = false;
    d->cur_tb_mode = APPLETB_CMD_MODE_SPCL;
    d->cur_tb_disp = APPLETB_CMD_DISP_ON;
    mode_calls = display_calls = power_calls = 0;
}
int main(void) {
    struct appletb_device d = {0};
    struct hid_device mode = {&d}, display = {&d};
    pm_message_t suspend = {PM_EVENT_SUSPEND}, freeze = {PM_EVENT_FREEZE};
    pm_message_t runtime = {PM_EVENT_AUTO_SUSPEND};
    d.mode_iface.hdev = &mode;
    d.disp_iface.hdev = &display;
    for (int reverse = 0; reverse < 2; reverse++) {
        struct hid_device *first = reverse ? &display : &mode;
        struct hid_device *last = reverse ? &mode : &display;
        reset(&d);
        test_skip_suspend_display_off_once = true;
        appletb_suspend(first, runtime);
        assert(test_skip_suspend_display_off_once && d.active);
        appletb_suspend(first, suspend);
        assert(test_skip_suspend_display_off_once && !d.active);
        assert(mode_calls == 0 && display_calls == 0 && power_calls == 0);
        appletb_suspend(last, suspend);
        assert(!test_skip_suspend_display_off_once);
        assert(mode_calls == 1 && display_calls == 0 && power_calls == 1);
        assert(!d.tb_autopm_off && d.cur_tb_disp == APPLETB_CMD_DISP_ON);
        assert(d.cur_tb_mode == APPLETB_CMD_MODE_OFF);
        /* Next suspend falls back to the original sequence. */
        reset(&d);
        appletb_suspend(first, suspend);
        appletb_suspend(last, suspend);
        assert(mode_calls == 1 && display_calls == 1 && power_calls == 1);
        assert(d.cur_tb_disp == APPLETB_CMD_DISP_OFF);
    }
    reset(&d);
    test_skip_suspend_display_off_once = true;
    appletb_suspend(&mode, freeze);
    appletb_suspend(&display, freeze);
    assert(test_skip_suspend_display_off_once);
    assert(mode_calls == 0 && display_calls == 0 && power_calls == 0);
    reset(&d);
    d.is_t1 = false;
    appletb_suspend(&mode, suspend);
    appletb_suspend(&display, suspend);
    assert(test_skip_suspend_display_off_once && d.active);
    assert(mode_calls == 0 && display_calls == 0 && power_calls == 0);
    /* No PM reference held: the test must not release one. */
    reset(&d);
    d.tb_autopm_off = false;
    appletb_suspend(&mode, suspend);
    appletb_suspend(&display, suspend);
    assert(!test_skip_suspend_display_off_once);
    assert(mode_calls == 1 && display_calls == 0 && power_calls == 0);
    puts("PASS: single-use display skip, both interface orders, PM balance, default/freeze/runtime/T2 paths");
}
"""
with tempfile.TemporaryDirectory(prefix="t1-suspend-test-") as tmp:
    binary = str(Path(tmp) / "test")
    subprocess.run(["cc", "-std=c11", "-Wall", "-Werror", "-x", "c", "-", "-o", binary],
                   input=constants + "\n" + stub + callback + cases, text=True, check=True)
    subprocess.run([binary], check=True)
