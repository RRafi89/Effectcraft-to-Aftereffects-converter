@echo off
setlocal DisableDelayedExpansion
title EffectCraft to After Effects
rem ==========================================================================
rem  EffectCraft (.ecproj) to Adobe After Effects (.aep) converter
rem
rem  How to use:
rem    * Drag one or more .ecproj files (or a folder) onto this file, or
rem    * Double-click it and pick the files.
rem  After Effects opens, rebuilds each project and saves a .aep next to it.
rem
rem  Needs: Windows 10/11 and Adobe After Effects (CC 2018 or newer).
rem  Everything the converter needs lives inside this one file.
rem ==========================================================================

set "EC2AE_BAT=%~f0"
set /a EC2AE_N=0
:collect
if "%~1"=="" goto collected
set /a EC2AE_N+=1
set "EC2AE_F%EC2AE_N%=%~1"
shift
goto collect
:collected

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell was not found. It comes with every Windows 10 and 11 PC.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -Command "$t=[IO.File]::ReadAllText($env:EC2AE_BAT); $a='<'+'#EC2AE-PS'; $b='EC2AE-PS-END'+'#>'; $i=$t.IndexOf($a); $j=$t.IndexOf($b); if($i -lt 0 -or $j -lt $i){ Write-Host 'This converter file is damaged. Download it again.' -ForegroundColor Red; exit 1 }; & ([ScriptBlock]::Create($t.Substring($i+$a.Length, $j-$i-$a.Length)))"
set "EC2AE_RC=%ERRORLEVEL%"
echo.
if "%EC2AE_RC%"=="0" (
  echo   This window closes by itself in a few seconds.
  timeout /t 12 >nul
) else (
  pause
)
exit /b %EC2AE_RC%

rem ---- Everything below is read by PowerShell and After Effects, not by cmd ----
<#EC2AE-PS
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'EffectCraft to After Effects' } catch {}

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Fail([string]$m) { Say ''; Say ('  ' + $m) 'Red'; exit 1 }

Say ''
Say '  EffectCraft (.ecproj)  ->  After Effects (.aep)' 'Cyan'
Say '  ----------------------------------------------' 'DarkCyan'

$batPath = $env:EC2AE_BAT
$batDir  = Split-Path -Parent $batPath
$text    = [IO.File]::ReadAllText($batPath)

Add-Type -AssemblyName System.Windows.Forms
$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
$owner.ShowInTaskbar = $false

# ------------------------------------------------------------------ 1. which files
$inputs = New-Object System.Collections.Generic.List[string]
$count = 0
[void][int]::TryParse("$env:EC2AE_N", [ref]$count)
for ($i = 1; $i -le $count; $i++) {
    $p = [Environment]::GetEnvironmentVariable("EC2AE_F$i")
    if (-not $p) { continue }
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Filter '*.ecproj' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $inputs.Add($_.FullName) }
    } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
        $inputs.Add((Get-Item -LiteralPath $p).FullName)
    } else {
        Say ('  Skipped (not found): ' + $p) 'Yellow'
    }
}

if ($inputs.Count -eq 0) {
    Say '  Pick the EffectCraft project(s) to convert...'
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Pick EffectCraft project(s) to convert'
    $dlg.Filter = 'EffectCraft projects (*.ecproj)|*.ecproj|All files (*.*)|*.*'
    $dlg.Multiselect = $true
    if ($dlg.ShowDialog($owner) -ne [System.Windows.Forms.DialogResult]::OK) { Fail 'Nothing was picked.' }
    foreach ($f in $dlg.FileNames) { $inputs.Add($f) }
}

$jobs = New-Object System.Collections.Generic.List[object]
foreach ($f in $inputs) {
    try {
        $fs = [IO.File]::OpenRead($f)
        $buf = New-Object byte[] 8192
        $len = $fs.Read($buf, 0, $buf.Length)
        $fs.Close()
        $head = [Text.Encoding]::UTF8.GetString($buf, 0, $len).TrimStart([char]0xFEFF, ' ', "`t", "`r", "`n")
    } catch {
        Say ('  Skipped (cannot read): ' + $f) 'Yellow'
        continue
    }
    if (-not $head.StartsWith('{') -or $head -notmatch '"(schema|items)"') {
        Say ('  Skipped (not an EffectCraft project): ' + (Split-Path -Leaf $f)) 'Yellow'
        continue
    }
    $dir  = Split-Path -Parent $f
    $base = [IO.Path]::GetFileNameWithoutExtension($f)
    $out  = Join-Path $dir ($base + '.aep')
    $k = 2
    while ((Test-Path -LiteralPath $out) -or ($jobs | Where-Object { $_.Out -eq $out })) {
        $out = Join-Path $dir ($base + ' (' + $k + ').aep')
        $k++
    }
    $trusted = $false
    try {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $ser.RecursionLimit = 10000
        [void]$ser.DeserializeObject([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8))
        $trusted = $true
    } catch {
        try { [void]([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json); $trusted = $true } catch {}
    }
    if (-not $trusted) { Say ('  Note: could not pre-check ' + (Split-Path -Leaf $f) + '; After Effects will check it (slower).') 'DarkYellow' }
    $jobs.Add([pscustomobject]@{ In = $f; Out = $out; Trusted = $trusted })
}
if ($jobs.Count -eq 0) { Fail 'No EffectCraft projects to convert.' }

# ------------------------------------------------------------------ 2. find After Effects
$cfgDir = Join-Path $env:APPDATA 'EC2AE'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$savedAe = Join-Path $cfgDir 'afterfx_path.txt'

function Get-AEVersion([string]$exe) {
    try {
        $v = (Get-Item -LiteralPath $exe).VersionInfo
        return [version]('{0}.{1}' -f $v.FileMajorPart, $v.FileMinorPart)
    } catch { return [version]'0.0' }
}

$ae = $null
if ($env:EC2AE_AFTERFX -and (Test-Path -LiteralPath $env:EC2AE_AFTERFX)) { $ae = $env:EC2AE_AFTERFX }
if (-not $ae -and (Test-Path -LiteralPath $savedAe)) {
    $c = ([IO.File]::ReadAllText($savedAe)).Trim()
    if ($c -and (Test-Path -LiteralPath $c)) { $ae = $c }
}
if (-not $ae) {
    $cands = New-Object System.Collections.Generic.List[string]
    $roots = @($env:ProgramFiles, $env:ProgramW6432, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique
    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath (Join-Path $root 'Adobe') -Directory -Filter 'Adobe After Effects*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $exe = Join-Path $_.FullName 'Support Files\AfterFX.exe'
                if (Test-Path -LiteralPath $exe) { $cands.Add($exe) }
            }
    }
    Get-ChildItem -Path 'HKLM:\SOFTWARE\Adobe\After Effects' -ErrorAction SilentlyContinue | ForEach-Object {
        $ip = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).InstallPath
        if ($ip) {
            $exe = Join-Path $ip 'AfterFX.exe'
            if ((Test-Path -LiteralPath $exe) -and -not $cands.Contains($exe)) { $cands.Add($exe) }
        }
    }
    if ($cands.Count -gt 0) {
        $ae = $cands | Sort-Object @{ e = { if ($_ -match 'Beta') { 0 } else { 1 } } }, @{ e = { Get-AEVersion $_ } } -Descending |
              Select-Object -First 1
    }
}
if (-not $ae) {
    Say '  After Effects was not found automatically.' 'Yellow'
    Say '  Point me to AfterFX.exe. It usually lives in:'
    Say '  C:\Program Files\Adobe\Adobe After Effects 20xx\Support Files\'
    $dlg2 = New-Object System.Windows.Forms.OpenFileDialog
    $dlg2.Title = 'Where is AfterFX.exe?'
    $dlg2.Filter = 'After Effects (AfterFX.exe)|AfterFX.exe|Programs (*.exe)|*.exe'
    if ($dlg2.ShowDialog($owner) -ne [System.Windows.Forms.DialogResult]::OK) {
        Fail 'After Effects is needed to write .aep files. Install it, then run this again.'
    }
    $ae = $dlg2.FileName
}
[IO.File]::WriteAllText($savedAe, $ae)

# ------------------------------------------------------------------ 3. write the converter + a launcher script
$ma = '<' + '#EC2AE-JSX'
$mb = 'EC2AE-JSX-END' + '#>'
$ia = $text.IndexOf($ma)
$ib = $text.IndexOf($mb)
if ($ia -lt 0 -or $ib -lt $ia) { Fail 'This converter file is damaged. Download it again.' }
$jsx = $text.Substring($ia + $ma.Length, $ib - $ia - $ma.Length).Trim()
$jsxPath = Join-Path $cfgDir 'EC2AE_Converter.jsx'
[IO.File]::WriteAllText($jsxPath, $jsx, [Text.Encoding]::ASCII)

function Test-Ascii([string]$s) { return -not ($s -match '[^\x20-\x7E]') }
function JsStr([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq [char]'\') { [void]$sb.Append('/') }
        elseif ($ch -eq [char]'"') { [void]$sb.Append('\"') }
        elseif ($code -lt 32 -or $code -gt 126) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
        else { [void]$sb.Append($ch) }
    }
    return '"' + $sb.ToString() + '"'
}

# After Effects gets the launcher path on its command line, so keep that path plain ASCII
$runDir = $null
foreach ($d in @($cfgDir, (Join-Path $env:ProgramData 'EC2AE'), (Join-Path $env:SystemDrive 'EC2AE'))) {
    if (-not (Test-Ascii $d)) { continue }
    try {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $probe = Join-Path $d 'probe.tmp'
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force
        $runDir = $d
        break
    } catch {}
}
if (-not $runDir) {
    try { $runDir = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($cfgDir).ShortPath } catch { $runDir = $cfgDir }
}

$list = ($jobs | ForEach-Object { '{input:' + (JsStr $_.In) + ', output:' + (JsStr $_.Out) + ', trusted:' + $(if ($_.Trusted) { 'true' } else { 'false' }) + '}' }) -join (",`r`n    ")
$launcher  = "// Written by 'EffectCraft to After Effects.bat'. Safe to delete.`r`n"
$launcher += '$.global.EC2AE_JOBS = [' + "`r`n    " + $list + "`r`n];`r`n"
$launcher += '$.global.EC2AE_EXTRA_DIRS = [' + (JsStr $batDir) + '];' + "`r`n"
$launcher += '$.evalFile(new File(' + (JsStr $jsxPath) + '));' + "`r`n"
$launcherPath = Join-Path $runDir 'EC2AE_run.jsx'
[IO.File]::WriteAllText($launcherPath, $launcher, [Text.Encoding]::ASCII)

# ------------------------------------------------------------------ 4. hand over to After Effects
function Show-Manual {
    Say ''
    Say '  Run it by hand instead (takes 10 seconds):' 'Yellow'
    Say '    1. Open After Effects and wait until it has fully loaded.'
    Say '    2. File > Scripts > Run Script File...'
    Say ('    3. Pick this file:  ' + $launcherPath)
    Say '  That runs the exact same conversion. If AE shows an error, copy it and send it over.'
}
function Get-ReadyAE {
    Get-Process -Name 'AfterFX' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match 'After Effects' } |
        Select-Object -First 1
}

Say ''
foreach ($j in $jobs) { Say ('  ' + (Split-Path -Leaf $j.In) + '  ->  ' + (Split-Path -Leaf $j.Out)) 'Green' }
Say ''
Say ('  After Effects: ' + $ae) 'DarkGray'

$waitStart = [int]("0" + $env:EC2AE_WAIT_START); if ($waitStart -le 0) { $waitStart = 300 }
$waitDone  = [int]("0" + $env:EC2AE_WAIT_DONE);  if ($waitDone  -le 0) { $waitDone  = 900 }

