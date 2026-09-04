# Prayer Times for Garmin

A Connect IQ widget (glance + full view) for the Forerunner 265S / 265 / 965
that shows the day's Islamic prayer times and a live countdown to the next
one, calculated **offline on the watch** with the Diyanet (Türkiye) method
done right — 18°/17° twilight angles *and* Diyanet's fixed temkin
(precaution) offsets, which is what the store apps get wrong for Turkey.

```
glance:     İkindi 17:13
            ████████████░░░░░░░░      ← progress from the previous prayer
            2 sa 14 dk sonra

full view:        Ümraniye        (UP/DOWN: tomorrow, day after, qibla)
                   Bugün
              İmsak       04:51
              Güneş       06:31
              Öğle        13:11
            ● İkindi      17:13
              Akşam       19:41
              Yatsı       21:12
                  ● ○ ○
```

The calculation is a port of the one in the desktop app
(`../prayer-times-go`, which uses adhango, the Go port of the Batoul Apps
Adhan library) and is verified against it: `tools/verify/fixtures.txt`
holds 392 reference schedules computed by adhango, and the Monkey C port
reproduces every one of them to the second (see *Verifying* below).

## Features

- **Offline calculation**, no prayer-time API, nothing to sync.
- **12 methods**: Diyanet (default, with temkin), Muslim World League,
  ISNA, Umm al-Qura, Egyptian, Karachi, Moonsighting Committee, Kuwait,
  Qatar, Singapore, UOIF, Dubai. Standard or Hanafi Asr.
- **Three days**: today's imsakiye with the date on top; UP/DOWN (or swipe)
  for tomorrow and the day after. The next prayer is highlighted on
  whichever page it falls, so after Yatsı the highlight sits on tomorrow's
  İmsak.
- **Qibla compass** as the fourth page: a compass rose that turns with the
  watch heading, an arrow to the Kaaba (green when you are within 5°), the
  bearing in degrees and the great-circle distance.
- **Location**: current location (the watch's last known position or the
  phone's weather location, whichever is fresher, polled while the widget
  is open; press START in the full view for a fresh GPS fix). The header
  shows the place name: from the weather observation when that is nearby,
  otherwise reverse-geocoded through the phone (BigDataCloud, as in the
  desktop app) and cached; without a phone it shows the coordinates. Or a
  preset
  (Istanbul, Ankara, İzmir, Mecca, Medina, London, New York), or custom
  coordinates entered in the Connect IQ phone app (the watch has no way to
  type them).
- **Settings on the watch** (hold UP / MENU in the full view) or in the
  Connect IQ phone app; both write the same properties.
- **5 languages**: English, Türkçe, Русский, Español, Français. Defaults
  to the watch language, selectable in settings. (The desktop app's Arabic,
  Japanese and Chinese are left out: the watch fonts lack the glyphs.)
  Times are shown in the watch's time zone and respect the 12/24 h setting.

## Toolchain setup (macOS)

Nothing here is installed by default; the SDK needs a Garmin developer login.

1. **Java 17+** (the compiler is a Java program):
   ```sh
   brew install --cask temurin
   ```
