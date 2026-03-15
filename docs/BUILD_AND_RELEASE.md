# Build and Release Workflow

Complete guide for the iOS build/release lifecycle — from commit to TestFlight.

## Quick Reference

```bash
# Full release cycle
./scripts/release.sh prepare minor     # 1. Bump version, generate draft
./scripts/build-changelog.sh approve   # 2. Review and approve
./scripts/release.sh build             # 3. Archive iOS build
# Upload via Xcode: Product -> Archive -> Distribute App -> TestFlight
./scripts/release.sh submit            # 4. Push metadata to ASC
./scripts/release.sh status            # 5. Check build processing
```

## 1. Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/) to drive automatic changelog generation:

| Prefix | Purpose | Changelog Section |
|--------|---------|-------------------|
| `feat:` | New feature | NEW |
| `fix:` | Bug fix | FIXES |
| `chore:` | Maintenance, deps | (omitted) |
| `docs:` | Documentation | (omitted) |
| `test:` | Tests | (omitted) |
| `refactor:` | Code restructuring | OTHER |

Scoped prefixes are supported: `feat(ios):`, `fix(key-server):`, etc.

**Examples:**

```
feat(ios): add HD key derivation for BIP-32 child keys
fix: CryptoKit SealedBox slice crash in Release builds
chore: bump version to v0.24.0 (build 76)
```

## 2. Version Bumping

Versions follow [semver](https://semver.org/) as defined in `CLAUDE.md`:

| Bump | When | Example |
|------|------|---------|
| **Patch** `0.24.x` | Bug fixes, minor UI tweaks | Fix crash, adjust spacing |
| **Minor** `0.x.0` | New features, new views, new API bindings | Add HD derivation, new tab |
| **Major** `x.0.0` | Breaking changes, architecture overhauls | New key format, protocol change |

Both values live in `CBMPCNative.xcodeproj/project.pbxproj`:

- `MARKETING_VERSION` — semver string (e.g., `0.24.0`)
- `CURRENT_PROJECT_VERSION` — integer build number, increments every build (e.g., `76`)

The `release.sh prepare` command handles bumping automatically:

```bash
./scripts/release.sh prepare patch   # 0.24.0 -> 0.24.1
./scripts/release.sh prepare minor   # 0.24.0 -> 0.25.0
./scripts/release.sh prepare major   # 0.24.0 -> 1.0.0
```

## 3. Changelog Generation

### Automatic (Recommended)

```bash
./scripts/build-changelog.sh prepare
```

This generates two files in `docs/iOS-AppStore/changelogs/`:

1. **JSON manifest** (`v0.25.0-build77.json`) — structured data for automation:
   ```json
   {
     "version": "0.25.0",
     "build": 77,
     "date": "2026-03-14",
     "status": "draft",
     "features": ["..."],
     "fixes": ["..."],
     "commits": [{"hash": "...", "type": "feat", "message": "..."}]
   }
   ```

2. **Approval doc** (`v0.25.0-build77-approval.md`) — human-readable review document with checklist.

### Manual Preview

```bash
./scripts/build-changelog.sh show     # Preview without saving
./scripts/build-changelog.sh history  # List all changelogs
```

### How It Works

The changelog script:
1. Reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `project.pbxproj`
2. Finds the last `build/*` git tag
3. Collects commits since that tag touching `CBMPCNative/`, `key-server/src/`, or `src/`
4. Categorizes by conventional commit prefix (`feat:`, `fix:`, etc.)
5. Generates "What to Test" text and structured JSON

## 4. Approval Workflow

Every release goes through an explicit approval step before submission.

```
prepare  ->  [review]  ->  approve  ->  build  ->  [upload]  ->  submit
 (draft)                  (approved)                            (submitted)
```

### Review the Draft

After `prepare`, review the approval doc printed to stdout. Check:

- [ ] Feature list is accurate
- [ ] No sensitive information in changelog text
- [ ] Version bump is correct (patch/minor/major)
- [ ] Test instructions cover new functionality

### Approve

```bash
./scripts/build-changelog.sh approve
```

This updates the JSON manifest status from `draft` to `approved`. The `submit` command refuses to run unless the manifest is approved.

## 5. Build and Archive

### Build for Device

```bash
./scripts/release.sh build
```

This runs `xcodebuild` with Release configuration for `generic/platform=iOS`. The built `.app` is in:

```
~/Library/Developer/Xcode/DerivedData/CBMPCNative-*/Build/Products/Release-iphoneos/CBMPCNative.app
```

### Install to Device

```bash
xcrun devicectl device install app --device <UUID> /path/to/CBMPCNative.app
xcrun devicectl device process launch --device <UUID> xyz.atsignhandle.cb-mpc
```

### Archive for TestFlight

Use Xcode: **Product -> Archive -> Distribute App -> TestFlight Internal Testing**

Or via command line:

```bash
cd CBMPCNative
xcodebuild -project CBMPCNative.xcodeproj \
  -scheme CBMPCNative \
  -sdk iphoneos \
  -configuration Release \
  -archivePath build/CBMPCNative.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/CBMPCNative.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions-iOS.plist
```

## 6. TestFlight Submission

### Push Metadata

```bash
./scripts/release.sh submit
```

This chains three operations:
1. `build-changelog.sh record` — tags the build in git, saves markdown changelog
2. `build-changelog.sh push` — pushes "What to Test" text to ASC via API
3. `asc-metadata.sh upload` — uploads full metadata (description, keywords, categories)

### Manual Metadata Commands

```bash
./scripts/asc-metadata.sh info        # Fetch current app info from ASC
./scripts/asc-metadata.sh upload      # Push description, keywords, categories
./scripts/asc-metadata.sh age-rating  # Set age rating declaration
./scripts/asc-metadata.sh testflight  # Set TestFlight "What to Test"
./scripts/asc-metadata.sh review      # Set App Review contact info
./scripts/asc-metadata.sh all         # Run upload + age-rating + review
```

### Check Status

```bash
./scripts/release.sh status
```

Shows local version info, manifest status, and queries ASC for recent build processing state.

## 7. File Reference

| File | Purpose |
|------|---------|
| `scripts/release.sh` | Orchestrator — single entry point for full lifecycle |
| `scripts/build-changelog.sh` | Changelog generation, git tagging, ASC push |
| `scripts/asc-metadata.sh` | App Store Connect API metadata upload |
| `scripts/asc-upload-screenshots.py` | Screenshot upload to ASC |
| `CHANGELOG.md` | Human-readable version history |
| `docs/iOS-AppStore/changelogs/*.json` | Per-build structured manifests |
| `docs/iOS-AppStore/changelogs/*.md` | Per-build approval documents |
| `fastlane/metadata/en-US/` | Metadata text files (name, description, keywords, etc.) |
| `docs/iOS-AppStore/ios-app-details.md` | Reference doc for all ASC fields |

## 8. Environment Setup

Required environment variables (set in `.env` at project root):

```bash
ASC_KEY_ID=67F836A739
ASC_ISSUER_ID=99378080-0c4d-4766-8324-cf017d97e6a1
ASC_KEY_FILE=private_keys/AuthKey_67F836A739.p8
APP_ID=6760239004
```

Python dependencies for ASC API:

```bash
pip3 install PyJWT cryptography
```