# If AE is not open yet, start it plain and wait for its main window.
# Sending the script during the splash screen can make AE drop it.
if (-not (Get-ReadyAE)) {
    if (-not (Get-Process -Name 'AfterFX' -ErrorAction SilentlyContinue)) {
        Say '  Starting After Effects...'
        try { Start-Process -FilePath $ae } catch { Say ('  Could not start After Effects: ' + $_.Exception.Message) 'Red'; Show-Manual; exit 1 }
    } else {
        Say '  After Effects is still loading...'
    }
    $deadline = (Get-Date).AddSeconds($waitStart)
    $dots = 0
    while (-not (Get-ReadyAE)) {
        if ((Get-Date) -gt $deadline) {
            Say ''
            Say '  After Effects did not finish opening.' 'Red'
            Say '  If it is waiting on a sign-in, licence or update screen, deal with that first.'
            Say '  If it never opened at all, After Effects may not be installed properly on this PC.'
            Show-Manual
            exit 1
        }
        Start-Sleep -Seconds 2
        $dots++
        if ($dots % 5 -eq 0) { Write-Host '.' -NoNewline }
    }
    Write-Host ''
    Say '  After Effects is open. Giving it a moment to settle...'
    Start-Sleep -Seconds 10
}

Say '  Sending the conversion to After Effects...'
try {
    Start-Process -FilePath $ae -ArgumentList @('-r', ('"' + $launcherPath + '"'))
} catch {
    Say ('  Could not reach After Effects: ' + $_.Exception.Message) 'Red'
    Show-Manual
    exit 1
}

Say '  Converting. A progress window in After Effects shows each step.'
Say '  Waiting for the .aep file to appear...'
$t0 = Get-Date
$nextNote = 30
$deadline = (Get-Date).AddSeconds($waitDone)
$pending = New-Object System.Collections.Generic.List[object]
foreach ($j in $jobs) { $pending.Add($j) }
while ($pending.Count -gt 0) {
    foreach ($j in $pending.ToArray()) {
        if (Test-Path -LiteralPath $j.Out) {
            Say ('  Saved: ' + $j.Out) 'Green'
            [void]$pending.Remove($j)
        }
    }
    if ($pending.Count -eq 0) { break }
    if ((Get-Date) -gt $deadline -or -not (Get-Process -Name 'AfterFX' -ErrorAction SilentlyContinue)) {
        Say ''
        Say '  No .aep appeared for:' 'Red'
        foreach ($j in $pending) { Say ('    ' + (Split-Path -Leaf $j.In)) 'Red' }
        Say '  Look in After Effects for an error popup.'
        Show-Manual
        exit 1
    }
    $el = [int]((Get-Date) - $t0).TotalSeconds
    if ($el -ge $nextNote) {
        Say ('  Still working (' + [int][math]::Floor($el / 60) + 'm ' + ($el % 60) + 's). Look at After Effects: the progress window shows the current step; a popup means it needs you.') 'DarkYellow'
        $nextNote += 30
    }
    Start-Sleep -Seconds 2
}
Say ''
Say '  Done. Check the popup in After Effects for anything to review.' 'Cyan'
exit 0

EC2AE-PS-END#>

<#EC2AE-JSX
/*
    EC2AE_Converter.jsx
    EffectCraft (.ecproj)  ->  Adobe After Effects project

    Two ways to use it:
      1. Drop .ecproj files on "EffectCraft to After Effects.bat" (Windows).
         After Effects opens, this script rebuilds each project and saves a .aep
         next to the original file.
      2. In After Effects: File > Scripts > Run Script File... and pick this file.
         You choose one or more .ecproj files and they are rebuilt inside the
         project that is open right now (each in its own folder).

    What carries over: folders, footage (relinked), solids, comps and their
    settings, every layer type (footage, precomp, solid, adjustment, null,
    camera, light, text, shape), timing, stretch, switches, blend modes,
    parenting, track mattes, masks, transforms, 3D and material options,
    keyframes with easing, expressions, effects and their settings,
    text animators and shape-layer contents.

    Effects that have no After Effects match are listed in the final report.
    You can teach the converter new ones with ec2ae_effect_map.txt
    (one line per effect:  ec.some.effect = ADBE Match Name).

    The script is written in plain ES3 so it runs in every After Effects
    version from CC 2018 upward. Newer features (any-layer track mattes,
    font lookup) are used when the AE version has them.
*/

(function (GLOBAL) {

var EC2AE_VERSION = '1.0.2';
var TICKS = 254016000000;          // EffectCraft time unit: ticks per second
var ADD = 1;                       // table flag: group must be added with addProperty

// ---------------------------------------------------------------- helpers

function sec(t) { return (t || 0) / TICKS; }
function norm(s) { return String(s == null ? '' : s).toLowerCase().replace(/[^a-z0-9]/g, ''); }
function snake(s) { return String(s).replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase(); }
function trimStr(s) { return String(s).replace(/^\s+|\s+$/g, ''); }
function stripNum(s) { return trimStr(String(s).replace(/\s+\d+$/, '')); }
function fileNameOf(p) { var a = String(p).split(/[\\\/]/); return a[a.length - 1]; }
function isArr(a) { return a instanceof Array; }
function inArr(a, x) { if (!a) { return false; } for (var i = 0; i < a.length; i++) { if (a[i] == x) { return true; } } return false; }
function attempt(fn) { try { fn(); return true; } catch (e) { return false; } }
function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function enumVal(en, name, fallback) {
    if (!en || name == null) { return fallback; }
    var k = snake(name);
    if (en[k] !== undefined) { return en[k]; }
    k = String(name).toUpperCase();
    if (en[k] !== undefined) { return en[k]; }
    return fallback;
}

function readText(path) {
    var f = (path instanceof File) ? path : new File(path);
    if (!f.exists) { throw new Error('File not found: ' + f.fsName); }
    f.encoding = 'UTF-8';
    if (!f.open('r')) { throw new Error('Cannot open: ' + f.fsName); }
    var s = f.read();
    f.close();
    return s;
}

// JSON.parse is missing in ExtendScript. Validate the text the way json2.js
// does, so only real JSON reaches eval, then evaluate it.
function parseJSON(text, trusted) {
    if (text.charCodeAt(0) === 0xFEFF) { text = text.substring(1); }
    text = text.replace(/[\u2028\u2029]/g, function (c) {
        return '\\u' + ('0000' + c.charCodeAt(0).toString(16)).slice(-4);
    });
    if (trusted) { return eval('(' + text + ')'); }   // already validated by the .bat
    var check = text
        .replace(/\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})/g, '@')
        .replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g, ']')
        .replace(/(?:^|:|,)(?:\s*\[)+/g, '');
    if (!/^[\],:{}\s]*$/.test(check)) {
        throw new Error('This file is not valid JSON, so it is not an EffectCraft project this converter understands.');
    }
    return eval('(' + text + ')');
}

// ---------------------------------------------------------------- progress window

function Progress() {
    this.w = null;
    try {
        var w = new Window('palette', 'EffectCraft to After Effects');
        w.orientation = 'column';
        w.alignChildren = 'fill';
        w.margins = 16;
        this.t = w.add('statictext', undefined, 'Starting...');
        this.t.characters = 64;
        this.b = w.add('progressbar', undefined, 0, 100);
        this.b.preferredSize.width = 460;
        w.show();
        this.w = w;
    } catch (e) {}
}
Progress.prototype.set = function (msg, pct) {
    try { $.writeln('[EC2AE] ' + msg); } catch (e0) {}
    if (!this.w) { return; }
    try {
        this.t.text = msg;
        if (pct != null) { this.b.value = clamp(pct, 0, 100); }
        this.w.update();
    } catch (e) {}
};
Progress.prototype.close = function () { if (this.w) { try { this.w.close(); } catch (e) {} } };

// ---------------------------------------------------------------- report

function Log(name) {
    this.name = name;
    this.lines = [];
    this.warns = [];
    this.seen = {};
    this.stats = { comps: 0, layers: 0, footage: 0, missing: 0, effects: 0, effectsSkipped: 0, keys: 0 };
}
Log.prototype.info = function (m) { this.lines.push(m); };
Log.prototype.warn = function (m) {
    if (this.seen[m]) { return; }
    this.seen[m] = true;
    this.warns.push(m);
    this.lines.push('WARNING: ' + m);
};

// ---------------------------------------------------------------- lookup tables

var LABELS = {
    none: 0, red: 1, yellow: 2, aqua: 3, pink: 4, lavender: 5, peach: 6, seafoam: 7,
    blue: 8, green: 9, purple: 10, orange: 11, brown: 12, fuchsia: 13, cyan: 14,
    sandstone: 15, darkgreen: 16
};
function labelIndex(name) {
    if (typeof name === 'number') { return name; }
    var v = LABELS[norm(name)];
    return v === undefined ? null : v;
}

// EffectCraft effect id -> After Effects match name (ids seen in real projects)
var FX_BY_ID = {
    'ec.blur.radial': 'ADBE Radial Blur',
    'ec.distort.ripple': 'ADBE Ripple',
    'ec.color.levels': 'ADBE Easy Levels2',
    'ec.keying.keylight': 'Keylight 906',
    'ec.color.tritone': 'ADBE Tritone',
    'ec.key.linearcolor': 'ADBE Linear Color Key2',
    'ec.distort.ccpageturn': 'CC Page Turn',
    'ec.utility.growbounds': 'ADBE Grow Bounds',
    'ec.perspective.dropshadow': 'ADBE Drop Shadow',
    'ec.stylize.strobe': 'ADBE Strobe',
    'ec.stylize.motiontile': 'ADBE Tile',
    'ec.color.cctoner': 'CC Toner'
};

