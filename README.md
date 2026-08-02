# configsys-source

A [configsys](https://github.com/spacemeat/configsys) **data plugin** that adds a selectable
**build-from-source** (`via: source`) method to most genuinely-buildable components — CLI/TUI
tools and libraries with a public git repo and a standard build system.

It ships **no code** (the built-in `source` driver does the work), so there's no trust step —
add it and the covered components each gain a `source` binding.

## Why

1. **Build anything from source, anywhere** — for contributors and source purists (a "gentoo-ish"
   posture), any covered tool can be built rather than fetched as a binary.
2. **Close binary-method gaps** — a tool with no native/tarball/flatpak method on your OS can
   still be installed by building it.

## It never changes your defaults

The source bindings are **additive** and sit **below every binary method** in configsys's
`driver-preference` (`native > flatpak > snap > appImage > tarball > source > script`). So loading
this plugin changes **no** default resolution — `source` is strictly opt-in. Choose it:

```sh
# per component
configsys pin set ripgrep source

# or globally prefer source (the gentoo-ish switch), in ~/.config/configsys/configsys.hu:
#   driver-preference: [ source, native, flatpak, appImage, tarball, script ]
```

## Use it

Add to your `~/.config/configsys/configsys.hu`:

```
plugins: [
    { source: "github:spacemeat/configsys-source"  ref: v0.1.0 }
]
```

then `configsys plugin sync`. `configsys where <component>` shows the added `source` binding;
`configsys pin set <component> source` selects it.

## What's covered (and what isn't)

**Covered:** buildable CLI/TUI tools & libraries — Rust (cargo), Go, C/C++ (autotools / cmake /
make), Zig, meson.

**Not covered** (by design): language toolchains/runtimes (gcc, rust, go, node…), module-manager
installs (npm/pip/cargo-crate/gem… — already source-ish), fonts, dotfiles, services, groups, OS
metapackages, and proprietary/binary-only GUI apps (no public source).

**Heavy apps & desktops get their OWN bespoke plugins** (a real build driver + recipe), following
the Blender / KiCad precedent — not this declarative data plugin:

- `configsys-ghostty` — Ghostty (Zig + GTK4)
- `configsys-hyprland` — Hyprland + ecosystem
- `configsys-cosmic` — COSMIC desktop (Rust)
- `configsys-blender`, `configsys-kicad` — already published

## How a recipe looks

```
components: {
    ripgrep: { install: [
        { via: source
          repo: "https://github.com/BurntSushi/ripgrep"
          version: { github: BurntSushi/ripgrep }
          requires: cargo
          build: "cargo build --release && install -Dm755 target/release/rg $PREFIX/bin/rg" }
    ] }
}
```

`$PREFIX` (default `~/.local` at user scope), `$SRC`, `$VERSION`, `$ARCH` are substituted; the
binary lands on your PATH. See configsys's `docs/routing-model.md` and the `source` driver for the
full field set (`repo`/`url`+`version`, `build`, `requires`, `uninstall-cmd`, `installDir`,
`prefix`, `ref`, `tag-prefix`).

## Verification

Recipes are transcribed from each project's own build docs. A representative subset (≥1 per build
system) is container-built as a regression gate (`test/`); recipes not yet build-verified are
marked `// UNVERIFIED` in the data.

## License

MIT © Trevor Schrock
