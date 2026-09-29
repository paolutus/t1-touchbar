# Review before local commits — September 28, 2026

[Italiano](FINAL-REVIEW-IT.md) | English

## Scope

Review of local driver, suspend-handling, and documentation changes. No installation,
suspend, firmware change, GitHub configuration, or publication was performed during
this review.

The driver version and operational scripts remained those of the successful test:
no new hardware changes were introduced and implicitly considered validated.
Git exclusions for kernel build artifacts were added, and the mocked restoration
tests were made hardware-independent.

## Checks performed

- Both modules built successfully for `7.0.0-34-generic`.
- Build warnings: different compiler name, same GCC version; `pahole`/`vmlinux`
  unavailable for BTF generation. These are not build errors.
- Mock C tests for forced Touch Bar state restoration, two-interface suspend,
  and the one-shot ACPI diagnostic passed without hardware I/O.
- Mock shell tests for requesting user/inhibitors, PCI subtree scope, asynchronous
  resume waiting, restoration, and zero/nonzero/error keyboard brightness paths
  passed. PCI presence checks use temporary fake directories.
- Shell syntax and Python script compilation checks passed.
- All checksums in the 15-file operational SHA-256 manifest matched.
- `git diff --check` found no whitespace errors.
- A targeted search for private-key markers and tokens in files to include found
  no matches. This is not a comprehensive security audit.
- The systemd drop-in structure had been checked with systemd's parser without
  starting suspend; logs and the user's confirmation also document subsequent
  successful real cycles.

## Limitations to keep visible in the fork

- The hardware result concerns one MacBookPro14,2, not certification of all T1
  models or other kernels.
- The workaround is a combination; the firmware cause has not been isolated.
- Suspend is refused when peripherals are detected; a closed Mac may remain
  awake. Hibernation and suspend-then-hibernate are not covered.
- `test_resume_acpi_once` remains present, disabled by default and writable only
  by root. Its test caused a hang: do not arm it. The scripts require `N` and
  `skip_acpi_power=1`.
- `test_skip_suspend_display_off_once` is also diagnostic and must remain `N`.
- The diagnostics are retained in the snapshot to preserve the exact verified
  version, not to recommend their use. A future version removing these parameters
  will require new hashes, adjusted checks, and revalidation.
- The `srcversion` check is intentionally restrictive; driver/kernel updates
  need review and may cause suspend to be refused.
- Mock tests do not cover firmware failures, concurrent physical hotplug, or
  every possible installer error. Restoration cannot work if the kernel is hung.

## Planned commit separation

1. iBridge/Touch Bar drivers, related tests, DKMS helper and HID diagnostic;
   exclude build artifacts.
2. Guarded s2idle, keyboard backlight, installer/uninstaller, and hardware-independent
   shell tests.
3. Reproducible guide, operating notes, manifest, README, and this review.

Choose an appropriate Git author identity before publication: name and email
are part of the commits even when those commits are initially created only locally.
