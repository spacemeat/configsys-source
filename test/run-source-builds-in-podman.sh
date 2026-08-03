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
'lazydocker|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o lazydocker . && install -Dm755 lazydocker /root/.local/bin/lazydocker && /root/.local/bin/lazydocker --version'
'lazysql|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o lazysql . && install -Dm755 lazysql /root/.local/bin/lazysql && /root/.local/bin/lazysql --version'
'k9s|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o k9s . && install -Dm755 k9s /root/.local/bin/k9s && /root/.local/bin/k9s version --short'
'just|archlinux:latest|pacman -Sy --noconfirm --needed rust git|cargo build --release && install -Dm755 target/release/just /root/.local/bin/just && /root/.local/bin/just --version'
'jq|fedora:41|dnf install -y -q gcc make autoconf automake libtool bison flex git|git submodule update --init && autoreconf -fi && ./configure --prefix=/root/.local --with-oniguruma=builtin --disable-maintainer-mode && make && make install && /root/.local/bin/jq --version'
'opentofu|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o tofu ./cmd/tofu && install -Dm755 tofu /root/.local/bin/tofu && /root/.local/bin/tofu version'
'bazelisk|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o bazelisk . && install -Dm755 bazelisk /root/.local/bin/bazelisk && test -x /root/.local/bin/bazelisk && echo built'
'grpcurl|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -o grpcurl ./cmd/grpcurl && install -Dm755 grpcurl /root/.local/bin/grpcurl && /root/.local/bin/grpcurl --version'
'nushell|archlinux:latest|pacman -Sy --noconfirm --needed rust git|cargo build --release --bin nu && install -Dm755 target/release/nu /root/.local/bin/nu && /root/.local/bin/nu --version'
'yazi|archlinux:latest|pacman -Sy --noconfirm --needed rust git|cargo build --release --locked && install -Dm755 target/release/yazi /root/.local/bin/yazi && install -Dm755 target/release/ya /root/.local/bin/ya && /root/.local/bin/yazi --version'
'mtr|fedora:41|dnf install -y -q gcc make autoconf automake pkgconf-pkg-config ncurses-devel git|./bootstrap.sh && ./configure --prefix=/root/.local --sbindir=/root/.local/bin --without-gtk && make && make install && /root/.local/bin/mtr --version'
'curl|fedora:41|dnf install -y -q gcc make autoconf automake libtool pkgconf-pkg-config openssl-devel zlib-devel git|autoreconf -fi && ./configure --prefix=/root/.local --with-openssl --with-zlib --without-libpsl && make && make install && /root/.local/bin/curl --version'
'helm|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -trimpath -o helm ./cmd/helm && install -Dm755 helm /root/.local/bin/helm && /root/.local/bin/helm version'
'neovim|fedora:41|dnf install -y -q gcc gcc-c++ make cmake ninja-build gettext curl unzip git|make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX=/root/.local && make install && /root/.local/bin/nvim --version'
'nethogs|fedora:41|dnf install -y -q gcc gcc-c++ make libpcap-devel ncurses-devel git|make && install -Dm755 src/nethogs /root/.local/bin/nethogs && test -x /root/.local/bin/nethogs && echo nethogs-built'
'jmtpfs|fedora:41|dnf install -y -q gcc-c++ make pkgconf-pkg-config libmtp-devel fuse-devel libusb1-devel file-devel git|./configure --prefix=/root/.local && make && make install && test -x /root/.local/bin/jmtpfs && echo jmtpfs-built'
'iperf3|fedora:41|dnf install -y -q gcc make git|./configure --prefix=/root/.local && make && make install && /root/.local/bin/iperf3 --version'
'vnstat|fedora:41|dnf install -y -q gcc make sqlite-devel git|./configure --prefix=/root/.local && make && make install && /root/.local/bin/vnstat --version'
# NOTE: git and nmap are source-buildable and verified out-of-band, but are NOT gated here.
# Both trip a rootless-podman user-namespace quirk where `tar` cannot chmod certain archived
# dirs as container-root (git's install-time template tree; nmap's bundled `zenmap` dir on
# extraction) — a sandbox limitation, not a recipe fault (both extract+build fine as a real
# user). Verified by hand: git 2.47.1 (+ working git-remote-https clone); nmap 7.99 (C++ compile,
# host-extracted tree built in-container).
)

declare -A repo=(
  [ripgrep]=https://github.com/BurntSushi/ripgrep [lazygit]=https://github.com/jesseduffield/lazygit
  [superfile]=https://github.com/yorukot/superfile [htop]=https://github.com/htop-dev/htop
  [tmux]=https://github.com/tmux/tmux [fzf]=https://github.com/junegunn/fzf
  [btop]=https://github.com/aristocratos/btop [fastfetch]=https://github.com/fastfetch-cli/fastfetch
  [lazydocker]=https://github.com/jesseduffield/lazydocker [lazysql]=https://github.com/jorgerojas26/lazysql
  [k9s]=https://github.com/derailed/k9s [just]=https://github.com/casey/just [jq]=https://github.com/jqlang/jq
  [opentofu]=https://github.com/opentofu/opentofu [bazelisk]=https://github.com/bazelbuild/bazelisk
  [grpcurl]=https://github.com/fullstorydev/grpcurl [nushell]=https://github.com/nushell/nushell
  [yazi]=https://github.com/sxyazi/yazi [mtr]=https://github.com/traviscross/mtr
  [curl]=https://github.com/curl/curl [helm]=https://github.com/helm/helm
  [neovim]=https://github.com/neovim/neovim [nethogs]=https://github.com/raboof/nethogs
  [jmtpfs]=https://github.com/JasonFerrara/jmtpfs [iperf3]=https://github.com/esnet/iperf
  [vnstat]=https://github.com/vergoh/vnstat
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
