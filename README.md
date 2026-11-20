# EffectCraft to After Effects Converter

Convert **EffectCraft** projects (`.ecproj`) into real **Adobe After Effects** projects (`.aep`).

Drag your `.ecproj` onto one file. After Effects opens, rebuilds your project and saves a `.aep` next to the original. Comps, layers, keyframes, effects, masks, text and shape layers come along.

![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)
![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue.svg)
![After Effects](https://img.shields.io/badge/After%20Effects-CC%202018%2B-9999FF.svg)
![Version](https://img.shields.io/badge/version-1.0.2-orange.svg)

Created by **Rafiquzzaman Rafi**.

---

## Contents

- [Why this exists](#why-this-exists)
- [Download](#download)
- [Requirements](#requirements)
- [How to use (Windows)](#how-to-use-windows)
- [How to use (inside After Effects, or on Mac)](#how-to-use-inside-after-effects-or-on-mac)
- [What carries over](#what-carries-over)
- [After converting: quick checklist](#after-converting-quick-checklist)
- [Teaching it new effects](#teaching-it-new-effects)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Project files](#project-files)
- [Contributing](#contributing)
- [Author](#author)
- [License](#license)
- [Disclaimer](#disclaimer)

---

## Why this exists

EffectCraft is a free After Effects alternative, and its project files are plain JSON. That makes them easy to read, but there was no way to take that work back into After Effects. If you started a project in EffectCraft and needed to finish it in AE, or share it with someone who only uses AE, you had to rebuild everything by hand.

This tool does the rebuilding for you.

---

## Download

1. Go to the [Releases](../../releases) page.
2. Download the latest `EffectCraft-to-AfterEffects-vX.X.X.zip`.
3. Unzip it anywhere.

The `.bat` file is self-contained. It carries the whole converter inside it, so you can share just that one file if you want.

---

## Requirements

| What | Why |
| --- | --- |
| Windows 10 or 11 | The `.bat` launcher uses PowerShell, which ships with Windows. |
| Adobe After Effects CC 2018 or newer | After Effects writes the `.aep` file. See [How it works](#how-it-works). |
| An EffectCraft project (`.ecproj`) | Tested with EffectCraft file schema 2. |

Some features need newer After Effects versions:

- **SVG footage** needs After Effects 2025 or newer. Older versions get a placeholder.
- **Track mattes on layers that aren't directly above** need After Effects 2023 or newer.

---

## How to use (Windows)

1. **Drag** one or more `.ecproj` files (or a whole folder) onto `EffectCraft to After Effects.bat`.
   You can also **double-click** the `.bat` and pick files in the window that opens.
2. After Effects opens. A progress window shows each step.
3. When it's done, a popup lists anything worth checking.
4. Your new `.aep` is saved **next to the `.ecproj`**. The converter never overwrites an existing `.aep`. It adds `(2)`, `(3)` and so on instead.

The console window tells you when the `.aep` appears on disk.

**First run on a new PC:** Windows may show "Windows protected your PC" because the file came from the internet. Click **More info**, then **Run anyway**.

**After Effects in an unusual folder?** The converter asks you to point at `AfterFX.exe` once and remembers it.

> **Tip:** if After Effects opens and nothing happens (no progress window), the Home screen probably blocked the hand-off. See [Troubleshooting](#nothing-happens-after-after-effects-opens).

---

## How to use (inside After Effects, or on Mac)

You can skip the `.bat` entirely:

1. Open After Effects and click **New project** to leave the Home screen.
2. Go to **File > Scripts > Run Script File...**
3. Choose `EC2AE_Converter.jsx`.
4. Pick your `.ecproj` file(s).

Each project is rebuilt inside the project you have open, in its own folder. Save when you're happy.

This works on macOS too, since the converter script itself runs in any After Effects.

---

## What carries over

**Project**
- Folders and folder structure
- Footage (images, video, audio), relinked automatically
- Solids and adjustment layers
- Project bit depth, linear blending and time display

**Compositions**
- Size, frame rate, duration and pixel aspect
- Work area, background colour and start timecode
- Motion blur settings (shutter angle, phase, samples)
- 3D renderer and preview resolution
- Comp markers

**Layers**
- Every layer type: footage, precomps, solids, adjustment layers, nulls, cameras, lights, text and shape layers
- Layer order, names, labels and comments
- In/out points, start time and time stretch
- Blend modes and preserve transparency
- Switches: 3D, motion blur, shy, solo, lock, visibility, audio, quality, sampling, frame blending, collapse, guide
- Parenting (including long null chains)
- Track mattes (alpha, luma and their inverted versions)
- Auto-orient
- Layer markers

**Properties and animation**
- Transform (including separated position), 3D orientation and rotation
- Material options and camera options (zoom, depth of field, iris)
- Masks: path, feather, opacity, expansion, mode, inverted, colour
- Keyframes with full easing: Bezier, linear and hold, speed and influence, continuous and auto-Bezier, spatial tangents, roving
- Expressions

**Effects**
- Effects and all their settings, matched by name so groups and repeated setting names land in the right place
- Built in: Keylight, Levels, Radial Blur, Ripple, Tritone, Linear Color Key, CC Page Turn, Grow Bounds, Drop Shadow, Strobe Light, Motion Tile, CC Toner and around 120 more AE effects recognised by name
- EffectCraft's renamed effects are mapped back to their AE originals (for example "Screen Color Key" becomes Keylight and "Page Curl" becomes CC Page Turn)

**Text**
- Source text with line breaks
- Font, size, fill and stroke colour, stroke width
- Tracking, leading, alignment, baseline shift, scaling, faux bold/italic, caps
- Path options and more options
- Text animators with range selectors and their properties

**Shape layers**
- Groups with their transforms
- Ellipse, rectangle, polystar and custom paths
- Fill and stroke (including dashes, taper and wave)
- Trim paths, repeater, round corners, merge, offset, pucker and bloat, twist, zig zag and wiggle

---

## After converting: quick checklist

Around 98% of a typical project converts correctly. The rest takes a few minutes to fix by hand. Check these:

- **Drop Shadow opacity.** EffectCraft stores it as a percentage, while After Effects reads it on a 0 to 255 scale, so shadows can look fainter. Set the opacity again in Effect Controls.
- **Other effect values.** A few effects may use different scales in the two programs. Compare the Effect Controls panel with EffectCraft if something looks off.
- **Fonts.** A font must be installed in Windows for After Effects to use it. Missing fonts are listed in the popup.
- **Missing footage.** If your files moved, the converter looks next to the `.ecproj` and in a `footage` or `assets` folder there. Anything it can't find becomes a placeholder. Right-click it and choose **Replace Footage > File**.
- **Skipped effects.** Effects that only exist in EffectCraft are listed in the popup. If After Effects has something similar, see [Teaching it new effects](#teaching-it-new-effects).

**Want the full list of notes?** Turn on **Edit > Preferences > Scripting & Expressions > Allow Scripts to Write Files and Access Network**. The converter then saves a `_EC2AE-log.txt` next to each `.aep`.

---

## Teaching it new effects

If the popup says an effect "has no After Effects match", you can map it yourself. No coding needed.

Open `ec2ae_effect_map.txt` (keep it next to the `.bat` or next to your `.ecproj`) and add one line per effect:

```
EffectCraft effect id = After Effects match name
```

For example:

```
ec.blur.gaussian = ADBE Gaussian Blur 2
ec.stylize.glow = ADBE Glo2
```

- The **EffectCraft id** appears in the popup in brackets, like `(ec.blur.gaussian)`. It's also in the `.ecproj` file as `"effect": "ec.something"`.
- The **After Effects match name** is AE's internal name for the effect. Built-in ones look like `ADBE Gaussian Blur 2`. Plugins have their own.

Run the conversion again and the effect will come through. If you map effects that others would find useful, please share them (see [Contributing](#contributing)).

---

## Troubleshooting

### Nothing happens after After Effects opens

If AE opens to the Home screen and no progress window appears, the Home screen blocked the script. Run it by hand:

1. Click **New project** in After Effects.
2. Go to **File > Scripts > Run Script File...**
3. Paste this into the File name box and press Enter:
   ```
   %APPDATA%\EC2AE\EC2AE_run.jsx
   ```

That runs the exact same conversion the `.bat` prepared. To avoid this in future, turn off the Home screen at launch in **Edit > Preferences > General**.

### "After Effects did not finish opening"

After Effects may be waiting on a sign-in, licence or update screen. Deal with that first and run the `.bat` again. If AE never opens at all, it may not be installed properly.

### "Not an EffectCraft project"

The file isn't valid EffectCraft JSON. Try a different save or auto-save of the project.

### "A new project could not be opened"

After Effects has unsaved changes in its current project and you cancelled the save prompt. Save or close that project, then try again.

### Conversion stops partway

The progress window shows the last step it reached. Please [open an issue](../../issues) with that step and any error text.

### Using a different After Effects version

The converter remembers the `AfterFX.exe` it used in `%APPDATA%\EC2AE\afterfx_path.txt`. Delete that file to make it search again, or set the `EC2AE_AFTERFX` environment variable to the full path of the `AfterFX.exe` you want.

---

## How it works

**Why After Effects has to be installed.** EffectCraft's `.ecproj` is open JSON, but After Effects' `.aep` is a closed binary format. A file written without After Effects would open broken or not at all. So the converter runs as a script **inside** After Effects, rebuilds everything through AE's own scripting API, and lets AE save a genuine `.aep`.

**The pieces:**

1. **`EffectCraft to After Effects.bat`** starts a PowerShell script stored inside the same file. That script:
   - collects the files you dropped (or opens a file picker)
   - checks each one is valid EffectCraft JSON using Windows' fast built-in parser
   - picks an output name that won't overwrite anything
   - finds the newest After Effects install (Program Files and the registry)
   - extracts the converter to `%APPDATA%\EC2AE\` and writes a small launcher script
   - opens After Effects, waits for it to be ready, sends the launcher, then watches for the `.aep`
2. **`EC2AE_Converter.jsx`** runs inside After Effects. It is plain ES3 JavaScript (ExtendScript) so it works in every AE version from CC 2018 up. It:
   - reads the JSON and creates folders, footage, solids and empty comps first, so precomps can point at any comp
   - builds each comp's layers bottom-up, sets parenting before transforms (so local values land unchanged), then applies properties, track mattes, visibility and locks in that order
   - maps EffectCraft property names to AE match names through lookup tables, and falls back to matching by display name, since EffectCraft keeps After Effects' names
   - matches effect settings by name in order, then by position for unnamed slots, which handles effects with grouped or repeated setting names

**Format notes**, useful if you want to improve the converter:

| EffectCraft | After Effects |
| --- | --- |
| Time in ticks, 254,016,000,000 per second | Seconds |
| Popup values start at 0 | Popup values start at 1 (most of them) |
| Ease influence from 0 to 1 | Influence from 0.1 to 100% |
| Layers listed top to bottom | Each new layer is added on top |
| Effect ids like `ec.blur.radial` | Match names like `ADBE Radial Blur` |

---

## Project files

```
EffectCraft to After Effects.bat   Windows launcher with the converter built in
EC2AE_Converter.jsx                The converter (run it from File > Scripts in AE)
ec2ae_effect_map.txt               Optional: your own effect mappings
README.md                          This file
LICENSE                            MIT License
```

---

## Contributing

Bug reports, effect mappings and code improvements are all welcome.

**Reporting a problem:** please [open an issue](../../issues) and include:

- your After Effects version
- the text from the final popup, or the `_EC2AE-log.txt` file
- what looks wrong, ideally with screenshots of the Effect Controls panel in EffectCraft and in After Effects
- a small `.ecproj` that shows the problem, if you can share one (footage isn't needed)

**Sending code:**

1. Fork this repository.
2. Make your change in `EC2AE_Converter.jsx` (keep it ES3: no `let`, `const`, arrow functions, `forEach` or `JSON`, since ExtendScript doesn't have them).
3. Test it in After Effects with File > Scripts > Run Script File.
4. Open a pull request describing what you changed and which AE version you tested.

The easiest contributions are new lines for the effect tables (`FX_BY_ID` and `FX_ALIASES` near the top of the converter).

---

## Author

**Rafiquzzaman Rafi**

If this saved you time, a star on the repository helps others find it.

---

## License

This project is released under the **MIT License**. You can use, copy, modify, merge, publish, distribute, sublicense and sell copies of it, as long as the copyright notice and license text stay with it. See the [LICENSE](LICENSE) file for the full text.

Copyright (c) 2026 Rafiquzzaman Rafi

---

## Disclaimer

This is an independent, community project. It is not affiliated with, endorsed by or supported by Adobe Inc. or the makers of EffectCraft. Adobe and After Effects are trademarks of Adobe Inc. EffectCraft is a trademark of its respective owner.

The software is provided "as is", without warranty of any kind. Keep a copy of your original `.ecproj` files. The converter never changes them, but backups are always good practice.
