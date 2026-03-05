# iOS Demo App Build Notes

## Session: 2026-03-02

### Issue Resolution: Boost Podspec

**Problem**: React Native 0.73 was unable to download boost from the JFrog artifactory (repository was offline/redirecting).

**Solution**: Updated boost.podspec to use the official Boost archives mirror.

**File Modified**:
```
node_modules/react-native/third-party-podspecs/boost.podspec
```

**Change**:
```ruby
# Before (JFrog - offline)
spec.source = { :http => 'https://boostorg.jfrog.io/artifactory/main/release/1.83.0/source/boost_1_83_0.tar.bz2' }

# After (Official Archives - working)
spec.source = { :http => 'https://archives.boost.io/release/1.83.0/source/boost_1_83_0.tar.bz2' }
```

### Pod Installation

✓ **Status**: Successfully completed

```
Pod install took 11 seconds to run
Integrating client project
Pod installation complete! There are 59 dependencies from the Podfile and 59 total pods installed.
```

### Podfile Adjustments

1. **Added**: `use_modular_headers!` - Required for Swift pods to link as static libraries with React Native
2. **Removed**: `:ccache_enabled` parameter - Not supported in React Native 0.73's `react_native_post_install` function
3. **Simplified**: Removed boost workaround code (no longer needed with correct source)

### Xcode Build

**Started**: 2026-03-02 at 6:45 PM
**Command**: `npx expo run:ios`
**Configuration**: Debug
**Destination**: iOS Simulator

Note: First builds of React Native apps typically take 10-20+ minutes. Build is in progress.

### For Future Builds

Add a postinstall script to package.json to automatically patch the boost.podspec:

```json
"scripts": {
  "postinstall": "sed -i '' 's|https://boostorg.jfrog.io.*|https://archives.boost.io/release/1.83.0/source/boost_1_83_0.tar.bz2|' node_modules/react-native/third-party-podspecs/boost.podspec"
}
```

### Key Takeaways

- **JFrog Artifactory Issue**: The original JFrog repository for boost was offline. This is a known issue affecting React Native 0.71-0.73.
- **Official Mirror Works**: `https://archives.boost.io/` is the official Boost archives mirror and provides reliable access.
- **Configuration**: Using `archives.boost.io` resolves the issue without downgrading React Native.

### Next Steps

1. Wait for Xcode build to complete
2. Verify app launches on iOS Simulator
3. Test mock crypto flows (DKG, Sign, Verify)
4. Document any runtime issues

---

**Build Machine**: macOS (Xcode 15, Swift 5.x)
**Expo Version**: 50.0.21
**React Native Version**: 0.73.0
**iOS Deployment Target**: 13.4
