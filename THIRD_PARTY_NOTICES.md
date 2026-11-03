# Third-party notices

## Project code and generated artwork

First-party code and resources are distributed under [LICENSE.txt](LICENSE.txt). The PNG in `artwork/` was generated with the built-in imagegen tool; its provenance, prompt and unfinished integration status are documented in [artwork/README.md](artwork/README.md). No claim of exclusivity or official game authorship is made.

## bg3forge

`tools/vendor/bg3forge/` contains a vendored MIT-licensed format library from [crazyace/bg3-forge](https://github.com/crazyace/bg3-forge), commit `10fa2959b472bb71ba2714d274b9828e59cd4576`. See the retained [BG3FORGE_LICENSE.txt](tools/vendor/BG3FORGE_LICENSE.txt). It is used for LSF, LOCA and package format handling.

## LSLib

The small package writer follows the LSPK layout documented by [Norbyte/lslib](https://github.com/Norbyte/lslib), audited at commit `6f5f6987d10d8485876b8368431c948e4dea4f83`. The [LSLib MIT license](tools/vendor/LSLIB_LICENSE.txt) is retained. No LSLib binary is required to run the bundled builder.

## Script Extender and BG3

This mod depends on [Norbyte/bg3se](https://github.com/Norbyte/bg3se); BG3SE and the game are not bundled. Audit references are listed in [docs/API_AUDIT.md](docs/API_AUDIT.md). The mod references existing game templates, icons and VFX by identifier. It does not redistribute those original game textures, meshes, icons or VFX files. They remain subject to their owners' rights and require the game installation.

Baldur’s Gate, Dungeons & Dragons and related game materials belong to their respective owners. This is an unofficial fan project.

## Test dependencies

The optional development dependencies in `requirements-dev.txt` (lupa, pytest and lz4) are installed separately; their packages are not vendored. Their respective licenses apply.
