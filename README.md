# Laptop Auto Checker

A single-file Windows tool to check a second-hand laptop **before you buy it**.
Run one file; it inspects the hardware, warns about theft locks, spyware and
fake parts, and saves a clean PASS / WARN / FAIL report in English **and**
Bangla or Chinese.

It reads only — it changes nothing on the laptop (screen brightness is put back
after its test). Works on Windows 10 and 11, Intel / AMD / ARM, with or without
Administrator.

Made by **Mahdi**.

## How to use

1. Download the ZIP (green **Code** button → **Download ZIP**) and extract it.
2. Double-click **`START-LAPTOP-CHECK.bat`**.
3. Say **Yes** to the Administrator prompt, then follow the screen.

The run has five parts: automatic checks, a few guided hand checks (the screen
tells you what to do), a CPU heat test, a real battery-life test, and then the
report opens. The % done shows in the window title.

See **README.txt** (English + 中文) or **README-Bangla.txt** for full steps.

## What it checks

- **Model & serial** — blank serial can mean a replaced motherboard
- **CPU / RAM / GPU** — age, Windows 11 support, a no-restart RAM test
- **Battery** — real capacity measured by a 20% drain test, so a faked
  "health %" from the battery chip is caught
- **Storage** — SSD/HDD health, wear, a read-only bad-sector scan, speed
- **Screen** — resolution and whether the panel was swapped
- **WiFi / Bluetooth / camera / mic / speakers / touch / fingerprint / SD / SIM / NFC**
- **Windows & security** — activation, TPM, Secure Boot, BitLocker
- **Remote-control & spyware** — AnyDesk, TeamViewer and 20+ others, keyloggers, cracked Windows
- **Theft & company locks** — Computrace, Windows Autopilot, Azure AD / MDM
- **History** — past crashes and their cause, sudden shutdowns, disk errors, a hidden reset
- **Heat test** — full-load temperature and throttling

## Results

**FAIL** = do not buy · **WARN** = bargain the price down · **PASS** = OK · **INFO** = for your information

Each problem comes with a short tip in the report. Things only a person can
judge (sticker serial, BIOS password, body damage, fan noise) are listed at the
end of the report.

## Tools folder

`Tools\CrystalDiskInfo` (MIT) and `Tools\FurMark` (freeware) are bundled.
CPU-Z and HWMonitor are not re-hosted here — download links are in the READMEs.
See `THIRD-PARTY-NOTICES.txt`.

## License

MIT — see `LICENSE`. Covers the scripts only; the Tools keep their own licenses.
