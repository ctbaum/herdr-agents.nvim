FROM debian:bookworm-slim

ARG TARGETARCH
ARG NVIM_VERSION=v0.11.4
ARG HERDR_VERSION=0.7.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git jq procps zsh \
    && case "$TARGETARCH" in \
         amd64) nvim_arch=x86_64; herdr_arch=x86_64 ;; \
         arm64) nvim_arch=arm64; herdr_arch=aarch64 ;; \
         *) echo "unsupported Docker architecture: $TARGETARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${nvim_arch}.tar.gz" \
       | tar -xz -C /opt \
    && ln -s "/opt/nvim-linux-${nvim_arch}/bin/nvim" /usr/local/bin/nvim \
    && curl -fsSL "https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-${herdr_arch}" \
       -o /usr/local/bin/herdr-real \
    && chmod +x /usr/local/bin/herdr-real \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN mkdir -p /tmp/xdg/data/nvim/site/pack/test/start \
    && cp -R /src /tmp/xdg/data/nvim/site/pack/test/start/herdr-agents.nvim \
    && for spec in \
         'claudecode.nvim https://github.com/coder/claudecode.nvim.git 2390c6e45c4789072c293ac69de051d169668b29' \
         'codex.nvim https://github.com/ishiooon/codex.nvim.git e6b5eaa4b83c5f2085150ea80da2e2d103ee5f32' \
         'snacks.nvim https://github.com/folke/snacks.nvim.git 882c996cf28183f4d63640de0b4c02ec886d01f2'; do \
       set -- $spec; path="/tmp/xdg/data/nvim/site/pack/test/start/$1"; \
       git init "$path"; git -C "$path" remote add origin "$2"; \
       git -C "$path" fetch --depth 1 origin "$3"; \
       git -C "$path" checkout --detach FETCH_HEAD; \
     done \
    && install -m755 tests/docker/fake-herdr /usr/local/bin/herdr \
    && install -m755 tests/docker/real-nvim.sh /usr/local/bin/herdr-agents-real-nvim \
    && ln -s /bin/true /usr/local/bin/claude \
    && ln -s /bin/true /usr/local/bin/codex \
    && chmod +x tests/docker/e2e.sh

ENV HOME=/tmp/home \
    XDG_DATA_HOME=/tmp/xdg/data \
    XDG_CONFIG_HOME=/tmp/xdg/config \
    HERDR_SOCKET_PATH=/tmp/herdr.sock \
    HERDR_PANE_ID=nvim-pane \
    HERDR_NVIM_PROMPT_MATCH='$'

ENTRYPOINT ["tests/docker/e2e.sh"]
