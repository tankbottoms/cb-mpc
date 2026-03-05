#!/usr/bin/env bash

xcodebuild build -scheme CBMPCNative -project CBMPCNative.xcodeproj \
    -destination "platform=iOS,name=iPhone 15 Pro Max" \
    -configuration Release