// After Effects match name -> names / id endings that point to it.
// Used for effect ids that are not in FX_BY_ID: the last part of the id
// (ec.blur.gaussian -> "gaussian") and the effect's display name are tried.
var FX_ALIASES = {
    'ADBE Gaussian Blur 2': 'gaussianblur gaussian',
    'ADBE Box Blur2': 'fastboxblur fastbox boxblur box fastblur',
    'ADBE Motion Blur': 'directionalblur directional',
    'ADBE Radial Blur': 'radialblur radial',
    'ADBE Camera Lens Blur': 'cameralensblur cameralens lensblur',
    'ADBE Channel Blur': 'channelblur',
    'ADBE Compound Blur': 'compoundblur',
    'ADBE Bilateral': 'bilateralblur bilateral',
    'CC Radial Fast Blur': 'ccradialfastblur radialfastblur',
    'CC Radial Blur': 'ccradialblur',
    'CC Vector Blur': 'ccvectorblur vectorblur',
    'ADBE Sharpen': 'sharpen',
    'ADBE Unsharp Mask2': 'unsharpmask unsharp',
    'ADBE Easy Levels2': 'levels',
    'ADBE Pro Levels2': 'levelsindividualcontrols',
    'ADBE CurvesCustom': 'curves',
    'ADBE HUE SATURATION': 'huesaturation huesat',
    'ADBE Brightness & Contrast 2': 'brightnesscontrast brightnessandcontrast',
    'ADBE Exposure2': 'exposure',
    'ADBE Tint': 'tint',
    'ADBE Tritone': 'tritone',
    'CC Toner': 'cctoner toner multitonetint',
    'ADBE Black&White': 'blackwhite blackandwhite',
    'ADBE Vibrance': 'vibrance',
    'ADBE Color Balance 2': 'colorbalance',
    'ADBE Color Balance (HLS)': 'colorbalancehls',
    'ADBE CHANNEL MIXER': 'channelmixer',
    'ADBE Photo Filter': 'photofilter',
    'ADBE Lumetri': 'lumetri lumetricolor',
    'ADBE Invert': 'invert',
    'ADBE Posterize': 'posterize',
    'ADBE Threshold2': 'threshold',
    'ADBE Change To Color': 'changetocolor',
    'ADBE Change Color': 'changecolor',
    'ADBE Leave Color': 'leavecolor',
    'APC Colorama': 'colorama',
    'ADBE Gamma/Pedestal/Gain2': 'gammapedestalgain',
    'ADBE Shadow/Highlight': 'shadowhighlight',
    'ADBE Selective Color': 'selectivecolor',
    'ADBE Fill': 'fill',
    'ADBE Ramp': 'gradientramp ramp',
    'ADBE 4ColorGradient': '4colorgradient fourcolorgradient',
    'ADBE Glo2': 'glow',
    'ADBE Tile': 'motiontile',
    'ADBE Strobe': 'strobe strobelight',
    'ADBE Mosaic': 'mosaic',
    'ADBE Find Edges': 'findedges',
    'ADBE Roughen Edges': 'roughenedges',
    'ADBE Noise': 'noise',
    'ADBE Fractal Noise': 'fractalnoise',
    'ADBE Turbulent Displace': 'turbulentdisplace',
    'ADBE Displacement Map': 'displacementmap',
    'ADBE Wave Warp': 'wavewarp',
    'ADBE Ripple': 'ripple',
    'ADBE Bulge': 'bulge',
    'ADBE Twirl': 'twirl',
    'ADBE Mirror': 'mirror',
    'ADBE Optics Compensation': 'opticscompensation',
    'ADBE Polar Coordinates': 'polarcoordinates',
    'ADBE Geometry2': 'transform',
    'ADBE Corner Pin': 'cornerpin',
    'ADBE Spherize': 'spherize',
    'ADBE Offset': 'offset',
    'CC Page Turn': 'ccpageturn pageturn pagecurl',
    'CC Bend It': 'ccbendit bendit',
    'CC Lens': 'cclens',
    'ADBE Drop Shadow': 'dropshadow',
    'ADBE Radial Shadow': 'radialshadow',
    'ADBE Bevel Alpha': 'bevelalpha',
    'ADBE Grow Bounds': 'growbounds',
    'ADBE Echo': 'echo',
    'ADBE Posterize Time': 'posterizetime',
    'ADBE Linear Color Key2': 'linearcolorkey linearcolor',
    'ADBE Color Key': 'colorkey',
    'ADBE Luma Key': 'lumakey',
    'ADBE Extract': 'extract',
    'ADBE Simple Choker': 'simplechoker',
    'ADBE Matte Choker': 'mattechoker',
    'ADBE Set Matte3': 'setmatte',
    'ADBE Set Channels': 'setchannels',
    'Keylight 906': 'keylight screencolorkey',
    'ADBE Stroke': 'stroke',
    'ADBE Vegas': 'vegas',
    'ADBE Linear Wipe': 'linearwipe',
    'ADBE Radial Wipe': 'radialwipe',
    'ADBE Venetian Blinds': 'venetianblinds',
    'ADBE Gradient Wipe': 'gradientwipe',
    'ADBE Block Dissolve': 'blockdissolve',
    'CC Light Sweep': 'cclightsweep lightsweep',
    'CC Light Rays': 'cclightrays lightrays',
    'CC Vignette': 'ccvignette vignette',
    'ADBE Lens Flare': 'lensflare',
    'ADBE Lightning 2': 'advancedlightning lightning',
    'ADBE Brush Strokes': 'brushstrokes',
    'ADBE Cartoonify': 'cartoon',
    'ADBE Scatter': 'scatter',
    'ADBE Write-on': 'writeon',
    'ADBE Cell Pattern': 'cellpattern',
    'ADBE Checkerboard': 'checkerboard',
    'ADBE Grid': 'grid',
    'ADBE Circle': 'circle',
    'ADBE Minimax': 'minimax',
    'ADBE Median': 'median',
    'ADBE Dust & Scratches': 'dustscratches dustandscratches',
    'ADBE Liquify': 'liquify',
    'ADBE Magnify': 'magnify',
    'ADBE Shift Channels': 'shiftchannels',
    'ADBE Slider Control': 'slidercontrol slider',
    'ADBE Point Control': 'pointcontrol',
    'ADBE Point3D Control': 'point3dcontrol 3dpointcontrol',
    'ADBE Angle Control': 'anglecontrol',
    'ADBE Checkbox Control': 'checkboxcontrol',
    'ADBE Color Control': 'colorcontrol',
    'ADBE Layer Control': 'layercontrol',
    'ADBE Dropdown Control': 'dropdownmenucontrol dropdowncontrol'
};
var FX_BY_ALIAS = {};
(function () {
    for (var mn in FX_ALIASES) {
        if (!FX_ALIASES.hasOwnProperty(mn)) { continue; }
        var a = FX_ALIASES[mn].split(' ');
        for (var i = 0; i < a.length; i++) { if (a[i]) { FX_BY_ALIAS[a[i]] = mn; } }
    }
})();

// Popups whose After Effects values are 0-based (most popups are 1-based).
var RAW_ENUM = { 'ADBE Casts Shadows': 1, 'ADBE Accepts Shadows': 1 };

