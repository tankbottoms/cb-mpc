# Visual Guide Style Guide

**Reference Implementation**: `threshold-signing.html`

Copy this file's structure exactly when creating new pages. Do not deviate from these patterns.

## CSS Variables & Theme

### Root Variables (Always Include)

```css
:root {
  --font-mono: 'SF Mono', 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace;
  --border-w: 3px;
  --shadow-offset: 5px;
  --radius: 0;
  --alice: #6366f1;
  --bob: #f59e0b;
  --carol: #10b981;
  --public: #3b82f6;
  --private: #ef4444;
  --mail: #8b5cf6;
}
```

### Light Theme (Required)

```css
[data-theme="light"] {
  --bg: #f5f0e8;
  --card: #ffffff;
  --card2: #f0ebe3;
  --text: #1a1a1a;
  --muted: #6b7280;
  --border: #1a1a1a;
  --shadow-color: #1a1a1a;
}
```

### Dark Theme (REQUIRED - Use This Exact Palette)

```css
[data-theme="dark"] {
  --bg: #0f172a;        /* Deep blue-slate */
  --card: #1e293b;      /* Medium slate */
  --card2: #334155;     /* Lighter slate (hover) */
  --text: #e2e8f0;      /* Light slate text */
  --muted: #94a3b8;     /* Muted slate */
  --border: #475569;    /* Border/active */
  --shadow-color: #000000;
}
```

**NEVER use the old harsh palette**: #0f0f0f, #1a1a1a, #1e1e1e, #e5e5e5, etc.

## Body Layout (CRITICAL)

```css
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  font-family: var(--font-mono);
  background: var(--bg);
  color: var(--text);
  line-height: 1.6;
  padding: 2rem;
  max-width: 1200px;
  margin: 0 auto;
  transition: background 0.3s, color 0.3s;
}
```

**These three lines are MANDATORY**:
- `padding: 2rem;` - Constrains content from edges
- `max-width: 1200px;` - Limits line length
- `margin: 0 auto;` - Centers content

Missing any of these breaks the entire layout.

## Navigation Styles

### .doc-nav Container

```css
.doc-nav {
  display: flex;
  gap: 0;
  margin: 0 auto 2rem;
  width: 100%;
  border: var(--border-w) solid var(--border);
  box-shadow: var(--shadow-offset) var(--shadow-offset) 0 var(--shadow-color);
  overflow: hidden;
  flex-wrap: wrap;
}
```

### .nav-link Items (3-Column Grid)

```css
.nav-link {
  flex: 0 1 calc(100% / 3);         /* THIS creates 3-column grid */
  text-align: center;
  padding: 0.5rem 0.4rem;
  font-family: var(--font-mono);
  font-size: 0.7rem;
  font-weight: 700;
  text-decoration: none;
  color: var(--text);
  background: var(--card);
  border-right: var(--border-w) solid var(--border);
  border-bottom: var(--border-w) solid var(--border);
  transition: background 0.15s;
  white-space: nowrap;              /* Prevent text wrapping */
  overflow: hidden;
  text-overflow: ellipsis;
  display: flex;
  align-items: center;
  justify-content: center;
}
```

### Border Removal (Grid Appearance)

```css
.nav-link:nth-child(3n) { border-right: none; }          /* Remove right border on cols 3, 6, 9 */
.nav-link:nth-last-child(-n+3) { border-bottom: none; }  /* Remove bottom border on last 3 items */
```

### States

```css
.nav-link:hover { background: var(--card2); }

.nav-link.active {
  background: var(--border);
  color: var(--text);               /* NOT var(--card) - critical for contrast */
}
```

**Active State Critical Detail**: Use `color: var(--text)` not `var(--card)` for proper contrast in dark mode.

## HTML Structure

All pages must have this structure:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Page Title — Visual Guide</title>
  <style>
    /* All CSS here (see above) */
  </style>
