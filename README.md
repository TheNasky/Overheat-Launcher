# Overheat Launcher

The public launcher for **Overheat**. Players and testers install it once; it downloads the newest game
pack for their channel and starts the game.

**Status: M0.** Launcher v1 with Stable/Dev channels, tester login, self-update and a CI-built install kit.

**Install:** download `Overheat-Launcher.zip` from the latest `launcher-v*` release, unzip, run `Overheat.exe`.

Dev notes: Godot 4.7.2 project at the repo root (`scripts/launcher.gd`). Bump `LAUNCHER_VERSION` and push to
`main` to publish a new launcher (`.github/workflows/launcher.yml`). Test against local manifests with
`-- --channels=http://127.0.0.1:PORT --channel=dev [--auto-play]`.

## Hard rule

**This repo never contains server code.** No `server/` folder, no host scripts, no match-server logic, no
tunnel config, no tokens or keys. The game server is private and lives only in the private `Overheat` repo.
Packs published here are client builds made with `server/*` excluded, and the publish step refuses a pack
that contains it.

## What goes here

```
launcher source        Godot launcher scene + script (ported from reference/)
channels/stable.json   manifest for the stable channel (prod)
channels/dev.json      manifest for the dev channel (main, testers only)
README / install kit   how to install
GitHub Releases        the game packs (.pck), one release per build, SHA-256 in the manifest
```

Manifest shape (proposed, from the old `latest.json`): `version` (`YYYY.MM.DD-<sha>`), `published_unix`,
`pack_url`, `sha256`, `notes`, `server` (public hostname for that channel), `min_launcher`.

## Behaviour (target for M0)

- **Channel picker**: Stable (everyone) or Dev (needs a tester login; the server checks the token, the
  launcher stores only the user's own token locally).
- On start: read the channel manifest, download a newer pack if any, verify SHA-256, show date (player's
  time zone) and notes, PLAY. Offline: play the last pack.
- Self-update: every pack also carries the launcher scene; the kit's launcher hands over to the newest one
  (this already worked in the old game).
- "Check for update" button so a tester gets a fresh dev build without restarting.
- Dev flow: push to `main` in the private repo → CI (or a script on Nasky's PC) exports the client pack →
  creates a Release here and updates `channels/dev.json` → the tester's launcher picks it up.

## Reference

`reference/` holds the launcher-only files from the old game (`scripts/launcher/launcher.gd`,
`launcher.tscn`, `tools/make_launcher_kit.sh`, `tools/launcher_readme.txt`), copied from Mech-Game `main`
(85cf963). The old builds repo is github.com/TheNasky/Mech-Game-Builds (packs + `latest.json`). The old
publish script (`publish_build.sh`) stays in the private repo's reference because it runs on the dev side.
Delete `reference/` before the first public push, or keep it only if it contains nothing private (it
doesn't today: it holds the old public server hostname, which shipped in every old pack anyway).
