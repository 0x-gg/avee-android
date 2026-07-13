# Dropweb architecture notes

Dropweb is a Flutter application with an Android native VPN integration and a Go-based Mihomo core under `core/`. The Android Gradle project packages the native core and exposes VPN control through Kotlin plugins. Profile parsing, persistence, connection state, and country-mode behavior remain upstream responsibilities until a reviewed AVEE issue changes them.
