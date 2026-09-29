#!/usr/bin/env python3
"""Test the real resume callback with a mocked ACPI method, without hardware I/O."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / "apple-ib-drv/apple-ibridge.c").read_text()
start = source.index("static int appleib_suspend(")
end = source.index("\nstatic const struct acpi_device_id", start)
callback = source[start:end]

stub = r"""
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef unsigned int acpi_status;
struct appleib_device { int asoc_socw; };
struct device { struct appleib_device *data; };
struct dev_pm_ops {
    int (*suspend)(struct device *);
    int (*resume)(struct device *);
};
static bool test_resume_acpi_once;
static bool skip = true, locked;
static int calls;
static acpi_status status;
#define THIS_MODULE NULL
#define dev_warn(...) ((void)0)
#define dev_info(...) ((void)0)
#define ACPI_FAILURE(s) ((s) != 0)
static void kernel_param_lock(void *p) { assert(!locked); locked = true; }
static void kernel_param_unlock(void *p) { assert(locked); locked = false; }
static struct appleib_device *dev_get_drvdata(struct device *p) {
    return p->data;
}
static bool appleib_skip_acpi_power(void) { return skip; }
static acpi_status acpi_execute_simple_method(int handle, void *path, int arg) {
    assert(!test_resume_acpi_once); /* Disarmed before even entering firmware. */
    assert(!locked); /* Do not hold the parameter mutex across firmware. */
    assert(handle == 42 && path == NULL && arg == 1);
    calls++;
    return status;
}
"""
cases = r"""
int main(void) {
    struct appleib_device ib = { .asoc_socw = 42 };
    struct device p = { .data = &ib };
    assert(appleib_pm_ops.suspend(&p) == 0 && calls == 0);
    assert(appleib_pm_ops.resume(&p) == 0 && calls == 0); /* Default: no AML. */
    test_resume_acpi_once = true;
    assert(appleib_pm_ops.suspend(&p) == 0 && calls == 0);
    assert(test_resume_acpi_once); /* Suspend must neither execute nor consume. */
    assert(appleib_pm_ops.resume(&p) == 0 && calls == 1);
    assert(!test_resume_acpi_once && skip);
    assert(appleib_pm_ops.resume(&p) == 0 && calls == 1); /* Exactly one resume. */
    test_resume_acpi_once = true;
    status = 1;
    assert(appleib_pm_ops.resume(&p) == 0 && calls == 2);
    assert(!test_resume_acpi_once);
    assert(appleib_pm_ops.resume(&p) == 0 && calls == 2); /* Error does not rearm. */
    skip = false;
    assert(appleib_pm_ops.resume(&p) == 0 && calls == 3); /* Preserve force-run option. */
    puts("PASS: PM dispatch, suspend preserves request, disarm before AML, one-shot success/error");
}
"""
with tempfile.TemporaryDirectory(prefix="t1-acpi-test-") as tmp:
    binary = str(Path(tmp) / "test")
    subprocess.run(["cc", "-std=c11", "-Wall", "-Werror", "-x", "c", "-", "-o", binary],
                   input=stub + callback + cases, text=True, check=True)
    subprocess.run([binary], check=True)