</head>
<body data-theme="light">
  <button class="theme-toggle" onclick="toggleTheme()" id="themeBtn">[ LIGHT ]</button>

  <nav class="doc-nav">
    <a href="/index.html" class="nav-link">Demo Guide</a>
    <a href="/threshold-signing.html" class="nav-link">Threshold Signing</a>
    <a href="/dkg-ceremony.html" class="nav-link">DKG Ceremony</a>
    <a href="/device-to-device.html" class="nav-link">Device-to-Device</a>
    <a href="/server-architecture.html" class="nav-link">Server Architecture</a>
    <a href="/shamir-splitting.html" class="nav-link">Shamir Splitting</a>
    <a href="/ios-encryption-backup-strategy.html" class="nav-link">iOS Encryption</a>
    <a href="/key-management.html" class="nav-link">Key Management</a>
    <a href="/signing-operations.html" class="nav-link">Signing Ops</a>
  </nav>

  <!-- Your content here -->

  <script>
    function toggleTheme() {
      const html = document.documentElement;
      const btn = document.getElementById('themeBtn');
      const current = html.getAttribute('data-theme') || 'light';
      const next = current === 'light' ? 'dark' : 'light';
      html.setAttribute('data-theme', next);
      btn.textContent = `[ ${next.toUpperCase()} ]`;
      localStorage.setItem('theme', next);
    }

    window.addEventListener('DOMContentLoaded', () => {
      const saved = localStorage.getItem('theme') || 'light';
      document.documentElement.setAttribute('data-theme', saved);
      document.getElementById('themeBtn').textContent = `[ ${saved.toUpperCase()} ]`;
    });
  </script>
</body>
</html>
```

## Typography

### Headings

```css
h1 {
  text-align: center;
  font-size: 2rem;
  margin-bottom: 0.5rem;
  background: linear-gradient(135deg, var(--alice), var(--bob), var(--carol));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}

h2 {
  font-size: 1.3rem;
  font-weight: 600;
  margin: 2.5rem 0 1rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border-left: 6px solid var(--party-0);
  padding-left: 0.75rem;
}
```

### Paragraphs

```css
p { margin: 0.5rem 0; font-size: 0.82rem; }

.subtitle {
  text-align: center;
  color: var(--muted);
  margin-bottom: 3rem;
  font-size: 0.9rem;
}
```

## Common Components

### Step/Section Containers

```css
.step {
  margin-bottom: 2rem;
  border: var(--border-w) solid var(--border);
  overflow: hidden;
  background: var(--card);
  box-shadow: var(--shadow-offset) var(--shadow-offset) 0 var(--shadow-color);
}

.step-header {
  padding: 1rem 1.5rem;
  border-bottom: 1px solid var(--border);
}
```

### Diagram Containers

```css
.diagram {
  padding: 1.5rem;
  background: var(--card2);
  border-top: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
}
```

## Print Styles (Always Include)

```css
@media print {
  body { background: white; color: #1e293b; padding: 1rem; }
  .step { break-inside: avoid; border-color: #ccc; background: white; }
  .diagram { background: #f8fafc; }
  h1 { -webkit-text-fill-color: #1e293b; background: none; }
  .theme-toggle, .doc-nav { display: none; }
}
```

## Implementation Checklist

When creating a new page:

- [ ] Copy `threshold-signing.html` as template
- [ ] Update `<title>` to page name
- [ ] Use EXACT CSS variables (dark theme palette)
- [ ] Include body padding/max-width/margin
- [ ] Include .doc-nav with all 9 links
- [ ] Set correct active state on current page
- [ ] Include toggleTheme() JavaScript
- [ ] Test light/dark theme toggle
- [ ] Test responsive/print styles
- [ ] Verify nav displays 3x3 grid without word wrapping
- [ ] Deploy to Cloudflare Workers

## Common Mistakes (DO NOT REPEAT)

1. ❌ Using old harsh color palette (#0f0f0f, #e5e5e5)
   - ✓ Always use slate: #0f172a, #1e293b, #334155, #475569

2. ❌ Missing body padding/max-width/margin
   - ✓ All three are MANDATORY: `padding: 2rem; max-width: 1200px; margin: 0 auto;`

3. ❌ Using `flex: 1` instead of `flex: 0 1 calc(100% / 3)`
   - ✓ The 3-column calculation is not optional

4. ❌ Not including white-space and text-overflow on nav items
   - ✓ Nav text MUST use: `white-space: nowrap; overflow: hidden; text-overflow: ellipsis;`

5. ❌ Using var(--card) for active state text
   - ✓ Must use var(--text) for proper dark mode contrast

6. ❌ Forgetting nth-child border removal
   - ✓ Grid appearance requires: `.nav-link:nth-child(3n) { border-right: none; }` etc.

---

**Last Updated**: 2026-03-11
**Status**: All 9 pages follow this guide
**Reference**: threshold-signing.html (never changed without updating this guide)
