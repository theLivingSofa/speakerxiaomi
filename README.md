# Sound Outdoor EQ

A menu-bar equalizer for Mac, made for the **Xiaomi Sound Outdoor** Bluetooth speaker, which has no app or EQ of its own.

The speaker's built-in sound can't be changed, so this app shapes the audio **on your Mac before it's sent to the speaker**. It works for everything your Mac plays: YouTube, Spotify, Apple Music, games and calls. Your settings are saved and come back after a restart.

## Features

- 10-band EQ (32 Hz – 16 kHz, ±12 dB) with a live response curve
- Presets: Flat, **Outdoor**, Bass Boost, Vocal / Podcast, Treble, Night, plus your own saved presets
- **Speaker protection**: cuts bass below 55 Hz, which the speaker can't play (it's rated from 60 Hz). Bass boosts stay cleaner and louder.
- **Limiter** so boosted parts don't clip
- **Bypass** switch to compare the sound with and without the EQ
- Preamp, balance, and a mono mode (best with a single speaker)
- Turns on by itself when the Xiaomi speaker is your output and steps aside for other devices. Can also be set to apply to every output.
- Opens at login and remembers everything
- **Keeps the Mac's own microphone** in use, so the speaker's mic never drops Bluetooth into muffled call mode

Needs **macOS 14.2 or newer**, on Apple Silicon or Intel. No audio driver to install.

## Install

1. Download the `.dmg`:
   - from **Releases**, if one has been published, or
   - from **Actions → latest "Build" run → Artifacts** (it downloads as a .zip that contains the .dmg).
2. Open the `.dmg` and drag **Sound Outdoor EQ** into **Applications**.
3. **First launch:** the app isn't notarized by Apple, so macOS blocks a normal double-click. Either:
   - right-click the app → **Open** → **Open**, or
   - try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. When macOS asks, **allow System Audio Recording**. The app needs this to apply the EQ. Nothing is recorded or saved.
5. A speaker icon appears in the menu bar. Click it to open the EQ.

> If you install a new build, macOS may ask for the audio permission again. That's because each build has a new signature.

## Using it

1. Connect the Xiaomi Sound Outdoor over Bluetooth and make sure it's the Mac's sound output.
2. Click the menu-bar icon. The status should say **Active on Xiaomi Sound Outdoor**.
3. Pick a preset or drag the sliders. Double-click a slider to reset it to 0.
4. Use **Bypass** to compare. Save curves you like with **⋯ → Save as New Preset**.

If boosting makes loud songs distort, lower the **Preamp** a few dB.

### Choosing the device

**Use with** decides when the EQ runs:
- **Any Xiaomi speaker** (default): any output with "Xiaomi" in its name
- a specific device from the list
- **Every output**: apply the EQ to whatever you're playing through

## iPhone

iOS doesn't let any app change the sound of other apps, so nothing can apply one EQ to everything on an iPhone. Your options:

- **Play through your Mac with AirPlay.** macOS can receive AirPlay. Put the iPhone and Mac on the same Wi-Fi. On the iPhone, open Control Center → AirPlay, and pick your Mac. The Mac plays it through this EQ to the speaker. If your Mac doesn't show up, turn on **System Settings → General → AirDrop & Handoff → AirPlay Receiver**.
- **Spotify's built-in EQ** (Settings → Playback → Equalizer) works with any speaker, but only in Spotify.
- Apple Music has a few fixed EQ presets (Settings → Apps → Music → EQ).

## How it works

The app uses macOS's system audio capture (a Core Audio *process tap*, added in macOS 14.2):

1. It captures the sound of every app and mutes the originals while it's running.
2. It runs that sound through the EQ (speaker protection → preamp → 10 bands → balance/mono → limiter).
3. It plays the result on the speaker.

If the app quits or crashes, macOS unmutes your apps automatically, so you never lose sound. Processing adds about 10–20 ms of delay, which isn't noticeable for music or video.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| No sound at all while the EQ is on | Open the menu → 🔒 button → turn on **Sound Outdoor EQ** under System Audio Recording. Or switch the EQ off. |
| Status says "Waiting for the Xiaomi speaker" | Make sure the speaker is your sound output (menu bar → Sound). Check the **Use with** setting. |
| "The EQ couldn't start" | Click **Try Again**. Reconnecting the speaker also restarts it. |
| Open at login doesn't stick | Click **Approve…**, or allow it in System Settings → General → Login Items. |
| Music suddenly sounds muffled or mono | An app used the speaker's microphone, which switches Bluetooth into call mode. Keep **Use the Mac's microphone** on, or pick the MacBook microphone in System Settings → Sound → Input. |

## Building it yourself

Needs Xcode 16 or newer.

```bash
swift test                     # run the EQ tests
scripts/build_app.sh 1.0.0     # builds dist/Sound Outdoor EQ.app
scripts/make_dmg.sh 1.0.0      # builds dist/SoundOutdoorEQ-1.0.0.dmg
```

To publish a release with the DMG attached, either push a tag such as `v1.0.0`, or go to **Actions → Build → Run workflow** and enter a version such as `1.0.1`. The workflow creates the tag and the release.

## Project layout

- `Sources/EQCore/`: filters, EQ processing, presets and saved settings. Plain Swift, fully unit-tested.
- `Sources/SoundOutdoorEQ/Audio/`: system audio capture and playback (Core Audio).
- `Sources/SoundOutdoorEQ/UI/`: the menu-bar window (SwiftUI).
- `Tests/EQCoreTests/`: tests for the EQ math and settings.
- `scripts/`: app bundle and DMG packaging.
- `.github/workflows/build.yml`: builds, tests and packages on every push.

## Credits

Created by **Ayush Agrawal** ([@theLivingSofa](https://github.com/theLivingSofa)): the idea, features and testing on the real speaker. Code written with [Claude Code](https://claude.com/claude-code).
