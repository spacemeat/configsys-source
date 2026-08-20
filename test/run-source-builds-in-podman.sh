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
'yazi|archlinux:latest|pacman -Syu --noconfirm --needed base-devel rust git|cargo build --release --locked && install -Dm755 target/release/yazi /root/.local/bin/yazi && install -Dm755 target/release/ya /root/.local/bin/ya && /root/.local/bin/yazi --version'
'mtr|fedora:41|dnf install -y -q gcc make autoconf automake pkgconf-pkg-config ncurses-devel git|./bootstrap.sh && ./configure --prefix=/root/.local --sbindir=/root/.local/bin --without-gtk && make && make install && /root/.local/bin/mtr --version'
'curl|fedora:41|dnf install -y -q gcc make autoconf automake libtool pkgconf-pkg-config openssl-devel zlib-devel git|autoreconf -fi && ./configure --prefix=/root/.local --with-openssl --with-zlib --without-libpsl && make && make install && /root/.local/bin/curl --version'
'helm|archlinux:latest|pacman -Sy --noconfirm --needed go git|CGO_ENABLED=0 go build -trimpath -o helm ./cmd/helm && install -Dm755 helm /root/.local/bin/helm && /root/.local/bin/helm version'
'neovim|fedora:41|dnf install -y -q gcc gcc-c++ make cmake ninja-build gettext curl unzip git|make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX=/root/.local && make install && /root/.local/bin/nvim --version'
'nethogs|fedora:41|dnf install -y -q gcc gcc-c++ make libpcap-devel ncurses-devel git|make && install -Dm755 src/nethogs /root/.local/bin/nethogs && test -x /root/.local/bin/nethogs && echo nethogs-built'
'jmtpfs|fedora:41|dnf install -y -q gcc-c++ make pkgconf-pkg-config libmtp-devel fuse-devel libusb1-devel file-devel git|./configure --prefix=/root/.local && make && make install && test -x /root/.local/bin/jmtpfs && echo jmtpfs-built'
'iperf3|fedora:41|dnf install -y -q gcc make git|./configure --prefix=/root/.local && make && make install && /root/.local/bin/iperf3 --version'
'vnstat|fedora:41|dnf install -y -q gcc make sqlite-devel git|./configure --prefix=/root/.local && make && make install && /root/.local/bin/vnstat --version'
'ninja|fedora:41|dnf install -y -q gcc-c++ cmake make git|cmake -B build -DCMAKE_INSTALL_PREFIX=/root/.local -DCMAKE_BUILD_TYPE=Release && cmake --build build && cmake --install build && /root/.local/bin/ninja --version'
'protobuf|fedora:41|dnf install -y -q gcc-c++ cmake make git|git submodule update --init --recursive && cmake -B build -DCMAKE_INSTALL_PREFIX=/root/.local -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_ABSL_PROVIDER=module && cmake --build build && cmake --install build && /root/.local/bin/protoc --version'
'whois|fedora:41|dnf install -y -q gcc make perl libidn2-devel gettext git|make && make install prefix=/root/.local && test -x /root/.local/bin/whois && echo whois-built'
'cmake|fedora:41|dnf install -y -q gcc gcc-c++ make git openssl-devel|./bootstrap --prefix=/root/.local --parallel=$(nproc) && make -j$(nproc) && make install && /root/.local/bin/cmake --version | head -1'
'ffmpeg|fedora:41|dnf install -y -q gcc make nasm git|./configure --prefix=/root/.local --disable-doc --enable-gpl && make -j$(nproc) && make install && /root/.local/bin/ffmpeg -version | head -1'
# fastdds needs its two eProsima libs (foonathan_memory_vendor, Fast-CDR) built into the SAME prefix
# FIRST, then Fast-DDS with -DCMAKE_PREFIX_PATH so find_package locates them — the multi-repo chain
# configsys models via `requires:`. Here the build clones the two deps itself (the harness only clones
# the component's own repo). Asio/TinyXML2/OpenSSL come from the distro (asio-devel etc.).
'fastdds|fedora:41|dnf install -y -q gcc-c++ cmake make git asio-devel tinyxml2-devel openssl-devel|git clone --depth 1 https://github.com/eProsima/foonathan_memory_vendor /fm && cmake -S /fm -B /fm/b -DCMAKE_INSTALL_PREFIX=/root/.local -DBUILD_SHARED_LIBS=ON && cmake --build /fm/b -j$(nproc) --target install && git clone --depth 1 https://github.com/eProsima/Fast-CDR /fc && cmake -S /fc -B /fc/b -DCMAKE_INSTALL_PREFIX=/root/.local -DBUILD_SHARED_LIBS=ON && cmake --build /fc/b -j$(nproc) --target install && cmake -B build -DCMAKE_INSTALL_PREFIX=/root/.local -DCMAKE_PREFIX_PATH=/root/.local -DBUILD_SHARED_LIBS=ON -DCOMPILE_EXAMPLES=OFF -DBUILD_TESTING=OFF . && cmake --build build -j$(nproc) --target install && ls /root/.local/lib/libfastdds.so* /root/.local/lib/libfastrtps.so* 2>/dev/null | head -1 && echo fastdds-built'
# xpilot: the maintained kekyo/xpilot-ng fork; its `master` builds the SDL2/GL client + server on a
# modern toolchain (the legacy X11 clients need the removed Xxf86misc extension, so we --disable them).
'xpilot|ubuntu:24.04|apt-get update -qq && apt-get install -y -qq build-essential gcc-14 g++-14 autoconf automake libtool pkg-config libexpat1-dev zlib1g-dev libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev libgl1-mesa-dev libglu1-mesa-dev git|export CC="$(command -v gcc-14 || command -v gcc)"; export CXX="$(command -v g++-14 || command -v g++)"; ( ./bootstrap || autoreconf -fi ) && ./configure --prefix=/root/.local --disable-x11-client --disable-xp-mapedit --disable-replay && make -j$(nproc) && make install && ls /root/.local/bin/xpilot-ng-sdl /root/.local/bin/xpilot-ng-server && echo xpilot-built'
# NOTE: git and nmap are source-buildable and verified out-of-band, but are NOT gated here.
# Both trip a rootless-podman user-namespace quirk where `tar` cannot chmod certain archived
# dirs as container-root (git's install-time template tree; nmap's bundled `zenmap` dir on
# extraction) — a sandbox limitation, not a recipe fault (both extract+build fine as a real
# user). Verified by hand: git 2.47.1 (+ working git-remote-https clone); nmap 7.99 (C++ compile,
# host-extracted tree built in-container).
#
# desktop.hu source-first tools (suckless X + dwl/Wayland). Built on Arch (rolling) so the X/Wayland
# dev libs and, critically, wlroots are recent enough for dwl. dwmblocks/-async share the `dwmblocks`
# binary. These have no `--version`; assert the binary exists.
'dwm|archlinux:latest|pacman -Sy --noconfirm --needed base-devel libx11 libxinerama libxft git|make PREFIX=/root/.local clean install && test -x /root/.local/bin/dwm && echo dwm-built'
'st|archlinux:latest|pacman -Sy --noconfirm --needed base-devel libx11 libxft git|make PREFIX=/root/.local clean install && test -x /root/.local/bin/st && echo st-built'
'dmenu|archlinux:latest|pacman -Sy --noconfirm --needed base-devel libx11 libxinerama libxft git|make PREFIX=/root/.local clean install && test -x /root/.local/bin/dmenu && echo dmenu-built'
# NOTE: -Syu (full upgrade, not -Sy) on Arch — a partial upgrade pulls a newer python (meson's
# runtime) against the image's older glibc and breaks meson. dwmblocks/someblocks need a GCC-14
# pointer-error downgrade via CC; dwmblocks-async needs xcb added to LIBS; somebar needs config.hpp
# copied first. dwl is NOT gated here: it locks to one wlroots minor and Arch's rolling wlroots
# (0.20) no longer matches dwl master (0.19) — it can't build on Arch until they realign.
'dwm|archlinux:latest|pacman -Syu --noconfirm --needed base-devel libx11 libxinerama libxft git|make PREFIX=/root/.local clean install && test -x /root/.local/bin/dwm && echo dwm-built'
'st|archlinux:latest|pacman -Syu --noconfirm --needed base-devel libx11 libxft git|make PREFIX=/root/.local clean install && test -x /root/.local/bin/st && echo st-built'
'dmenu|archlinux:latest|pacman -Syu --noconfirm --needed base-devel libx11 libxinerama libxft git|make PREFIX=/root/.local clean install && test -x /root/.local/bin/dmenu && echo dmenu-built'
'dwmblocks|archlinux:latest|pacman -Syu --noconfirm --needed base-devel libx11 git|make CC="cc -Wno-error=incompatible-pointer-types" PREFIX=/root/.local install && test -x /root/.local/bin/dwmblocks && echo dwmblocks-built'
'dwmblocks-async|archlinux:latest|pacman -Syu --noconfirm --needed base-devel libxcb xcb-util git|make LIBS="xcb-atom xcb" PREFIX=/root/.local install && test -x /root/.local/bin/dwmblocks && echo dwmblocks-async-built'
'somebar|archlinux:latest|pacman -Syu --noconfirm --needed base-devel wayland wayland-protocols cairo pango meson ninja pkgconf git|cp src/config.def.hpp src/config.hpp && meson setup --prefix=/root/.local build && ninja -C build install && test -x /root/.local/bin/somebar && echo somebar-built'
'someblocks|archlinux:latest|pacman -Syu --noconfirm --needed base-devel git|make CC="cc -Wno-error=incompatible-pointer-types" PREFIX=/root/.local install && test -x /root/.local/bin/someblocks && echo someblocks-built'
'fff|archlinux:latest|pacman -Syu --noconfirm --needed base-devel git|make PREFIX=/root/.local install && test -x /root/.local/bin/fff && echo fff-built'
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
  [ninja]=https://github.com/ninja-build/ninja [protobuf]=https://github.com/protocolbuffers/protobuf
  [whois]=https://github.com/rfc1036/whois
  [cmake]=https://github.com/Kitware/CMake [ffmpeg]=https://github.com/FFmpeg/FFmpeg
  [fastdds]=https://github.com/eProsima/Fast-DDS
  [xpilot]=https://github.com/kekyo/xpilot-ng
  [dwm]=https://git.suckless.org/dwm [st]=https://git.suckless.org/st
  [dmenu]=https://git.suckless.org/dmenu
  [dwmblocks]=https://github.com/torrinfail/dwmblocks
  [dwmblocks-async]=https://github.com/UtkarshVerma/dwmblocks-async
  [dwl]=https://codeberg.org/dwl/dwl [somebar]=https://git.sr.ht/~raphi/somebar
  [someblocks]=https://git.sr.ht/~raphi/someblocks
  [fff]=https://github.com/dylanaraps/fff
)