// Property tree tables.  T[context][ecMatch] =
//    'ADBE Match Name'                         for a property
//    ['ADBE Match Name', childContext, ADD?]   for a group
// Anything not listed is found by its display name, which covers most of
// the rest because EffectCraft keeps After Effects' names.
var DIR = 'ADBE Vector Shape Direction';
var T = {
    layer: {
        transform: ['ADBE Transform Group', 'transform'],
        masks: ['ADBE Mask Parade', 'masks'],
        effects: ['ADBE Effect Parade', 'effects'],
        materialOptions: ['ADBE Material Options Group', 'material'],
        audio: ['ADBE Audio Group', 'audio'],
        text: ['ADBE Text Properties', 'text'],
        contents: ['ADBE Root Vectors Group', 'vectors'],
        cameraOptions: ['ADBE Camera Options Group', 'camera'],
        lightOptions: ['ADBE Light Options Group', 'light'],
        timeRemap: 'ADBE Time Remapping'
    },
    transform: {
        anchor: 'ADBE Anchor Point', poi: 'ADBE Anchor Point', pointOfInterest: 'ADBE Anchor Point',
        position: 'ADBE Position', xPosition: 'ADBE Position_0', yPosition: 'ADBE Position_1', zPosition: 'ADBE Position_2',
        scale: 'ADBE Scale', orientation: 'ADBE Orientation',
        rotationX: 'ADBE Rotate X', rotationY: 'ADBE Rotate Y', rotation: 'ADBE Rotate Z', rotationZ: 'ADBE Rotate Z',
        opacity: 'ADBE Opacity'
    },
    material: {
        castsShadows: 'ADBE Casts Shadows', lightTransmission: 'ADBE Light Transmission',
        acceptsShadows: 'ADBE Accepts Shadows', acceptsLights: 'ADBE Accepts Lights',
        ambient: 'ADBE Ambient Coefficient', diffuse: 'ADBE Diffuse Coefficient',
        specularIntensity: 'ADBE Specular Coefficient', specularShininess: 'ADBE Shininess Coefficient',
        metal: 'ADBE Metal Coefficient', reflectionIntensity: 'ADBE Reflection Coefficient',
        reflectionSharpness: 'ADBE Glossiness Coefficient', reflectionRolloff: 'ADBE Fresnel Coefficient',
        transparency: 'ADBE Transparency Coefficient', transparencyRolloff: 'ADBE Transp Rolloff',
        indexOfRefraction: 'ADBE Index of Refraction'
    },
    audio: { levels: 'ADBE Audio Levels' },
    camera: {
        zoom: 'ADBE Camera Zoom', dof: 'ADBE Camera Depth of Field', focusDistance: 'ADBE Camera Focus Distance',
        aperture: 'ADBE Camera Aperture', blurLevel: 'ADBE Camera Blur Level', irisShape: 'ADBE Iris Shape',
        irisRotation: 'ADBE Iris Rotation', irisRoundness: 'ADBE Iris Roundness',
        irisAspectRatio: 'ADBE Iris Aspect Ratio', irisDiffractionFringe: 'ADBE Iris Diffraction Fringe',
        highlightGain: 'ADBE Iris Highlight Gain', highlightThreshold: 'ADBE Iris Highlight Threshold',
        highlightSaturation: 'ADBE Iris Hightlight Saturation'
    },
    light: {
        intensity: 'ADBE Light Intensity', color: 'ADBE Light Color', coneAngle: 'ADBE Light Cone Angle',
        coneFeather: 'ADBE Light Cone Feather 2', falloff: 'ADBE Light Falloff Type',
        radius: 'ADBE Light Falloff Start', falloffDistance: 'ADBE Light Falloff Distance',
        castsShadows: 'ADBE Casts Shadows', shadowDarkness: 'ADBE Light Shadow Darkness',
        shadowDiffusion: 'ADBE Light Shadow Diffusion'
    },
    masks: { mask: ['ADBE Mask Atom', 'mask', ADD] },
    mask: { path: 'ADBE Mask Shape', feather: 'ADBE Mask Feather', opacity: 'ADBE Mask Opacity', expansion: 'ADBE Mask Offset' },
    text: {
        sourceText: 'ADBE Text Document',
        pathOptions: ['ADBE Text Path Options', 'textpath'],
        moreOptions: ['ADBE Text More Options', 'textmore'],
        animators: ['ADBE Text Animators', 'animators']
    },
    textpath: {
        path: 'ADBE Text Path', reversePath: 'ADBE Text Reverse Path',
        perpendicular: 'ADBE Text Perpendicular To Path', forceAlignment: 'ADBE Text Force Align Path',
        firstMargin: 'ADBE Text First Margin', lastMargin: 'ADBE Text Last Margin'
    },
    textmore: {
        anchorGrouping: 'ADBE Text Anchor Point Option', groupingAlignment: 'ADBE Text Anchor Point Align',
        fillStroke: 'ADBE Text Render Order', interCharBlend: 'ADBE Text Character Blend Mode'
    },
    animators: { animator: ['ADBE Text Animator', 'animator', ADD] },
    animator: {
        selectors: ['ADBE Text Selectors', 'selectors'],
        properties: ['ADBE Text Animator Properties', 'textprops']
    },
    selectors: {
        rangeSelector: ['ADBE Text Selector', 'range', ADD],
        wigglySelector: ['ADBE Text Wiggly Selector', null, ADD],
        expressionSelector: ['ADBE Text Expressible Selector', null, ADD]
    },
    range: {
        start: 'ADBE Text Percent Start', end: 'ADBE Text Percent End', offset: 'ADBE Text Percent Offset',
        startIndex: 'ADBE Text Index Start', endIndex: 'ADBE Text Index End', offsetIndex: 'ADBE Text Index Offset',
        advanced: ['ADBE Text Range Advanced', 'rangeadv']
    },
    rangeadv: {
        units: 'ADBE Text Range Units', basedOn: 'ADBE Text Range Type2', mode: 'ADBE Text Selector Mode',
        amount: 'ADBE Text Selector Max Amount', shape: 'ADBE Text Range Shape',
        smoothness: 'ADBE Text Selector Smoothness', easeHigh: 'ADBE Text Levels Max Ease',
        easeLow: 'ADBE Text Levels Min Ease', randomize: 'ADBE Text Randomize Order',
        randomSeed: 'ADBE Text Random Seed'
    },
    textprops: {
        _addProps: true,
        anchor: 'ADBE Text Anchor Point 3D', position: 'ADBE Text Position 3D', scale: 'ADBE Text Scale 3D',
        skew: 'ADBE Text Skew', skewAxis: 'ADBE Text Skew Axis', rotationX: 'ADBE Text Rotation X',
        rotationY: 'ADBE Text Rotation Y', rotation: 'ADBE Text Rotation', opacity: 'ADBE Text Opacity',
        fillColor: 'ADBE Text Fill Color', fillHue: 'ADBE Text Fill Hue', fillSaturation: 'ADBE Text Fill Saturation',
        fillBrightness: 'ADBE Text Fill Brightness', fillOpacity: 'ADBE Text Fill Opacity',
        strokeColor: 'ADBE Text Stroke Color', strokeHue: 'ADBE Text Stroke Hue',
        strokeSaturation: 'ADBE Text Stroke Saturation', strokeBrightness: 'ADBE Text Stroke Brightness',
        strokeOpacity: 'ADBE Text Stroke Opacity', strokeWidth: 'ADBE Text Stroke Width',
        lineAnchor: 'ADBE Text Line Anchor', lineSpacing: 'ADBE Text Line Spacing',
        trackingType: 'ADBE Text Track Type', tracking: 'ADBE Text Tracking Amount',
        characterAlignment: 'ADBE Text Character Change Type', characterRange: 'ADBE Text Character Range',
        characterValue: 'ADBE Text Character Replace', characterOffset: 'ADBE Text Character Offset',
        blur: 'ADBE Text Blur'
    },
    vectors: {
        group: ['ADBE Vector Group', 'vgroup', ADD],
        ellipse: ['ADBE Vector Shape - Ellipse', 'ellipse', ADD],
        rect: ['ADBE Vector Shape - Rect', 'rect', ADD],
        rectangle: ['ADBE Vector Shape - Rect', 'rect', ADD],
        star: ['ADBE Vector Shape - Star', 'star', ADD],
        polystar: ['ADBE Vector Shape - Star', 'star', ADD],
        path: ['ADBE Vector Shape - Group', 'vpath', ADD],
        shape: ['ADBE Vector Shape - Group', 'vpath', ADD],
        fill: ['ADBE Vector Graphic - Fill', 'fill', ADD],
        stroke: ['ADBE Vector Graphic - Stroke', 'stroke', ADD],
        gradientFill: ['ADBE Vector Graphic - G-Fill', null, ADD],
        gfill: ['ADBE Vector Graphic - G-Fill', null, ADD],
        gradientStroke: ['ADBE Vector Graphic - G-Stroke', null, ADD],
        gstroke: ['ADBE Vector Graphic - G-Stroke', null, ADD],
        merge: ['ADBE Vector Filter - Merge', null, ADD],
        mergePaths: ['ADBE Vector Filter - Merge', null, ADD],
        offsetPaths: ['ADBE Vector Filter - Offset', null, ADD],
        puckerBloat: ['ADBE Vector Filter - PB', null, ADD],
        repeater: ['ADBE Vector Filter - Repeater', 'repeater', ADD],
        roundCorners: ['ADBE Vector Filter - RC', null, ADD],
        trim: ['ADBE Vector Filter - Trim', 'trim', ADD],
        trimPaths: ['ADBE Vector Filter - Trim', 'trim', ADD],
        twist: ['ADBE Vector Filter - Twist', null, ADD],
        wigglePaths: ['ADBE Vector Filter - Wiggler', null, ADD],
        wiggleTransform: ['ADBE Vector Filter - Wiggle Transform', null, ADD],
        zigzag: ['ADBE Vector Filter - Roughen', null, ADD]
    },
    vgroup: {
        blend: 'ADBE Vector Blend Mode',
        contents: ['ADBE Vectors Group', 'vectors'],
        transform: ['ADBE Vector Transform Group', 'vtransform']
    },
    vtransform: {
        anchor: 'ADBE Vector Anchor', position: 'ADBE Vector Position', scale: 'ADBE Vector Scale',
        skew: 'ADBE Vector Skew', skewAxis: 'ADBE Vector Skew Axis', rotation: 'ADBE Vector Rotation',
        opacity: 'ADBE Vector Group Opacity'
    },
    ellipse: { direction: DIR, size: 'ADBE Vector Ellipse Size', position: 'ADBE Vector Ellipse Position' },
    rect: { direction: DIR, size: 'ADBE Vector Rect Size', position: 'ADBE Vector Rect Position', roundness: 'ADBE Vector Rect Roundness' },
    star: {
        direction: DIR, type: 'ADBE Vector Star Type', points: 'ADBE Vector Star Points',
        position: 'ADBE Vector Star Position', rotation: 'ADBE Vector Star Rotation',
        innerRadius: 'ADBE Vector Star Inner Radius', outerRadius: 'ADBE Vector Star Outer Radius',
        innerRoundness: 'ADBE Vector Star Inner Roundess', outerRoundness: 'ADBE Vector Star Outer Roundess'
    },
    vpath: { direction: DIR, path: 'ADBE Vector Shape', shape: 'ADBE Vector Shape' },
    fill: {
        blend: 'ADBE Vector Blend Mode', composite: 'ADBE Vector Composite Order', rule: 'ADBE Vector Fill Rule',
        color: 'ADBE Vector Fill Color', opacity: 'ADBE Vector Fill Opacity'
    },
    stroke: {
        blend: 'ADBE Vector Blend Mode', composite: 'ADBE Vector Composite Order',
        color: 'ADBE Vector Stroke Color', opacity: 'ADBE Vector Stroke Opacity', width: 'ADBE Vector Stroke Width',
        cap: 'ADBE Vector Stroke Line Cap', join: 'ADBE Vector Stroke Line Join', miter: 'ADBE Vector Stroke Miter Limit',
        dashes: ['ADBE Vector Stroke Dashes', 'dashes'],
        taper: ['ADBE Vector Stroke Taper', 'taper'],
        wave: ['ADBE Vector Stroke Wave', 'wave']
    },
    dashes: { _addProps: true, dash: 'ADBE Vector Stroke Dash 1', gap: 'ADBE Vector Stroke Gap 1', offset: 'ADBE Vector Stroke Offset' },
    taper: {
        units: 'ADBE Vector Taper Length Units', startLength: 'ADBE Vector Taper Start Length',
        endLength: 'ADBE Vector Taper End Length', startWidth: 'ADBE Vector Taper Start Width',
        endWidth: 'ADBE Vector Taper End Width', startEase: 'ADBE Vector Taper Start Ease',
        endEase: 'ADBE Vector Taper End Ease'
    },
    wave: {
        amount: 'ADBE Vector Taper Wave Amount', units: 'ADBE Vector Taper Wave Units',
        wavelength: 'ADBE Vector Taper Wavelength', cycles: 'ADBE Vector Taper Wave Cycles',
        phase: 'ADBE Vector Taper Wave Phase'
    },
    trim: { start: 'ADBE Vector Trim Start', end: 'ADBE Vector Trim End', offset: 'ADBE Vector Trim Offset', trimMultiple: 'ADBE Vector Trim Type' },
    repeater: {
        copies: 'ADBE Vector Repeater Copies', offset: 'ADBE Vector Repeater Offset',
        composite: 'ADBE Vector Repeater Order', transform: ['ADBE Vector Repeater Transform', 'rtransform']
    },
    rtransform: {
        anchor: 'ADBE Vector Repeater Anchor', position: 'ADBE Vector Repeater Position',
        scale: 'ADBE Vector Repeater Scale', rotation: 'ADBE Vector Repeater Rotation',
        startOpacity: 'ADBE Vector Repeater Opacity 1', endOpacity: 'ADBE Vector Repeater Opacity 2'
    }
};

// ---------------------------------------------------------------- user effect map

function loadUserEffectMap(dirs, log) {
    var map = {};
    for (var i = 0; i < dirs.length; i++) {
        if (!dirs[i]) { continue; }
        var f = new File(dirs[i] + '/ec2ae_effect_map.txt');
        if (!f.exists) { continue; }
        var txt;
        try { txt = readText(f); } catch (e) { continue; }
        var rows = txt.split(/\r\n|\r|\n/);
        var n = 0;
        for (var r = 0; r < rows.length; r++) {
            var row = trimStr(rows[r]);
            if (!row || row.charAt(0) == '#' || row.indexOf('=') < 0) { continue; }
            var k = trimStr(row.substring(0, row.indexOf('=')));
            var v = trimStr(row.substring(row.indexOf('=') + 1));
            if (k && v) { map[k] = v; n++; }
        }
        if (n) { log.info('Loaded ' + n + ' custom effect mapping(s) from ' + f.fsName); }
    }
    return map;
}

// ---------------------------------------------------------------- property helpers

function resolvePath(layer, path) {
    var o = layer;
    for (var i = 0; i < path.length; i++) { o = o.property(path[i]); if (!o) { return null; } }
    return o;
}

function safeChild(group, nameOrMatch) {
    try { return group.property(nameOrMatch) || null; } catch (e) { return null; }
}

// find a child by display name or match name, compared loosely
function findChild(group, ecNode) {
    var p = safeChild(group, ecNode.name);
    if (p) { return p; }
    var want1 = norm(ecNode.name), want2 = norm(ecNode.match);
    var n = 0;
    try { n = group.numProperties; } catch (e) { return null; }
    for (var i = 1; i <= n; i++) {
        var c = group.property(i);
        var cn = norm(c.name);
        if (cn == want1 || cn == want2) { return c; }
    }
    return null;
}

function tryAdd(group, candidates) {
    for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        if (!c) { continue; }
        var ok = false;
        try { ok = group.canAddProperty(c); } catch (e) { ok = false; }
        if (!ok) { continue; }
        try { var g = group.addProperty(c); if (g) { return g; } } catch (e2) {}
    }
    return null;
}

function dimsOf(p) {
    var t = p.propertyValueType;
    if (t == PropertyValueType.ThreeD || t == PropertyValueType.ThreeD_SPATIAL) { return 3; }
    if (t == PropertyValueType.TwoD || t == PropertyValueType.TwoD_SPATIAL) { return 2; }
    if (t == PropertyValueType.OneD) { return 1; }
    if (t == PropertyValueType.COLOR) { return 4; }
    return 0;
}

function fitDims(v, p, ecNode, isScale) {
    if (!isArr(v)) { v = [v]; }
    var n = dimsOf(p);
    if (n === 0) { return v; }
    if (n == 1) { return v[0]; }
    var out = [];
    for (var i = 0; i < n; i++) {
        out.push(i < v.length ? v[i] : (isScale ? 100 : (n == 4 ? 1 : 0)));
    }
    return out;
}

function makeShape(v) {
    var s = new Shape();
    s.vertices = v.vertices || [];
    s.inTangents = v.in_tangents || v.inTangents || [];
    s.outTangents = v.out_tangents || v.outTangents || [];
    s.closed = !!v.closed;
    return s;
}

function resolveFont(family, style) {
    if (!family) { return null; }
    try {
        if (app.fonts && app.fonts.getFontsByFamilyNameAndStyleName) {
            var arr = app.fonts.getFontsByFamilyNameAndStyleName(family, style || 'Regular');
            if (arr && arr.length) { return arr[0].postScriptName; }
        }
    } catch (e) {}
    var ps = String(family).replace(/\s+/g, '');
    if (style && norm(style) != 'regular') { ps += '-' + String(style).replace(/\s+/g, ''); }
    return ps;
}

var JUSTIFY = {
    left: 'LEFT_JUSTIFY', center: 'CENTER_JUSTIFY', centre: 'CENTER_JUSTIFY', right: 'RIGHT_JUSTIFY',
    fullleft: 'FULL_JUSTIFY_LASTLINE_LEFT', justifyleft: 'FULL_JUSTIFY_LASTLINE_LEFT',
    fullcenter: 'FULL_JUSTIFY_LASTLINE_CENTER', justifycenter: 'FULL_JUSTIFY_LASTLINE_CENTER',
    fullright: 'FULL_JUSTIFY_LASTLINE_RIGHT', justifyright: 'FULL_JUSTIFY_LASTLINE_RIGHT',
    full: 'FULL_JUSTIFY_LASTLINE_FULL', fullall: 'FULL_JUSTIFY_LASTLINE_FULL', justifyall: 'FULL_JUSTIFY_LASTLINE_FULL'
};

