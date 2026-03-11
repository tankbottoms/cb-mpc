# CB-MPC Visual Guide

A comprehensive neo-brutalist visual guide to multi-party computation (MPC) concepts and iOS app workflows. Designed with monospace typography, hard shadows, and rectangular geometry following brutalist design principles.

## Pages

### Core MPC Concepts

1. **Threshold Signing** (`threshold-signing.html`)
   - Shamir's secret sharing fundamentals
   - Distributed key generation (DKG) ceremony workflow
   - Multi-party signing coordination
   - Party communication and secret share distribution

2. **DKG Ceremony** (`dkg-ceremony.html`)
   - Distributed key generation process
   - Polynomial evaluation and commitment
   - Secret share exchange
   - Key reconstruction and verification

3. **Device-to-Device** (`device-to-device.html`)
   - Peer-to-peer MPC communication
   - Device coordination and synchronization
   - Signing workflows across multiple devices
   - Network topology and message flow

4. **Server Architecture** (`server-architecture.html`)
   - Coordinator/validator architecture
   - Key share storage and retrieval
   - Transaction signing flow
   - API endpoints and request/response patterns

5. **Shamir Splitting** (`shamir-splitting.html`)
   - Shamir secret sharing mathematical foundation
   - Polynomial reconstruction
   - Threshold schemes (t-of-n)
   - Computational complexity and security

### iOS App Workflows

6. **Key Management** (`key-management.html`)
   - Dashboard states (empty, populated)
   - Key creation workflows (5 modes: solo, assisted, collaborative, imported, recovery)
   - Key detail views and operations
   - Export/import functionality

7. **Signing Operations** (`signing-operations.html`)
   - Message signing workflows
   - Transaction signing flows
   - QR code export and import cycles
   - Approval and verification steps

8. **iOS Encryption & Backup Strategy** (`ios-encryption-backup-strategy.html`)
   - Local storage encryption
   - Backup topology and strategies
   - Key derivation and storage options
   - Recovery workflows

### Navigation Hub

9. **Demo Guide** (`index.html`)
   - Landing page with overview of all concepts
   - Quick navigation to all visual guides
   - Feature descriptions and use cases

## Design System

All pages follow a consistent **neo-brutalist** design system:

- **Typography**: Monospace fonts (SF Mono, JetBrains Mono, Fira Code)
- **Spacing**: 3px borders, 5px shadows, rectangular geometry
- **Colors**: Sophisticated slate palette (see STYLE_GUIDE.md)
- **Layout**: Centered, max-width 1200px with 2rem padding
- **Navigation**: 3-column grid layout with 9 nav items

See `STYLE_GUIDE.md` for detailed CSS patterns and implementation guidelines.

## Usage

These pages are generated as static HTML and deployed to Cloudflare Workers. They require no backend and can be served as static assets.

### Local Development

Open any `.html` file directly in a browser. All pages support light/dark theme toggle via button in top-right corner.

### Deployment

Files are deployed to: https://cb-mpc-visual-guide.atsignhandle.workers.dev

To redeploy after changes:
```bash
cd /Users/mark.phillips/Developer/cb-mpc-ux
wrangler deploy
```

## Purpose

These visual guides serve as:

1. **Educational Material** - Explain complex MPC concepts through interactive diagrams
2. **Design System Reference** - Show the iOS app's UX patterns and workflows
3. **Product Documentation** - Quick reference for stakeholders and developers
4. **Design Precedent** - Template for creating new documentation pages

## Future Pages

When creating new pages, follow the exact pattern in `STYLE_GUIDE.md`. Use `threshold-signing.html` as a template - do not deviate from the documented CSS and theme structure.

---

**Last Updated**: 2026-03-11
**Theme**: Neo-brutalist with slate color palette
**Status**: All 9 pages deployed and consistent