# For projects whose default branch diverges from the release the RECIPE installs, build the latest
# vX.Y.Z tag instead of master (matching `version: {github}`): protobuf's master is mid-refactor and
# won't compile; yazi's default tag is a rolling `nightly`. Resolved host-side (needs git + network).
declare -A ref=(
  [protobuf]=latest [yazi]=latest [cmake]=latest
)

fail=0
for row in "${rows[@]}"; do
  IFS='|' read -r name img deps build <<<"$row"
  [ -n "$want" ] && [[ ",$want," != *",$name,"* ]] && continue
  echo ">> building $name on $img"
  branchopt=""
  if [ "${ref[$name]:-}" = latest ]; then
    tag=$(git ls-remote --tags --sort=-v:refname "${repo[$name]}" 2>/dev/null | grep -oE 'refs/tags/v[0-9.]+$' | head -1 | sed 's#refs/tags/##')
    [ -n "$tag" ] && branchopt="--branch $tag"
  fi
  out=$("$RT" run --rm "$img" bash -c "
    set -e; export DEBIAN_FRONTEND=noninteractive
    $deps >/dev/null 2>&1
    git clone --depth 1 $branchopt ${repo[$name]} /s >/dev/null 2>&1; cd /s
    $build" 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then echo "   OK: $(echo "$out" | tail -1)"; else
    echo "   FAILED (exit $rc): $(echo "$out" | tail -2 | tr '\n' ' ')"; fail=$((fail+1)); fi
done

echo
if [ $fail -eq 0 ]; then echo "source builds: OK"; else echo "source builds: $fail FAILED"; exit 1; fi