function makeTextDoc(v, p, env) {
    var d = p.value;
    var txt = String(v.text == null ? '' : v.text).replace(/\r\n|\n/g, '\r');
    attempt(function () { d.resetCharStyle(); });
    attempt(function () { d.resetParagraphStyle(); });
    d.text = txt;
    if (v.size != null) { attempt(function () { d.fontSize = v.size; }); }
    if (v.font) {
        var ps = resolveFont(v.font, v.style);
        var okFont = attempt(function () { d.font = ps; });
        if (!okFont || (d.font && norm(d.font) != norm(ps))) {
            env.log.warn('Font "' + v.font + (v.style ? ' ' + v.style : '') + '" is not installed in After Effects (layer "' + env.layerName + '"). Install it, then pick it in the Character panel.');
        }
    }
    attempt(function () { d.applyFill = v.apply_fill !== false; });
    if (v.fill) { attempt(function () { d.fillColor = [v.fill[0], v.fill[1], v.fill[2]]; }); }
    attempt(function () { d.applyStroke = !!v.apply_stroke; });
    if (v.stroke) { attempt(function () { d.strokeColor = [v.stroke[0], v.stroke[1], v.stroke[2]]; }); }
    if (v.stroke_width != null) { attempt(function () { d.strokeWidth = v.stroke_width; }); }
    if (v.stroke_over_fill != null) { attempt(function () { d.strokeOverFill = !!v.stroke_over_fill; }); }
    if (v.tracking != null) { attempt(function () { d.tracking = v.tracking; }); }
    if (v.leading == null) { attempt(function () { d.autoLeading = true; }); }
    else { attempt(function () { d.autoLeading = false; d.leading = v.leading; }); }
    if (v.justify) {
        var jk = JUSTIFY[norm(v.justify)];
        if (jk && ParagraphJustification[jk] !== undefined) { attempt(function () { d.justification = ParagraphJustification[jk]; }); }
    }
    if (v.baseline_shift != null) { attempt(function () { d.baselineShift = v.baseline_shift; }); }
    if (v.h_scale != null) { attempt(function () { d.horizontalScale = v.h_scale / 100; }); }
    if (v.v_scale != null) { attempt(function () { d.verticalScale = v.v_scale / 100; }); }
    if (v.tsume) { attempt(function () { d.tsume = v.tsume; }); }
    if (v.faux_bold) { attempt(function () { d.fauxBold = true; }); }
    if (v.faux_italic) { attempt(function () { d.fauxItalic = true; }); }
    if (v.all_caps) { attempt(function () { d.allCaps = true; }); }
    if (v.small_caps) { attempt(function () { d.smallCaps = true; }); }
    if (v.ligatures === false) { attempt(function () { d.ligature = false; }); }
    if (v.indent_first) { attempt(function () { d.firstLineIndent = v.indent_first; }); }
    if (v.indent_left) { attempt(function () { d.startIndent = v.indent_left; }); }
    if (v.indent_right) { attempt(function () { d.endIndent = v.indent_right; }); }
    if (v.space_before) { attempt(function () { d.spaceBefore = v.space_before; }); }
    if (v.space_after) { attempt(function () { d.spaceAfter = v.space_after; }); }
    return d;
}

// convert an EffectCraft value {t, v} to what the AE property expects
function conv(val, p, ecNode, env) {
    if (!val) { return undefined; }
    var t = val.t, v = val.v;
    var pvt = p.propertyValueType;
    var isScale = (ecNode.match == 'scale' || norm(ecNode.name).indexOf('scale') >= 0);
    switch (t) {
        case 'Scalar': case 'Number': case 'Float': case 'Int':
            return isArr(v) ? fitDims(v, p, ecNode, isScale) : (dimsOf(p) > 1 ? fitDims([v], p, ecNode, isScale) : v);
        case 'Enum':
            if (pvt == PropertyValueType.LAYER_INDEX || pvt == PropertyValueType.MASK_INDEX || RAW_ENUM[p.matchName]) { return v; }
            return v + 1;
        case 'Bool':
            return v ? 1 : 0;
        case 'Vec2': case 'Vec3': case 'Vec4': case 'Point':
            return fitDims(v, p, ecNode, isScale);
        case 'Color':
            if (pvt == PropertyValueType.COLOR) { return [v[0], v[1], v[2], v.length > 3 ? v[3] : 1]; }
            return fitDims(v, p, ecNode, false);
        case 'Path':
            return makeShape(v);
        case 'Text':
            return makeTextDoc(v, p, env);
        case 'Layer':
            var id = (v && typeof v === 'object') ? (v.layer || v.id) : v;
            var L = env.layerById[id];
            return L ? L.index : 0;
        default:
            return undefined;
    }
}

function sameVal(p, v) {
    var cur;
    try { cur = p.value; } catch (e) { return false; }
    if (typeof v === 'number') { return typeof cur === 'number' && Math.abs(cur - v) < 1e-4; }
    if (isArr(v) && isArr(cur)) {
        for (var i = 0; i < v.length && i < cur.length; i++) { if (Math.abs(cur[i] - v[i]) > 1e-4) { return false; } }
        return true;
    }
    return false;
}

function removeAllKeys(p) {
    try { while (p.numKeys > 0) { p.removeKey(p.numKeys); } } catch (e) {}
}

function interpType(s) {
    if (s == 'Hold') { return KeyframeInterpolationType.HOLD; }
    if (s == 'Bezier') { return KeyframeInterpolationType.BEZIER; }
    return KeyframeInterpolationType.LINEAR;
}

function easeDims(p) {
    var t = p.propertyValueType;
    if (t == PropertyValueType.ThreeD) { return 3; }
    if (t == PropertyValueType.TwoD) { return 2; }
    return 1;
}

function mkEase(arr, n) {
    var out = [], i;
    if (!arr || !arr.length) {
        for (i = 0; i < n; i++) { out.push(new KeyframeEase(0, 16.666667)); }
        return out;
    }
    if (n == 1 && arr.length > 1) {        // spatial: one ease along the motion path
        var s2 = 0, inf = 0;
        for (i = 0; i < arr.length; i++) {
            s2 += (arr[i].speed || 0) * (arr[i].speed || 0);
            inf = Math.max(inf, arr[i].influence || 0);
        }
        out.push(new KeyframeEase(Math.sqrt(s2), clamp(inf * 100, 0.1, 100)));
        return out;
    }
    for (i = 0; i < n; i++) {
        var e = arr[Math.min(i, arr.length - 1)];
        var infl = (e.influence == null) ? (1 / 6) : e.influence;
        out.push(new KeyframeEase(e.speed || 0, clamp(infl * 100, 0.1, 100)));
    }
    return out;
}

function setEase(p, idx, k) {
    var tries = [easeDims(p), 1, 2, 3];
    for (var j = 0; j < tries.length; j++) {
        try { p.setTemporalEaseAtKey(idx, mkEase(k.in_ease, tries[j]), mkEase(k.out_ease, tries[j])); return; } catch (e) {}
    }
}

function fitArr(v, n) {
    var out = [];
    v = v || [];
    for (var i = 0; i < n; i++) { out.push(i < v.length ? v[i] : 0); }
    return out;
}

function setKeys(c, p, env) {
    removeAllKeys(p);
    var keys = c.keys, recs = [], i;
    for (i = 0; i < keys.length; i++) {
        var k = keys[i];
        var v = conv(k.value, p, c, env);
        if (v === undefined) { continue; }
        var t = sec(k.time);
        try { p.setValueAtTime(t, v); recs.push({ t: t, k: k }); }
        catch (e) { env.log.warn('Keyframe on "' + c.name + '" (layer "' + env.layerName + '") could not be set: ' + e.message); }
    }
    if (!recs.length) {
        var sv = conv(c.value, p, c, env);
        if (sv !== undefined) { attempt(function () { p.setValue(sv); }); }
        return;
    }
    env.log.stats.keys += recs.length;
    var spatial = false;
    try { spatial = p.isSpatial; } catch (e2) {}
    var sd = dimsOf(p) || 3;
    for (i = 0; i < recs.length; i++) {
        var r = recs[i], kk = r.k, idx;
        try { idx = p.nearestKeyIndex(r.t); } catch (e3) { continue; }
        if ((kk.in_ease && kk.in_ease.length) || (kk.out_ease && kk.out_ease.length)) { setEase(p, idx, kk); }
        attempt(function () { p.setInterpolationTypeAtKey(idx, interpType(kk.in_interp), interpType(kk.out_interp)); });
        if (kk.continuous) { attempt(function () { p.setTemporalContinuousAtKey(idx, true); }); }
        if (kk.auto_bezier) { attempt(function () { p.setTemporalAutoBezierAtKey(idx, true); }); }
        if (spatial) {
            if (kk.spatial_auto) { attempt(function () { p.setSpatialAutoBezierAtKey(idx, true); }); }
            else {
                attempt(function () { p.setSpatialAutoBezierAtKey(idx, false); });
                attempt(function () { p.setSpatialTangentsAtKey(idx, fitArr(kk.spatial_in, sd), fitArr(kk.spatial_out, sd)); });
            }
            if (kk.spatial_continuous) { attempt(function () { p.setSpatialContinuousAtKey(idx, true); }); }
        }
        if (kk.roving) { attempt(function () { p.setRovingAtKey(idx, true); }); }
    }
}

function applyProp(c, p, env) {
    if (!p || p.propertyType != PropertyType.PROPERTY) { return; }
    var pvt = p.propertyValueType;
    if (pvt == PropertyValueType.NO_VALUE || pvt == PropertyValueType.CUSTOM_VALUE) { return; }
    if (c.three_d_only && !env.is3D) { return; }
    if (c.keys && c.keys.length) {
        setKeys(c, p, env);
    } else if (c.value) {
        var v = conv(c.value, p, c, env);
        if (v !== undefined) {
            try {
                if (p.numKeys > 0) { removeAllKeys(p); }
                p.setValue(v);
            } catch (e) {
                if (!sameVal(p, v) && !(c.ui && c.ui.kind == 'Hidden')) {
                    env.log.warn('Could not set "' + c.name + '" on layer "' + env.layerName + '": ' + e.message);
                }
            }
        } else if (c.value.t && c.value.t != 'Text') {
            env.log.warn('Value type "' + c.value.t + '" of "' + c.name + '" (layer "' + env.layerName + '") is not supported yet.');
        }
    }
    if (c.expr && c.expr.text) {
        try {
            p.expression = c.expr.text;
            p.expressionEnabled = c.expr.enabled !== false;
        } catch (e4) {
            env.log.warn('Expression on "' + c.name + '" (layer "' + env.layerName + '") was rejected: ' + e4.message);
        }
    }
}

// ---------------------------------------------------------------- effects

function effectCandidates(c, env) {
    var id = (c.kind && c.kind.effect) || c.match || '';
    var out = [];
    if (env.userFx[id]) { out.push(env.userFx[id]); }
    if (FX_BY_ID[id]) { out.push(FX_BY_ID[id]); }
    var parts = String(id).split('.');
    var last = norm(parts[parts.length - 1]);
    var keys = [last, norm(c.name), norm(stripNum(c.name))];
    if (last.indexOf('cc') === 0) { keys.push(last.substring(2)); }
    for (var i = 0; i < keys.length; i++) { if (FX_BY_ALIAS[keys[i]]) { out.push(FX_BY_ALIAS[keys[i]]); } }
    out.push(c.name);
    out.push(stripNum(c.name));
    return out;
}

function flatEC(node, out) {
    var kids = node.children || [];
    for (var i = 0; i < kids.length; i++) {
        if (kids[i].node == 'Group') { flatEC(kids[i], out); } else { out.push(kids[i]); }
    }
    return out;
}

