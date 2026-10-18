# CMF Phone 1 (tetris) — LineageOS Dirty Flash

A fastboot script that **dirty-flashes** an extracted LineageOS OTA update on the
CMF Phone 1 (codename **tetris**, MT6878 / Dimensity 7300) **without wiping
user data**.

Made for updates that ship as `payload.bin` and cannot be sideloaded directly
(e.g. an unofficial build whose OTA is not signed for your recovery): extract
the images with [otaripper](https://github.com/syedinsaf/otaripper), drop this
script next to them, and flash.

> **Dirty flash** = partitions are written over the current install. `userdata`
> and `metadata` are never touched, only the **current slot** is written.

## Features

- Scans the image folder and classifies every `*.img` before anything is
  flashed — you see the full plan up front, nothing is flashed silently.
- Correct name mapping for this device (`preloader_raw.img` → `preloader_a`,
  `bl2_ext` is not a partition, and so on — see below).
- `lk.img` is verified against the **official** stock SHA-256 before flashing,
  with an extra warning for fenrir-patched images.
- Bootloader-fastboot phase (boot chain, firmware) and fastbootd phase
  (logical partitions inside `super`), including Virtual A/B snapshot handling.
- Never writes identity / wipe partitions (IMEI, lock state, keys, data) —
  these are blocked unconditionally.

## Requirements

- Windows, phone with an **unlocked bootloader**.
- USB drivers working in both bootloader fastboot and fastbootd
  (Android Bootloader Interface).
- `platform-tools` — downloaded automatically if not present.

## Usage

1. Put `dirty_flash.bat` in the folder with the extracted `*.img` files
   (OTARipper output + a clean stock `lk.img`).
2. Boot the phone into bootloader mode: `adb reboot bootloader`
3. Run the script, read the plan table, answer the prompts.

Typical answers for a LineageOS update:

- **Firmware images?** `N` — the ROM update does not touch early-boot firmware,
  and a wrong preloader can hard-brick the phone.
- **Flash lk.img?** `Y` — only after the script prints
  `Verdict: KNOWN STOCK lk` (see below).
- Final confirmation: `Y`.

First boot after an update can take a few minutes.

## How images are handled

| Tag | Meaning | What happens |
|---|---|---|
| `[AUTO]` | ROM images | Flashed without asking |
| `[ASK]` | lk / firmware / unknown names | Separate question each |
| `[BLOCK]` | identity, wipe or device-state data | Never flashed |

For a full image set the plan looks like this:

**Phase 1 — bootloader fastboot mode**

| Images | Target |
|---|---|
| `boot`, `dtbo`, `init_boot`, `vendor_boot` | `boot_a`, `dtbo_a`, ... |
| `vbmeta`, `vbmeta_system`, `vbmeta_vendor` | `vbmeta_a`, ... (optional `VBMETA_FLAGS`) |
| `lk.img` *(asked, hash-checked)* | `lk_a` |
| `apusys ccu connsys_bt connsys_gnss connsys_wifi dpm gpueb gz logo mcf_ota mcupm modem pi_img scp spmfw sspm tee vcp` *(asked)* | `name_a` |
| `preloader_raw.img` *(asked)* | `preloader_a` |

**Phase 2 — fastbootd (`fastboot reboot fastboot`)**

| Images | Target |
|---|---|
| `system system_ext product vendor odm odm_dlkm vendor_dlkm system_dlkm` | `name_a` |

Then `fastboot --set-active=<current-slot>` and `fastboot reboot`.

### Name mapping notes

- **`preloader_raw.img` goes to the `preloader` partition.** Same mapping as
  nothing_flasher's `flash_all.bat` and the fenrir flash instructions. The file
  name is not the partition name. `preloader.img` (if present) is accepted as an
  alternative; `preloader_raw.img` wins if both exist.
- **`bl2_ext` is not a partition on this device.** The `lk` partition is a
  package containing `lk + bl2_ext + aee + lk_main_dtb + lk_dtbo` (see the
  fenrir README and R0rt1z2's write-up; the preloader log even loads it as
  `part: lk_a img: bl2_ext`). A standalone `bl2_ext.img`/`aee.img`/... is an
  unpacked sub-image and is blocked — only a complete `lk.img` can be flashed
  to `lk_a`.
- **`fastboot getvar product` reports `k6878v1_64`** (the MT6878 platform name),
  not `tetris`. Both values are accepted.

### Never flashed (hard block)

| Partitions | Why |
|---|---|
| `nvram`, `nvdata`, `nvcfg`, `protect1`, `protect2` | IMEI / calibration |
| `persist` | DRM, device keys |
| `seccfg` | bootloader lock state |
| `proinfo` | serial / product info |
| `frp` | factory reset protection data |
| `userdata`, `metadata`, `cache`, `sdcard` | user data |
| `super_empty` | wiping the super partition layout |

These are never part of a ROM update. Stock flashers never write them from a
ROM zip either.

## lk.img and fenrir

Some unofficial builds for tetris ship a **fenrir-patched** `lk.img` in their
OTA payload. Fenrir ([R0rt1z2/fenrir](https://github.com/R0rt1z2/fenrir),
archived Sep 2026) is a PoC that patches `sec_get_vfy_policy()` inside the
`bl2_ext` component to break the secure boot chain after the preloader. Google
made changes with PI so it's not working right know (basic integrity only, 
bootloader shows locked and shows rkp on da key attestation app tho...), and flashing it may trigger a
factory reset. Its release notes also state that Nothing patched the issue in
NOS 4 stable, so it no longer works on current preloader firmware.

Instead, use a clean stock `lk.img` from the official firmware archive
([spike0en/nothing_archive](https://github.com/spike0en/nothing_archive)) and
let the script verify it. Known stock hash for
`Tetris_B4.1-260928-1140` (`lk.img`):

```
06fe7a8ec097ec05c13c416ffef3989b8c85190bf6621ab0be7d509fa1543dbd
```

The script computes the SHA-256 of your `lk.img`:

- `Verdict: KNOWN STOCK lk` → matches the official image, flash on request.
- `Verdict: UNKNOWN` → does **not** match; it may be fenrir-patched. Flash only
  if you know exactly what the file is.
- It also scans the image for the string `fenrir` as a best-effort extra check.

Update `STOCK_LK_SHA256` at the top of the script when a newer official
firmware archive is released.

## Differences from `flash_all.bat` (nothing_flasher)

`flash_all.bat` is a **clean stock firmware flasher**; this script is a
**dirty ROM updater**:

- No `wipe data` step; `userdata`/`metadata` are never erased.
- No `wipe-super` / logical delete+create — logical partitions are written in
  place (fastboot resizes them to fit the image).
- Only the **current** slot is written; the other slot is left untouched as a
  fallback (`flash_all.bat` forces everything to slot `a`).
- `lk` is not flashed blindly with the firmware group — it gets its own gate.
- Images are discovered from the folder instead of a fixed list, so partial
  extractions work and unknown files get an explicit question.

## Troubleshooting

- **fastbootd never appears (Windows):** the phone re-enumerates in fastbootd
  mode and the driver can get stuck. Refresh the driver in Device Manager or
  try a USB 2.0 port.
- **"snapshot merge is in progress":** boot Android, let the Virtual A/B merge
  finish, then run the script again.
- **Interrupted run:** nothing is wiped; re-run the script, already written
  partitions are simply written again.
- **Bootloop:** bootloader mode still works — re-run the script with the
  previous images, or flash just `lk`: `fastboot flash lk_a lk.img`.
- **Wrong product name:** if `fastboot getvar product` returns something else
  entirely, fix `TARGET` at the top of the script.

## Credits

- [spike0en/nothing_archive](https://github.com/spike0en/nothing_archive) —
  official firmware archives and hash files for tetris.
- [spike0en/nothing_flasher](https://github.com/spike0en/nothing_flasher) —
  `flash_all.bat`, the reference for partition names and mappings.
- [R0rt1z2/fenrir](https://github.com/R0rt1z2/fenrir) — the `bl2_ext`/`lk`
  boot chain write-up.
- [syedinsaf/otaripper](https://github.com/syedinsaf/otaripper) — OTA payload
  extraction.

## Disclaimer

Flashing partitions can brick your device. Everything here is at your own
risk. Read the plan table before answering any prompt.
