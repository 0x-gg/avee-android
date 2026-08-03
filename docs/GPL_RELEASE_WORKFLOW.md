# GPL source release workflow

The Android repository is distributed under GPL-3.0 and keeps upstream
attribution for AVEE, FlClashX, FlClash, and mihomo/Clash.Meta in the
English README and `LICENSE`.

`scripts/verify-gpl-release.ps1` is the release-candidate check. It:

1. verifies the GPL-3.0 license and required upstream notices;
2. resolves an exact commit or tag;
3. archives the application and checked-out GPL submodules;
4. emits a gzip source archive and a SHA-256 checksum.

The GitHub workflow runs on `v*` tags or manual dispatch and uploads the
archive as a CI artifact. It does not publish a GitHub release, deploy an
APK, or sign a binary. Those remain deliberate human-controlled release
steps.

Local verification:

```powershell
pwsh ./scripts/verify-gpl-release.ps1 -Tag HEAD -OutputDirectory ./release-source
Get-Content ./release-source/*.sha256
```