function flatAE(group, out) {
    var n = 0;
    try { n = group.numProperties; } catch (e) { return out; }
    for (var i = 1; i <= n; i++) {
        var p = group.property(i);
        if (p.propertyType == PropertyType.PROPERTY) {
            var t = p.propertyValueType;
            if (t != PropertyValueType.NO_VALUE && t != PropertyValueType.CUSTOM_VALUE) { out.push(p); }
        } else {
            flatAE(p, out);
        }
    }
    return out;
}

function typeFits(ecNode, p) {
    var t = ecNode.value ? ecNode.value.t : '';
    var pvt = p.propertyValueType, PVT = PropertyValueType;
    if (t == 'Color') { return pvt == PVT.COLOR; }
    if (t == 'Path') { return pvt == PVT.SHAPE; }
    if (t == 'Vec2' || t == 'Vec3') { return pvt == PVT.TwoD || pvt == PVT.TwoD_SPATIAL || pvt == PVT.ThreeD || pvt == PVT.ThreeD_SPATIAL; }
    return pvt == PVT.OneD || pvt == PVT.LAYER_INDEX || pvt == PVT.MASK_INDEX;
}

// match EffectCraft parameters to AE parameters: by name in order first,
// then by position when the name is unknown but the slot is clearly free
function applyEffectParams(c, fx, env) {
    var ecList = flatEC(c, []);
    var aeList = flatAE(fx, []);
    var aeNames = [], used = [], i, j;
    for (j = 0; j < aeList.length; j++) { aeNames.push(norm(aeList[j].name)); used.push(false); }
    var remaining = {};
    for (i = 0; i < ecList.length; i++) {
        remaining[norm(ecList[i].name)] = (remaining[norm(ecList[i].name)] || 0) + 1;
        remaining[norm(ecList[i].match)] = (remaining[norm(ecList[i].match)] || 0) + 1;
    }
    var cursor = 0;
    for (i = 0; i < ecList.length; i++) {
        var e = ecList[i], n1 = norm(e.name), n2 = norm(e.match), found = -1;
        remaining[n1]--; remaining[n2]--;
        for (j = cursor; j < aeList.length && found < 0; j++) { if (!used[j] && (aeNames[j] == n1 || aeNames[j] == n2)) { found = j; } }
        for (j = 0; j < cursor && found < 0; j++) { if (!used[j] && (aeNames[j] == n1 || aeNames[j] == n2)) { found = j; } }
        if (found < 0) {
            j = cursor;
            while (j < aeList.length && used[j]) { j++; }
            if (j < aeList.length && !(remaining[aeNames[j]] > 0) && typeFits(e, aeList[j])) { found = j; }
        }
        if (found < 0) {
            if (!(e.ui && e.ui.kind == 'Hidden')) {
                env.log.warn('Effect "' + c.name + '" on layer "' + env.layerName + '": setting "' + e.name + '" has no match in After Effects.');
            }
            continue;
        }
        used[found] = true;
        cursor = found + 1;
        applyProp(e, aeList[found], env);
    }
}

function addEffect(c, layer, path, env) {
    var parade = resolvePath(layer, path);
    if (!parade) { return; }
    var fx = tryAdd(parade, effectCandidates(c, env));
    var id = (c.kind && c.kind.effect) || c.match;
    if (!fx) {
        env.log.stats.effectsSkipped++;
        env.log.warn('Effect "' + c.name + '" (' + id + ') on layer "' + env.layerName + '" has no After Effects match and was skipped. Add it to ec2ae_effect_map.txt to fix this.');
        return;
    }
    env.log.stats.effects++;
    var fpath = path.concat([fx.propertyIndex]);
    fx = resolvePath(layer, fpath);
    applyEffectParams(c, fx, env);
    if (c.enabled === false) { attempt(function () { resolvePath(layer, fpath).enabled = false; }); }
}

// ---------------------------------------------------------------- generic group walk

function maskAttrs(c, m, env) {
    var k = c.kind || {};
    if (k.mode) { attempt(function () { m.maskMode = enumVal(MaskMode, k.mode, MaskMode.ADD); }); }
    if (k.inverted) { attempt(function () { m.inverted = true; }); }
    if (k.color && k.color.length >= 3) {
        var d = (k.color[0] > 1 || k.color[1] > 1 || k.color[2] > 1) ? 255 : 1;
        attempt(function () { m.color = [k.color[0] / d, k.color[1] / d, k.color[2] / d]; });
    }
    if (k.motion_blur) { attempt(function () { m.maskMotionBlur = enumVal(MaskMotionBlur, k.motion_blur, MaskMotionBlur.SAME_AS_LAYER); }); }
    if (k.feather_falloff) {
        attempt(function () { m.maskFeatherFalloff = (norm(k.feather_falloff) == 'linear') ? MaskFeatherFalloff.FFO_LINEAR : MaskFeatherFalloff.FFO_SMOOTH; });
    }
    if (k.roto_bezier) { attempt(function () { m.rotoBezier = true; }); }
}

function allZero(node) {
    var kids = flatEC(node, []);
    for (var i = 0; i < kids.length; i++) {
        var k = kids[i];
        if ((k.keys && k.keys.length) || (k.expr && k.expr.text)) { return false; }
        if (k.value && typeof k.value.v === 'number' && k.value.v !== 0) { return false; }
    }
    return true;
}

function getGroup(c, parent, ctx, env) {
    var tbl = T[ctx] || {};
    var e = tbl.hasOwnProperty(c.match) ? tbl[c.match] : null;
    var mn = e ? (typeof e === 'string' ? e : e[0]) : null;
    var childCtx = (e && typeof e !== 'string') ? e[1] : null;
    var isAdd = (e && typeof e !== 'string' && e[2] === ADD) ||
                (c.kind && (c.kind.kind == 'Indexed' || c.kind.kind == 'Mask'));
    var g = null;
    if (isAdd) {
        g = tryAdd(parent, [mn, c.name, stripNum(c.name)]);
    } else {
        if (mn) { g = safeChild(parent, mn); }
        if (!g) { g = findChild(parent, c); }
    }
    return { g: g, ctx: childCtx || 'generic', added: isAdd };
}

function getProp(c, parent, ctx) {
    var tbl = T[ctx] || {};
    var mn = tbl.hasOwnProperty(c.match) ? tbl[c.match] : null;
    if (mn && typeof mn !== 'string') { mn = mn[0]; }
    var p = null;
    if (mn) { p = safeChild(parent, mn); }
    if (!p) { p = findChild(parent, c); }
    if (!p && tbl._addProps) { p = tryAdd(parent, [mn, c.name]); }
    return p;
}

function applyGroup(ecG, layer, path, ctx, env) {
    var kids = ecG.children || [];
    if (ctx == 'dashes' && allZero(ecG)) { return; }

    if (ctx == 'transform') {
        var sep = false;
        for (var s = 0; s < kids.length; s++) { if (kids[s].match == 'xPosition') { sep = true; } }
        if (sep) {
            attempt(function () { resolvePath(layer, path).property('ADBE Position').dimensionsSeparated = true; });
        }
    }

    for (var i = 0; i < kids.length; i++) {
        var c = kids[i];
        var parent = resolvePath(layer, path);
        if (!parent) { env.log.warn('Lost track of a property group on layer "' + env.layerName + '".'); return; }

        if (c.node == 'Group') {
            if (ctx == 'effects') { addEffect(c, layer, path, env); continue; }
            if (ctx == 'layer' && c.match == 'masks' && !(c.children && c.children.length)) { continue; }
            var r = getGroup(c, parent, ctx, env);
            if (!r.g) {
                if (c.children && c.children.length) {
                    env.log.warn('"' + c.name + '" on layer "' + env.layerName + '" has no After Effects equivalent and was skipped.');
                }
                continue;
            }
            var cpath = path.concat([r.g.propertyIndex]);
            if (c.kind && c.kind.kind == 'Mask') { maskAttrs(c, r.g, env); }
            if (r.added && c.name) { attempt(function () { resolvePath(layer, cpath).name = c.name; }); }
            applyGroup(c, layer, cpath, r.ctx, env);
            if (c.enabled === false) { attempt(function () { resolvePath(layer, cpath).enabled = false; }); }
            if (c.kind && c.kind.kind == 'Mask' && c.kind.locked) { attempt(function () { resolvePath(layer, cpath).locked = true; }); }
        } else {
            if (ctx == 'text' && c.match == 'perChar3d') {
                if (c.value && c.value.v) { attempt(function () { layer.threeDPerChar = true; }); }
                continue;
            }
            if (ctx == 'transform' && c.match == 'position' && kids.length && hasMatch(kids, 'xPosition')) { continue; }
            var p = getProp(c, parent, ctx);
            if (!p) {
                if (!(c.ui && c.ui.kind == 'Hidden') && !c.three_d_only) {
                    env.log.warn('"' + c.name + '" on layer "' + env.layerName + '" has no After Effects equivalent and was skipped.');
                }
                continue;
            }
            applyProp(c, p, env);
        }
    }
}

function hasMatch(kids, m) {
    for (var i = 0; i < kids.length; i++) { if (kids[i].match == m) { return true; } }
    return false;
}

// ---------------------------------------------------------------- markers

function addMarkers(markerProp, list, log, where) {
    if (!list || !list.length || !markerProp) { return; }
    for (var i = 0; i < list.length; i++) {
        var m = list[i];
        try {
            var mv = new MarkerValue(String(m.comment || m.name || m.text || ''));
            if (m.duration) { mv.duration = sec(m.duration); }
            if (m.chapter) { mv.chapter = String(m.chapter); }
            if (m.url) { mv.url = String(m.url); }
            if (m.label != null) { var li = labelIndex(m.label); if (li != null) { mv.label = li; } }
            markerProp.setValueAtTime(sec(m.time != null ? m.time : m.start), mv);
        } catch (e) {
            log.warn('A marker on ' + where + ' could not be copied.');
        }
    }
}

// ---------------------------------------------------------------- project items

function locateFile(path, dirs) {
    if (path) {
        var f = new File(path);
        if (f.exists) { return f; }
    }
    var name = fileNameOf(path || '');
    if (!name) { return null; }
    for (var i = 0; i < dirs.length; i++) {
        if (!dirs[i]) { continue; }
        var g = new File(dirs[i] + '/' + name);
        if (g.exists) { return g; }
    }
    return null;
}

function importFootage(it, env) {
    var k = it.kind;
    var item = null;
    var f = locateFile(k.path, env.searchDirs);
    if (f) {
        try {
            var io = new ImportOptions(f);
            try { io.sequence = false; } catch (e0) {}
            try { if (io.canImportAs(ImportAsType.FOOTAGE)) { io.importAs = ImportAsType.FOOTAGE; } } catch (e1) {}
            item = app.project.importFile(io);
        } catch (e) {
            env.log.warn('After Effects could not import "' + f.fsName + '" (' + e.message + '). A placeholder was used.');
        }
    }
    if (!item) {
        if (!f) { env.log.warn('Missing file: ' + k.path + ' - a placeholder was created. Right-click it > Replace Footage > File to relink.'); }
        env.log.stats.missing++;
        var w = Math.max(4, k.width || 1920), h = Math.max(4, k.height || 1080);
        var fr = k.frame_rate ? (k.frame_rate.num / (k.frame_rate.den || 1)) : 30;
        var dur = sec(k.duration);
        if (!(dur > 0)) { dur = 600; }
        item = app.project.importPlaceholder(it.name || fileNameOf(k.path), w, h, clamp(fr, 1, 999), dur);
    }
    env.log.stats.footage++;
    attempt(function () { item.name = it.name; });
    if (item.mainSource) {
        if (k.alpha) {
            var am = { ignore: 'IGNORE', straight: 'STRAIGHT', premultiplied: 'PREMULTIPLIED' }[norm(k.alpha)];
            if (am) { attempt(function () { item.mainSource.alphaMode = AlphaMode[am]; }); }
            if (am == 'PREMULTIPLIED' && k.premul_color) { attempt(function () { item.mainSource.premulColor = k.premul_color; }); }
        }
        if (k.loop_count && k.loop_count > 1) { attempt(function () { item.mainSource.loop = k.loop_count; }); }
        if (k.native_rate && k.frame_rate) {
            attempt(function () { item.mainSource.conformFrameRate = k.frame_rate.num / (k.frame_rate.den || 1); });
        }
    }
    return item;
}

