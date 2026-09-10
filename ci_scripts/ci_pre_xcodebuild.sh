#!/usr/bin/env bash

set -euo pipefail

# This phase consumes already-built test products without a source checkout.
if [[ "${CI_XCODEBUILD_ACTION:-}" == "test-without-building" ]]; then
  exit 0
fi

# Xcode Cloud starts this hook in ci_scripts, not the repository root.
cd "${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH must point to the checkout}"

# The cloud image includes Homebrew, but not the JDK needed by Kotlin/Native.
# Use the same JDK major version as the SDK's release build, without sudo.
export HOMEBREW_NO_AUTO_UPDATE=1
if ! brew list --versions openjdk@17 >/dev/null 2>&1; then
  brew install openjdk@17
fi
java_prefix="$(brew --prefix openjdk@17)"
export JAVA_HOME="$java_prefix/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
java -version

# Checkout the host SDK's pinned gitlink; never follow the submodule's main.
git submodule update --init --recursive -- notifly-kmp-sdk

# Gradle/Java do not read Xcode Cloud's proxy environment variables themselves.
# JAVA_TOOL_OPTIONS reaches the wrapper, Gradle daemon and Kotlin compiler.
if [[ -n "${HTTP_PROXY:-}${HTTPS_PROXY:-}" ]]; then
  proxy_options="$(python3 - <<'PY'
import os
import re
from urllib.parse import urlsplit

options = []
for protocol in ("http", "https"):
    value = os.environ.get(protocol.upper() + "_PROXY")
    if not value:
        continue
    try:
        proxy = urlsplit(value)
        host = proxy.hostname or ""
        port = proxy.port if proxy.port is not None else 80
        if (proxy.scheme != "http" or proxy.username is not None
                or proxy.password is not None or not 1 <= port <= 65535
                or not re.fullmatch(r"[A-Za-z0-9.:[\]-]+", host)):
            raise ValueError()
    except ValueError:
        raise SystemExit("Unsupported Xcode Cloud proxy URL; expected an unauthenticated HTTP proxy.")
    options.extend((f"-D{protocol}.proxyHost={host}", f"-D{protocol}.proxyPort={port}"))
print(" ".join(options))
PY
)"
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }$proxy_options"
fi

# The test app references build/NotiflyCore.xcframework in a clean checkout.
exec ./scripts/build_kmp_core_xcframework.sh
