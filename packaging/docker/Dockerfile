# Build context: dist/<musl-target>/stage, matching the requested image platform.
# This image contains a CLI scaffold, not a gateway service.
FROM debian:trixie-slim
LABEL org.opencontainers.image.title="SecureTunnelRG scaffold"
LABEL org.opencontainers.image.source="https://github.com/vvhh2002/SecureTunnelRG"
# Keep optional packages out of future role-specific runtime installs.
RUN printf '%s\n' 'APT::Install-Recommends "false";' 'APT::Install-Suggests "false";' \
    > /etc/apt/apt.conf.d/99securetunnel-minimal
COPY bin/securetunnel-rg /usr/local/bin/securetunnel-rg
COPY BUILD-INFO.txt README.md LICENSE /usr/share/securetunnel/
USER 65532:65532
# QEMU may run the wrong CPU architecture successfully: check the manifest too.
ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64) target=x86_64-unknown-linux-musl ;; \
      arm64) target=aarch64-unknown-linux-musl ;; \
      *) echo "Unsupported image architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && grep -Fxq "gateway=SecureTunnelRG" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "app_package=securetunnel-app" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "app_binary=securetunnel-rg" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "application_source=SecureTunnelAPP" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "target=$target" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "runtime_packaging=eligible-static-musl" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "runtime_distribution=debian" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "runtime_suite=trixie" /usr/share/securetunnel/BUILD-INFO.txt \
    && grep -Fxq "runtime_base_image=debian:trixie-slim" /usr/share/securetunnel/BUILD-INFO.txt
RUN ["/usr/local/bin/securetunnel-rg", "--version"]
ENTRYPOINT ["/usr/local/bin/securetunnel-rg"]
CMD ["--help"]