function createSolids(solids, env) {
    if (!solids.length) { return; }
    var tmp = app.project.items.addComp('__ec2ae_temp__', 100, 100, 1, 1, 30);
    for (var i = 0; i < solids.length; i++) {
        var it = solids[i], k = it.kind;
        try {
            var col = k.color || [0, 0, 0];
            var L = tmp.layers.addSolid([col[0], col[1], col[2]], it.name,
                clamp(Math.round(k.width || 1920), 4, 30000), clamp(Math.round(k.height || 1080), 4, 30000),
                k.pixel_aspect || 1, 1);
            var src = L.source;
            if (!env.aeSolidsFolder && src.parentFolder && src.parentFolder != app.project.rootFolder) {
                env.aeSolidsFolder = src.parentFolder;
            }
            env.itemMap[it.id] = src;
        } catch (e) {
            env.log.warn('Solid "' + it.name + '" could not be created: ' + e.message);
        }
    }
    attempt(function () { tmp.remove(); });
}

var RENDERERS = { classic3d: 'ADBE Advanced 3d', cinema4d: 'ADBE Ernst', advanced3d: 'ADBE Calder' };
var RES = { full: [1, 1], half: [2, 2], third: [3, 3], quarter: [4, 4] };

function createComp(it, env) {
    var k = it.kind;
    var fps = k.frame_rate ? (k.frame_rate.num / (k.frame_rate.den || 1)) : 30;
    var dur = sec(k.duration);
    if (!(dur > 0)) { dur = 10; }
    var comp = app.project.items.addComp(it.name,
        clamp(Math.round(k.width || 1920), 4, 30000), clamp(Math.round(k.height || 1080), 4, 30000),
        k.pixel_aspect || 1, clamp(dur, 1 / fps, 10800), clamp(fps, 1, 999));
    env.log.stats.comps++;
    if (k.background) { attempt(function () { comp.bgColor = [k.background[0], k.background[1], k.background[2]]; }); }
    if (k.display_start) { attempt(function () { comp.displayStartTime = sec(k.display_start); }); }
    if (k.work_area && k.work_area.length == 2) {
        var ws = clamp(sec(k.work_area[0]), 0, comp.duration);
        var we = clamp(sec(k.work_area[1]), 0, comp.duration);
        if (we - ws > 0) {
            attempt(function () { comp.workAreaStart = ws; comp.workAreaDuration = we - ws; });
        }
    }
    if (k.shutter_angle != null) { attempt(function () { comp.shutterAngle = k.shutter_angle; }); }
    if (k.shutter_phase != null) { attempt(function () { comp.shutterPhase = k.shutter_phase; }); }
    if (k.motion_blur_samples) { attempt(function () { comp.motionBlurSamplesPerFrame = k.motion_blur_samples; }); }
    if (k.motion_blur_adaptive_limit) { attempt(function () { comp.motionBlurAdaptiveSampleLimit = k.motion_blur_adaptive_limit; }); }
    attempt(function () { comp.hideShyLayers = !!k.hide_shy; });
    attempt(function () { comp.motionBlur = !!k.enable_motion_blur; });
    attempt(function () { comp.frameBlending = !!k.enable_frame_blending; });
    attempt(function () { comp.draft3d = !!k.draft_3d; });
    attempt(function () { comp.preserveNestedFrameRate = !!k.preserve_frame_rate; });
    attempt(function () { comp.preserveNestedResolution = !!k.preserve_resolution; });
    if (k.resolution && RES[norm(k.resolution)]) { attempt(function () { comp.resolutionFactor = RES[norm(k.resolution)]; }); }
    if (k.renderer) {
        var rn = RENDERERS[norm(k.renderer)];
        if (rn && inArr(comp.renderers, rn)) { attempt(function () { comp.renderer = rn; }); }
    }
    addMarkers(comp.markerProperty, k.markers, env.log, 'comp "' + it.name + '"');
    return comp;
}

// ---------------------------------------------------------------- layers

var AUTO_ORIENT = {
    off: 'NO_AUTO_ORIENT', none: 'NO_AUTO_ORIENT', alongpath: 'ALONG_PATH',
    towardspointofinterest: 'CAMERA_OR_POINT_OF_INTEREST', towardscamera: 'CAMERA_OR_POINT_OF_INTEREST',
    towardspoi: 'CAMERA_OR_POINT_OF_INTEREST', characterstowardcamera: 'CHARACTERS_TOWARD_CAMERA'
};
var FRAME_BLEND = { off: 'NO_FRAME_BLEND', framemix: 'FRAME_MIX', pixelmotion: 'PIXEL_MOTION' };
var LIGHT_TYPES = { parallel: 'PARALLEL', spot: 'SPOT', point: 'POINT', ambient: 'AMBIENT', environment: 'ENVIRONMENT' };

function findSourceText(L) {
    var root = L.props || {};
    var kids = root.children || [];
    for (var i = 0; i < kids.length; i++) {
        if (kids[i].match != 'text') { continue; }
        var tk = kids[i].children || [];
        for (var j = 0; j < tk.length; j++) { if (tk[j].match == 'sourceText') { return tk[j]; } }
    }
    return null;
}

function createLayer(L, comp, env) {
    var src = L.source || {};
    var cw = comp.width, ch = comp.height;
    var layer = null, i;
    switch (src.type) {
        case 'Footage': case 'Comp': case 'Solid':
            var item = env.itemMap[src.item];
            if (item) {
                try { layer = comp.layers.add(item); } catch (e) { env.log.warn('Layer "' + L.name + '" could not be added: ' + e.message); }
            } else {
                env.log.warn('Layer "' + L.name + '" points at a missing project item; a null was used instead.');
            }
            break;
        case 'Null':
            layer = comp.layers.addNull(comp.duration);
            break;
        case 'Camera':
            layer = comp.layers.addCamera(L.name || 'Camera', [cw / 2, ch / 2]);
            break;
        case 'Light':
            layer = comp.layers.addLight(L.name || 'Light', [cw / 2, ch / 2]);
            var lt = LIGHT_TYPES[norm(src.light_type || src.lightType || src.kind || '')];
            if (lt) { attempt(function () { layer.lightType = LightType[lt]; }); }
            break;
        case 'Text':
            var st = findSourceText(L);
            var tv = (st && st.value && st.value.v) ? st.value.v : {};
            var txt = String(tv.text || ' ').replace(/\r\n|\n/g, '\r');
            if (tv.box_size && tv.box_size.length == 2) {
                try { layer = comp.layers.addBoxText([tv.box_size[0], tv.box_size[1]], txt); } catch (e2) { layer = null; }
            }
            if (!layer) { layer = comp.layers.addText(txt); }
            break;
        case 'Shape':
            layer = comp.layers.addShape();
            break;
        default:
            env.log.warn('Layer "' + L.name + '" is of type "' + src.type + '", which the converter does not know yet; a null was used instead.');
    }
    if (!layer) { layer = comp.layers.addNull(comp.duration); }
    env.log.stats.layers++;
    return layer;
}

function setupLayer(L, layer, env) {
    var sw = L.switches || {};
    var isText = L.source && L.source.type == 'Text';
    if (!(isText && L.name_follows_text)) { attempt(function () { layer.name = L.name; }); }
    var li = labelIndex(L.label);
    if (li != null) { attempt(function () { layer.label = li; }); }
    if (L.comment) { attempt(function () { layer.comment = L.comment; }); }

    attempt(function () { layer.startTime = sec(L.start_time); });
    if (L.stretch != null && L.stretch != 100) { attempt(function () { layer.stretch = L.stretch; }); }
    var inP = sec(L.in_point), outP = sec(L.out_point);
    if (outP > inP) {
        attempt(function () { layer.outPoint = outP; });
        attempt(function () { layer.inPoint = inP; });
        attempt(function () { layer.outPoint = outP; });
    }

    var t = L.source ? L.source.type : '';
    var isCamLight = (t == 'Camera' || t == 'Light');
    if (!isCamLight && sw.three_d) { attempt(function () { layer.threeDLayer = true; }); }
    if (sw.adjustment) { attempt(function () { layer.adjustmentLayer = true; }); }
    if (sw.guide) { attempt(function () { layer.guideLayer = true; }); }
    if (sw.shy) { attempt(function () { layer.shy = true; }); }
    if (sw.solo) { attempt(function () { layer.solo = true; }); }
    if (sw.audio === false) { attempt(function () { layer.audioEnabled = false; }); }
    if (sw.effects === false) { attempt(function () { layer.effectsActive = false; }); }
    if (sw.motion_blur) { attempt(function () { layer.motionBlur = true; }); }
    if (sw.collapse) { attempt(function () { layer.collapseTransformation = true; }); }
    if (sw.quality) { attempt(function () { layer.quality = enumVal(LayerQuality, sw.quality, LayerQuality.BEST); }); }
    if (sw.sampling) {
        attempt(function () { layer.samplingQuality = enumVal(LayerSamplingQuality, sw.sampling, LayerSamplingQuality.BILINEAR); });
    }
    if (sw.frame_blend && FRAME_BLEND[norm(sw.frame_blend)]) {
        attempt(function () { layer.frameBlendingType = FrameBlendingType[FRAME_BLEND[norm(sw.frame_blend)]]; });
    }
    if (L.blend_mode) {
        var bm = enumVal(BlendingMode, L.blend_mode, null);
        if (bm == null) { env.log.warn('Blend mode "' + L.blend_mode + '" on layer "' + L.name + '" is unknown; Normal was used.'); }
        else { attempt(function () { layer.blendingMode = bm; }); }
    }
    if (L.preserve_transparency) { attempt(function () { layer.preserveTransparency = true; }); }
    if (L.auto_orient) {
        var ao = AUTO_ORIENT[norm(L.auto_orient)];
        if (ao) { attempt(function () { layer.autoOrient = AutoOrientType[ao]; }); }
    }
    if (L.props && hasMatch(L.props.children || [], 'timeRemap')) {
        attempt(function () { layer.timeRemapEnabled = true; });
    }
    addMarkers(safeChild(layer, 'ADBE Marker'), L.markers, env.log, 'layer "' + L.name + '"');
}

