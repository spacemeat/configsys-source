#!/usr/bin/env bash
# Container build-verification for configsys-source recipes — the ongoing regression gate.
#
# For each (component, image, deps, build) row it installs the build deps in a fresh container,
# clones the repo, runs the recipe's build command into a prefix, and asserts the binary runs.
# This proves the RECIPE (build command + dependency names) on a distro with a recent-enough
# toolchain. It does NOT go through configsys itself — it verifies the build data directly.
#
# Networked + container-bound (like configsys's run-name-sweep-in-podman.sh): NOT part of pytest.
# Usage:  bash test/run-source-builds-in-podman.sh [comp1,comp2,...]   (default: all)
#
# Toolchain-floor note: cargo/go recipes need a recent Rust/Go. We verify on images whose packaged
# toolchain is new enough (Arch for the newest floors, Fedora for autotools). A distro with an
# older Rust/Go will fail the build by design — that's the documented caveat, not a recipe bug.
set -uo pipefail
RT=${CONTAINER_RUNTIME:-podman}
want=${1:-}

# rows: name|image|install-deps-cmd|build-cmd (build runs in the clone dir; installs to /root/.local)
rows=(
'ripgrep|archlinux:latest|pacman -Sy --noconfirm --needed rust git|cargo build --release && install -Dm755 target/release/rg /root/.local/bin/rg && /root/.local/bin/rg --version'
'lazygit|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o lazygit . && install -Dm755 lazygit /root/.local/bin/lazygit && /root/.local/bin/lazygit --version'
'superfile|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o spf . && install -Dm755 spf /root/.local/bin/spf && /root/.local/bin/spf --version'
'htop|fedora:41|dnf install -y -q gcc make autoconf automake pkgconf-pkg-config ncurses-devel git|./autogen.sh && ./configure --prefix=/root/.local && make && make install && /root/.local/bin/htop --version'
'tmux|fedora:41|dnf install -y -q gcc make autoconf automake pkgconf-pkg-config ncurses-devel libevent-devel bison git|sh autogen.sh && ./configure --prefix=/root/.local && make && make install && /root/.local/bin/tmux -V'
'fzf|archlinux:latest|pacman -Sy --noconfirm --needed go git|mkdir -p /root/.local/bin && go build -o /root/.local/bin/fzf && /root/.local/bin/fzf --version'
'btop|fedora:41|dnf install -y -q gcc-c++ make git|make && make install PREFIX=/root/.local && /root/.local/bin/btop --version'
'fastfetch|fedora:41|dnf install -y -q gcc cmake make git|cmake -B build -DCMAKE_INSTALL_PREFIX=/root/.local && cmake --build build && cmake --install build && /root/.local/bin/fastfetch --version'
)

declare -A repo=(
  [ripgrep]=https://github.com/BurntSushi/ripgrep [lazygit]=https://github.com/jesseduffield/lazygit
  [superfile]=https://github.com/yorukot/superfile [htop]=https://github.com/htop-dev/htop
  [tmux]=https://github.com/tmux/tmux [fzf]=https://github.com/junegunn/fzf
  [btop]=https://github.com/aristocratos/btop [fastfetch]=https://github.com/fastfetch-cli/fastfetch
)

fail=0
for row in "${rows[@]}"; do
  IFS='|' read -r name img deps build <<<"$row"
  [ -n "$want" ] && [[ ",$want," != *",$name,"* ]] && continue
  echo ">> building $name on $img"
  out=$("$RT" run --rm "$img" bash -c "
    set -e; export DEBIAN_FRONTEND=noninteractive
    $deps >/dev/null 2>&1
    git clone --depth 1 ${repo[$name]} /s >/dev/null 2>&1; cd /s
    $build" 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then echo "   OK: $(echo "$out" | tail -1)"; else
    echo "   FAILED (exit $rc): $(echo "$out" | tail -2 | tr '\n' ' ')"; fail=$((fail+1)); fi
done

echo
if [ $fail -eq 0 ]; then echo "source builds: OK"; else echo "source builds: $fail FAILED"; exit 1; fi
