# Kindle Jailbreak + KOReader (Windows helper)

A Windows PowerShell script that does the PC side of jailbreaking a Kindle with
[WinterBreak](https://github.com/KindleModding/WinterBreak) and installing
[KOReader](https://github.com/koreader/koreader). It downloads both from their official
release pages, copies them to the Kindle, checks every file and tells you what to tap on
the Kindle at each step.

This repo doesn't host any jailbreak or KOReader files. Everything comes straight from
the original projects. The detailed, authoritative guide is
**[kindlemodding.org](https://kindlemodding.org)**. If anything here disagrees with it,
follow kindlemodding.org.

> [!WARNING]
> Jailbreaking may void your warranty and carries a small risk of bricking your device.
> You do this at your own risk. Back up any books you've added yourself first.

## Will it work on my Kindle?

| | |
|---|---|
| **Tested on** | Kindle Paperwhite 5 (11th gen), firmware **5.16.2.1.1** |
| **Should work on** | Kindles that WinterBreak supports, on firmware **below 5.18.1** |
| **Won't work on** | Firmware **5.18.1 or newer**. The script checks this and stops. |

Find your firmware at **Settings → ⋮ → Device Info**.

## Before you start

- A Windows 10 or 11 PC and a USB cable.
- Your Kindle **registered** to an Amazon account, plus Wi-Fi.
- **Turn on Airplane Mode right now** and leave it on. If the Kindle updates its firmware
  before you jailbreak, the jailbreak may stop working.

## Steps

1. **Download this repo**: click **Code → Download ZIP** and unzip it.
2. On the Kindle, check that **Airplane Mode is on**, then **restart** it (hold the power
   button → Restart).
3. Plug the Kindle into the PC.
4. Open PowerShell in the unzipped folder and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-KindleJailbreak.ps1 -Stage WinterBreak
   ```

5. Do the on-device steps the script prints: eject → open the **Kindle Store** → tap
   **Yes** to turn off Airplane Mode → tap **WinterBreak** → wait about 30 seconds until
   text appears and the home screen reloads.
6. Plug the Kindle back in and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-KindleJailbreak.ps1 -Stage KOReader
   ```

7. Eject, then tap the new **KOReader** item in your library.

Add `-DryRun` to either command to check your Kindle and see what would be downloaded,
without changing anything.

## What the script does

**`-Stage WinterBreak`**
- Finds the drive labelled `Kindle` and reads `system\version.txt`. It stops if the
  firmware is 5.18.1 or newer.
- Warns you about any `.bin` update files in the Kindle's root.
- Downloads `WinterBreak.tar.gz` from the latest WinterBreak release and copies it to the
  Kindle's root, including the hidden `.active_content_sandbox` folder.

**`-Stage KOReader`**
- Picks the right KOReader build for your firmware: `kindlehf` for 5.16.3 and newer,
  `kindlepw2` for older.
- Downloads it from the latest KOReader release and copies `koreader\` and `extensions\`
  to the Kindle.
- Adds [`launcher/KOReader.sh`](launcher/KOReader.sh) to `documents\`. WinterBreak shows
  any `.sh` file there as a library item (a "scriptlet") and runs it when you tap it.

Every copied file is checked by SHA-256 hash. Downloads go into a temporary folder on your
PC.

## Why there's no KUAL

Older guides install KUAL (with PEKI or MRPI) to launch KOReader. On WinterBreak, KUAL
can fail with *"Application error. The selected application could not be started"*. The
current kindlemodding.org guide uses scriptlets instead, and that's what this script
installs.

Newer WinterBreak releases (from around June 2026) include the **Kindle Package Manager
(KPM)**. If yours does, you can also install KOReader by typing `;kpm install koreader` in
the Kindle's search bar. See
[Getting KOReader](https://kindlemodding.org/jailbreaking/whats-next/getting-koreader/).

## Troubleshooting

- **The Kindle Store opens normally and there's no WinterBreak icon.** Check that the
  hidden `.active_content_sandbox` folder is in the Kindle's root, then restart the Kindle
  and try again. The
  [WinterBreak troubleshooting](https://kindlemodding.org/jailbreaking/WinterBreak/)
  section covers Store errors.
- **No KOReader item in the library.** Wait a minute, or sort the library by Recent.
  Check that `documents\KOReader.sh` exists.
- **Tapping KOReader does nothing.** Wait about 10 seconds and tap once more; the first
  start is slow.

## Afterwards

- **Don't install Kindle firmware updates.** WinterBreak blocks them automatically.
- Leave the `apps`, `mesquito`, `.active_content_sandbox`, `koreader` and `extensions`
  folders on the Kindle.
- To update KOReader, use KOReader's own **Tools → Update** menu.

## Credits

- [WinterBreak](https://github.com/KindleModding/WinterBreak) by HackerDude and the
  KindleModding team
- [KOReader](https://github.com/koreader/koreader) and its contributors
- [kindlemodding.org](https://kindlemodding.org) for the guides

This repo's own script and launcher are under the [MIT License](LICENSE). WinterBreak and
KOReader keep their own licenses.