2. **Connect IQ SDK Manager**:
   ```sh
   brew install --cask connectiq-sdk-manager
   ```
   (or download it from https://developer.garmin.com/connect-iq/sdk/).
   Open it, sign in, download the latest SDK, and under *Devices* download
   **Forerunner 265S**, **Forerunner 265** and **Forerunner 965**. The SDK
   lands in `~/Library/Application Support/Garmin/ConnectIQ/Sdks/<version>/`.
   The active one is recorded in `current-sdk.cfg`, so this line in
   `~/.zshrc` keeps `monkeyc`, `monkeydo` and `connectiq` on your `PATH`
   across SDK upgrades:
   ```sh
   export PATH="$PATH:$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")bin"
   ```
3. **VS Code**: install the *Monkey C* extension (`garmin.monkey-c`). It
   picks up `monkey.jungle`, gives you *Run* (simulator) and *Build for
   Device*, and can generate a developer key if you don't have one.

### Developer key

Builds must be signed. A key was generated in the project root and is
git-ignored (`developer_key.der`). To make a new one:

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

## Build

```sh
mkdir -p bin
monkeyc -d fr265s -f monkey.jungle -o bin/PrayerTimes.prg -y developer_key.der -w
```

Run in the simulator:

```sh
connectiq &                       # starts the simulator
monkeydo bin/PrayerTimes.prg fr265s
```

In the simulator use *Settings → Set Position* to feed a position; the
widget's "Current location" picks it up within ten seconds while the full
view is open. Note that the simulator also simulates weather with its own
station location, which the widget uses until a position is set. Custom
coordinates can be entered via *File → Edit Persistent Storage → Edit
Application.Properties*. *Simulation → Time* lets you jump around the day
to check the rollover after Isha.

## Install on the watch

Connect the watch by USB, and copy `bin/PrayerTimes.prg` into the watch's
`GARMIN/APPS/` folder. The Forerunner 265 mounts as an MTP device, so on
macOS use [OpenMTP](https://openmtp.ganeshrvel.com/) or Android File
Transfer (Garmin Express also works). Disconnect, and the widget appears in
the glance list (*Settings → Glances → Add* if it is not there already).

## Verifying the calculation

Two layers, because Monkey C only runs inside the simulator:

1. `tools/verify/mirror.py` is a statement-for-statement Python mirror of
   `source/PrayerCalc.mc`, checked against the adhango reference output:
   ```sh
   (cd tools/fixtures && go run . > ../verify/fixtures.txt)   # regenerate references
   python3 tools/verify/mirror.py                              # 392/392 cases match adhango
   ```
   This validates the algorithm transcription (both are IEEE doubles).
2. `source/PrayerCalcTest.mc` holds 125 of those cases as Connect IQ unit
   tests (generated by `tools/verify/gen_tests.py`), which validate the
   actual Monkey C compiler and runtime:
   ```sh
   monkeyc -d fr265s -f monkey.jungle -o bin/PrayerTimes-test.prg -y developer_key.der -t
   monkeydo bin/PrayerTimes-test.prg fr265s -t
   ```
   Status: all 8 tests (125 schedules) pass on SDK 9.2.0 / fr265s 5.2.0.

## Connect IQ gotchas met along the way

- A string resource id cannot be a Monkey C keyword (`Method` was rejected;
  it is `CalcMethod` now).
- Resources used from glance code need `scope="glance"` in the XML, or the
  glance crashes with *Could not access symbol 'Rez'*. Foreground code can
  still use them.
- Resource strings always follow the device language, so a user-selectable
  language needs its own table in code (`L10n.mc`). Strings only used by
  the settings editor carry `scope="settings"` and stay out of the app.
- The fr265s launcher icon is 60x60 (`tools/make_icon.py` generates it).
- Every floating literal in `PrayerCalc.mc` carries a `d` suffix so the
  math stays in Double; Monkey C's default Float is single precision.

## Code layout

| File | Purpose |
|---|---|
| `source/Qibla.mc` | bearing and distance to the Kaaba |
| `source/PrayerCalc.mc` | the astronomy: adhan port, Double throughout, returns UTC epoch seconds |
| `source/Methods.mc` | the 12 method presets (angles, intervals, minute offsets) |
| `source/Model.mc` | settings, location resolution, today/tomorrow schedule with cache, formatting |
| `source/LocationProvider.mc` | weather / last-known / GPS location for "current location" |
| `source/L10n.mc` | on-watch strings in 5 languages (resource strings only serve the phone settings editor) |
| `source/PrayerTimesApp.mc` | app entry, glance + full view wiring |
| `source/PrayerGlanceView.mc` | glance |
| `source/PrayerView.mc` | full view |
| `source/PrayerDelegate.mc` | buttons and the on-watch settings menus |
| `source/PrayerCalcTest.mc` | generated unit tests |
| `resources*/` | strings (en, tr), settings schema, launcher icon |
| `tools/` | fixture generator (Go), Python mirror, test generator, icon generator |

## Diyanet parameters

Fajr 18°, Isha 17°, Asr standard shadow, and the temkin offsets applied
after the astronomical times: İmsak −2, Güneş −7, Öğle +7, İkindi +4,
Akşam +9, Yatsı +2 minutes. High-latitude fallback is middle of the night,
like the desktop app.