function buildComp(it, comp, env) {
    var layers = it.kind.layers || [];
    var made = [], i;
    env.layerById = {};

    // AE stacks each new layer on top, so build bottom-up
    for (i = layers.length - 1; i >= 0; i--) {
        var lay = createLayer(layers[i], comp, env);
        env.layerById[layers[i].id] = lay;
        made[i] = lay;
    }
    for (i = 0; i < layers.length; i++) { setupLayer(layers[i], made[i], env); }

    // parent before properties, so stored local values land as they are
    for (i = 0; i < layers.length; i++) {
        var pid = layers[i].parent;
        if (pid == null) { continue; }
        var par = env.layerById[pid];
        if (!par) { env.log.warn('Parent of layer "' + layers[i].name + '" was not found.'); continue; }
        var child = made[i];
        if (!attempt(function () { child.setParentWithJump(par); })) {
            if (!attempt(function () { child.parent = par; })) {
                env.log.warn('Could not parent "' + layers[i].name + '" to "' + par.name + '".');
            }
        }
    }

    for (i = 0; i < layers.length; i++) {
        var L = layers[i];
        if (!L.props) { continue; }
        env.layerName = L.name;
        env.doneLayers++;
        env.prog.set('Comp "' + it.name + '": layer ' + (i + 1) + ' of ' + layers.length + ' (' + L.name + ')',
            30 + 67 * env.doneLayers / Math.max(1, env.totalLayers));
        env.is3D = !!(L.switches && L.switches.three_d) || (L.source && (L.source.type == 'Camera' || L.source.type == 'Light'));
        try { applyGroup(L.props, made[i], [], 'layer', env); }
        catch (e) { env.log.warn('Layer "' + L.name + '" was only partly converted: ' + e.message + (e.line ? ' (line ' + e.line + ')' : '')); }
    }

    // track mattes (AE 2023+ allows any layer as matte; older versions need the matte right above)
    for (i = 0; i < layers.length; i++) {
        var tm = layers[i].track_matte;
        if (!tm || tm.layer == null) { continue; }
        var target = made[i], matte = env.layerById[tm.layer];
        if (!matte) { env.log.warn('Track matte of "' + layers[i].name + '" was not found.'); continue; }
        var type = enumVal(TrackMatteType, tm.kind, TrackMatteType.ALPHA);
        var done = attempt(function () { target.setTrackMatte(matte, type); });
        if (!done && matte.index == target.index - 1) { done = attempt(function () { target.trackMatteType = type; }); }
        if (!done) {
            env.log.warn('Track matte on "' + layers[i].name + '" needs After Effects 2023 or newer (the matte layer is not directly above it).');
        }
    }

    // visibility and locks last, because locked layers refuse edits
    for (i = 0; i < layers.length; i++) {
        var s = layers[i].switches || {};
        var lyr = made[i];
        if (s.video === false) { attempt(function () { lyr.enabled = false; }); }
        else { attempt(function () { if (lyr.hasVideo) { lyr.enabled = true; } }); }
    }
    for (i = 0; i < layers.length; i++) {
        if (layers[i].switches && layers[i].switches.locked) {
            var lk = made[i];
            attempt(function () { lk.locked = true; });
        }
    }
}

// ---------------------------------------------------------------- one project

function convertOne(job, auto, extraDirs, prog) {
    var inFile = new File(job.input);
    var baseName = decodeURI(inFile.name).replace(/\.ecproj$/i, '');
    var log = new Log(baseName);
    log.info('EC2AE ' + EC2AE_VERSION + '  |  ' + inFile.fsName);

    prog.set('Reading ' + decodeURI(inFile.name) + '...', 2);
    var raw = readText(inFile);
    prog.set('Reading project data (' + Math.round(raw.length / 1024) + ' KB)...', 5);
    var data = parseJSON(raw, !!job.trusted);
    raw = null;
    if (!data || !data.items) { throw new Error('No "items" in this file. Is it an EffectCraft project?'); }
    if (data.schema && data.schema > 2) {
        log.warn('This project uses EffectCraft file schema ' + data.schema + '. The converter was written for schema 2, so check the result.');
    }

    prog.set('Opening a new project...', 8);
    if (auto) {
        if (!app.newProject()) { throw new Error('A new project could not be opened (save or close the current one first).'); }
    } else if (!app.project) {
        app.newProject();
    }
    var proj = app.project;

    var srcDir = inFile.parent ? inFile.parent.fsName : '';
    var dirs = [srcDir, srcDir + '/footage', srcDir + '/Footage', srcDir + '/assets', srcDir + '/Assets'];
    for (var d = 0; d < extraDirs.length; d++) { dirs.push(extraDirs[d]); }

    var env = {
        log: log, itemMap: {}, layerById: {}, searchDirs: dirs,
        userFx: loadUserEffectMap([srcDir].concat(extraDirs), log),
        aeSolidsFolder: null, layerName: '', is3D: false, prog: prog
    };

    // project settings only when we own the project
    var st = data.settings || {};
    if (auto) {
        if (st.bit_depth) {
            var bpc = { bpc8: 8, bpc16: 16, bpc32: 32 }[norm(st.bit_depth)];
            if (bpc) { attempt(function () { proj.bitsPerChannel = bpc; }); }
        }
        if (st.blend_linear != null) { attempt(function () { proj.linearBlending = !!st.blend_linear; }); }
        if (st.working_gamma) { attempt(function () { proj.workingGamma = st.working_gamma; }); }
        if (st.time_display) {
            attempt(function () { proj.timeDisplayType = (norm(st.time_display) == 'frames') ? TimeDisplayType.FRAMES : TimeDisplayType.TIMECODE; });
        }
        if (st.frame_start != null) {
            attempt(function () { proj.framesCountType = st.frame_start == 1 ? FramesCountType.FC_START_1 : FramesCountType.FC_START_0; });
        }
    }

    var root = proj.rootFolder;
    if (!auto) { root = proj.items.addFolder(baseName + ' (EffectCraft)'); }

    var ids = [], k, it;
    for (k in data.items) { if (data.items.hasOwnProperty(k)) { ids.push(k); } }
    ids.sort(function (a, b) { return Number(a) - Number(b); });

    // 1. folders
    for (k = 0; k < ids.length; k++) {
        it = data.items[ids[k]];
        if (it.kind && it.kind.type == 'Folder') { env.itemMap[it.id] = proj.items.addFolder(it.name); }
    }
    // 2. footage
    for (k = 0; k < ids.length; k++) {
        it = data.items[ids[k]];
        if (it.kind && it.kind.type == 'Footage') {
            prog.set('Importing footage: ' + it.name, 10 + 15 * k / ids.length);
            try { env.itemMap[it.id] = importFootage(it, env); }
            catch (e) { log.warn('Footage "' + it.name + '" failed: ' + e.message); }
        }
    }
    // 3. solids
    var solids = [];
    for (k = 0; k < ids.length; k++) {
        it = data.items[ids[k]];
        if (it.kind && it.kind.type == 'Solid') { solids.push(it); }
    }
    prog.set('Creating solids and comps...', 26);
    createSolids(solids, env);
    // 4. empty comps (so precomp layers can point at any comp)
    var comps = [];
    for (k = 0; k < ids.length; k++) {
        it = data.items[ids[k]];
        if (it.kind && it.kind.type == 'Comp') {
            try { env.itemMap[it.id] = createComp(it, env); comps.push(it); }
            catch (e2) { log.warn('Comp "' + it.name + '" could not be created: ' + e2.message); }
        } else if (it.kind && inArr(['Folder', 'Footage', 'Solid'], it.kind.type) === false) {
            log.warn('Project item "' + it.name + '" has type "' + it.kind.type + '", which the converter does not know yet.');
        }
    }
    // 5. folder structure, labels, comments
    for (k = 0; k < ids.length; k++) {
        it = data.items[ids[k]];
        var ae = env.itemMap[it.id];
        if (!ae) { continue; }
        var pf = (it.parent != null && env.itemMap[it.parent]) ? env.itemMap[it.parent] : root;
        attempt(function () { ae.parentFolder = pf; });
        var lb = labelIndex(it.label);
        if (lb != null) { attempt(function () { ae.label = lb; }); }
        if (it.comment) { attempt(function () { ae.comment = it.comment; }); }
    }
    if (env.aeSolidsFolder) {
        attempt(function () { if (env.aeSolidsFolder.numItems === 0) { env.aeSolidsFolder.remove(); } });
    }
    // 6. layers
    env.totalLayers = 0; env.doneLayers = 0;
    for (k = 0; k < comps.length; k++) { env.totalLayers += (comps[k].kind.layers || []).length; }
    for (k = 0; k < comps.length; k++) {
        try { buildComp(comps[k], env.itemMap[comps[k].id], env); }
        catch (e3) { log.warn('Comp "' + comps[k].name + '" was only partly built: ' + e3.message + (e3.line ? ' (line ' + e3.line + ')' : '')); }
    }

    // open the first top-level comp so the user lands somewhere useful
    for (k = 0; k < comps.length; k++) {
        if (comps[k].parent == null) {
            var oc = env.itemMap[comps[k].id];
            attempt(function () { oc.openInViewer(); });
            break;
        }
    }

    var saved = null;
    if (auto && job.output) {
        prog.set('Saving ' + job.output + ' ...', 98);
        var out = new File(job.output);
        if (proj.save(out)) { saved = out.fsName; } else { log.warn('Saving to ' + out.fsName + ' failed. Use File > Save As.'); }
    }
    log.saved = saved;
    log.input = inFile.fsName;
    writeLog(log, job.output ? new File(job.output) : inFile);
    return log;
}

function writeLog(log, nextTo) {
    var allowed = false;
    try { allowed = app.preferences.getPrefAsLong('Main Pref Section', 'Pref_SCRIPTING_FILE_NETWORK_SECURITY') == 1; } catch (e) {}
    if (!allowed) { return; }
    try {
        var f = new File(String(nextTo.fsName).replace(/\.[^\\\/.]+$/, '') + '_EC2AE-log.txt');
        f.encoding = 'UTF-8';
        if (f.open('w')) { f.write(log.lines.join('\n')); f.close(); log.logFile = f.fsName; }
    } catch (e2) {}
}

// ---------------------------------------------------------------- entry point

function main() {
    if (typeof app === 'undefined' || !app.project && !app.newProject) {
        alert('Run this script from inside Adobe After Effects.');
        return;
    }
    var jobs = GLOBAL.EC2AE_JOBS;
    var extra = GLOBAL.EC2AE_EXTRA_DIRS || [];
    GLOBAL.EC2AE_JOBS = undefined;
    GLOBAL.EC2AE_EXTRA_DIRS = undefined;
    var auto = !!(jobs && jobs.length);

    var scriptDir = '';
    try { scriptDir = new File($.fileName).parent.fsName; } catch (e0) {}
    if (scriptDir) { extra = extra.concat([scriptDir]); }

    if (!auto) {
        var picked = File.openDialog('Pick EffectCraft project(s) to convert', 'EffectCraft:*.ecproj,All files:*.*', true);
        if (!picked) { return; }
        if (!isArr(picked)) { picked = [picked]; }
        jobs = [];
        for (var p = 0; p < picked.length; p++) { jobs.push({ input: picked[p].fsName }); }
    }

    var results = [];
    var prog = new Progress();
    app.beginUndoGroup('EffectCraft to After Effects');
    try { app.beginSuppressDialogs(); } catch (e1) {}
    for (var j = 0; j < jobs.length; j++) {
        try {
            results.push(convertOne(jobs[j], auto, extra, prog));
        } catch (e) {
            results.push({ failed: true, input: jobs[j].input, error: e.message + (e.line ? ' (line ' + e.line + ')' : '') });
        }
    }
    try { app.endSuppressDialogs(false); } catch (e2) {}
    app.endUndoGroup();
    prog.close();

    // report
    var msg = ['EffectCraft to After Effects ' + EC2AE_VERSION, ''];
    for (var r = 0; r < results.length; r++) {
        var x = results[r];
        if (x.failed) { msg.push('FAILED: ' + fileNameOf(x.input)); msg.push('   ' + x.error); msg.push(''); continue; }
        var s = x.stats;
        msg.push('DONE: ' + fileNameOf(x.input));
        msg.push('   ' + s.comps + ' comps, ' + s.layers + ' layers, ' + s.footage + ' footage items, ' + s.effects + ' effects, ' + s.keys + ' keyframes');
        if (x.saved) { msg.push('   Saved: ' + x.saved); }
        if (s.missing) { msg.push('   ' + s.missing + ' footage file(s) not found (placeholders added).'); }
        if (x.warns.length) {
            msg.push('   ' + x.warns.length + ' note(s):');
            for (var w = 0; w < x.warns.length && w < 12; w++) { msg.push('   - ' + x.warns[w]); }
            if (x.warns.length > 12) {
                msg.push('   ...and ' + (x.warns.length - 12) + ' more' + (x.logFile ? ' (full list in ' + x.logFile + ')' : ' (turn on Preferences > Scripting & Expressions > "Allow Scripts to Write Files" to get a full log file)'));
            }
        }
        msg.push('');
    }
    alert(msg.join('\n'));
}

main();

})($.global);

EC2AE-JSX-END#>
