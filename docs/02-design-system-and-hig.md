---
name: macOS HIG Desktop Application
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#393939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1b1b1c'
  surface-container: '#202020'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353535'
  on-surface: '#e5e2e1'
  on-surface-variant: '#c1c6d7'
  inverse-surface: '#e5e2e1'
  inverse-on-surface: '#303030'
  outline: '#8b90a0'
  outline-variant: '#414755'
  surface-tint: '#adc6ff'
  primary: '#adc6ff'
  on-primary: '#002e69'
  primary-container: '#4b8eff'
  on-primary-container: '#00285c'
  inverse-primary: '#005bc1'
  secondary: '#53e16f'
  on-secondary: '#003911'
  secondary-container: '#05b046'
  on-secondary-container: '#003a11'
  tertiary: '#ffb868'
  on-tertiary: '#482900'
  tertiary-container: '#ce7f00'
  on-tertiary-container: '#3f2300'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d8e2ff'
  primary-fixed-dim: '#adc6ff'
  on-primary-fixed: '#001a41'
  on-primary-fixed-variant: '#004493'
  secondary-fixed: '#72fe88'
  secondary-fixed-dim: '#53e16f'
  on-secondary-fixed: '#002107'
  on-secondary-fixed-variant: '#00531c'
  tertiary-fixed: '#ffddbb'
  tertiary-fixed-dim: '#ffb868'
  on-tertiary-fixed: '#2b1700'
  on-tertiary-fixed-variant: '#673d00'
  background: '#131313'
  on-background: '#e5e2e1'
  surface-variant: '#353535'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 28px
  headline-md:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
  headline-sm:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '600'
    lineHeight: 20px
  body-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  body-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 14px
  label-lg:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
  label-md:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
  label-sm:
    fontFamily: Inter
    fontSize: 10px
    fontWeight: '600'
    lineHeight: 12px
  code-md:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  code-sm:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 16px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 0.75rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style

This design system targets macOS desktop engineering environments, specifically supporting developer operations, runner infrastructure, and continuous integration workflows. The aesthetic directly honors Apple Human Interface Guidelines (HIG) for modern macOS versions, combining native desktop utility with precision terminal telemetry.

The emotional baseline is focused, reliable, and authentic:
- **Desktop Authenticity**: The UI must feel completely native to macOS, rejecting web-first paradigms in favor of standard system patterns, split views, toolbar items, and platform-accurate window chrome.
- **Developer Rigor**: Runner status, resource gauges, and system telemetry demand tight information density, instant visual scanning, and terminal-grade legibility.
- **Vibrant Hierarchy**: Depth is communicated through calibrated material translucency, layered vibrancy, and subtle structural hairline borders rather than heavy decoration.

## Colors

The palette reproduces native macOS system color roles across both Dark and Light Appearances, supplemented with ANSI terminal colors for process logs and status indicators.

### Appearance Modes & Surfaces
- **Dark Appearance (Default)**:
  - Base Window Background: `#1E1E1E`
  - Sidebar / Secondary Background: `#252526` (with material blur)
  - Elevated Container / Card: `#2D2D2D`
  - Active Selection / Control Surface: `#3A3A3C`
  - Separators & Hairlines: `#383838` (and `rgba(255, 255, 255, 0.08)`)
  - Primary Content / Labels: `#FFFFFF`
  - Secondary Content: `#8E8E93`
  - Tertiary / Disabled Content: `#545458`
- **Light Appearance (Aqua)**:
  - Base Window Background: `#FFFFFF`
  - Sidebar / Secondary Surface: `#ECECEC`
  - Elevated Control Surface: `#F6F6F6`
  - Separators & Hairlines: `#D1D1D6` (and `rgba(0, 0, 0, 0.1)`)
  - Primary Content / Labels: `#1D1D1F`
  - Secondary Content: `#6E6E73`

### Accent & Semantic Roles
- **System Blue (Primary)**: `#007AFF` — standard push buttons, active segmented tabs, focused states.
- **System Green (Secondary / Online)**: `#34C759` — active runner state, idle listening, completed jobs.
- **System Orange (Tertiary / Warning)**: `#FF9F0A` — rate limits, pending builds, warning telemetry.
- **System Red (Destructive / Error)**: `#FF3B30` — process failure, terminated services, stop runner actions.
- **System Purple (Job Hook)**: `#AF52DE` — custom workflow extensions and matrix steps.

### Terminal & Log Stream (ANSI Colors)
- Terminal Background: `#181818`
- Terminal Foreground: `#D4D4D4`
- Terminal ANSI Yellow: `#E5C07B`
- Terminal ANSI Cyan: `#56B6C2`
- Terminal ANSI Magenta: `#C678DD`
- Terminal ANSI Blue: `#61AFEF`

## Typography

Typography strictly mirrors the scale, tracking, and optical rhythm of macOS desktop software. System UI roles utilize standard grotesque proportions (implemented via Inter as the cross-platform equivalent for SF Pro), while terminal streams, PID badges, Git commit hashes, and runner tags rely on a monospace hierarchy.

- **Window Titlebar & Section Headers**: Set in `headline-sm` (`15px/600`) or `headline-md` (`17px/600`) with tight tracking (`-0.015em`).
- **Standard Controls & Table Views**: Standard push buttons, segmented labels, list items, and inspector fields use `body-md` (`13px/400`) and `label-lg` (`13px/500`).
- **Metadata & Subtext**: Timestamps, service descriptions, and column headers use `body-sm` (`11px/400`) and `label-md` (`11px/500`) in secondary label color.
- **Process Output & Key-Value Pairs**: All console feeds, CLI commands, and environment variables use `code-md` (`12px/400`) and `code-sm` (`11px/400`).

## Layout & Spacing

Layout conforms to the standard macOS three-pane navigation and inspector model:
1. **Source List (Sidebar)**: Collapsible fixed/flexible panel (`200px` to `280px` wide) housing runner groups, organizations, and service states.
2. **Primary Content (Master/Detail)**: Work pool, active job queues, and real-time execution graphs.
3. **Inspector Panel (Trailing Sidebar)**: Details, environment flags, and launchd controls (`260px` to `320px` wide).

### Rhythms & Metrics
- Native desktop applications rely on an internal 4px/8px metric grid. 
- List item height is standardized at `28px` for compact sidebar rows and `36px` to `44px` for data table rows.
- Standard form and control vertical gaps use `space-sm` (`8px`).
- Section padding inside inspector cards uses `space-md` (`12px`) or `space-lg` (`16px`).
- macOS titlebar height is fixed at `52px` (including standard window control inset).

## Elevation & Depth

Visual hierarchy does not use exaggerated dropshadows. It relies on platform materials, backdrop vibrancies, and hairline borders.

### Surface Materials
- **Window Frame**: Standard desktop window has an outline border of `1px solid rgba(255, 255, 255, 0.12)` in dark mode and `1px solid rgba(0, 0, 0, 0.15)` in light mode, with an outer window drop shadow: `0 24px 48px rgba(0, 0, 0, 0.35)`.
- **Sidebar Vibrancy**: `backdrop-filter: blur(20px)` over semi-transparent surface tokens (`#252526D9` in dark mode, `#ECECECD9` in light mode).
- **Elevated Controls (Cards & Popovers)**:
  - Surface: `#2D2D2D`
  - Border: `1px solid #383838`
  - Shadow: `0 4px 12px rgba(0, 0, 0, 0.2)`
- **Modal Sheets**: Present from the top titlebar edge with a smooth curved scrim, elevated with `0 16px 32px rgba(0, 0, 0, 0.4)`.

## Shapes

Shapes mirror macOS Big Sur/Sonoma geometry:
- **Application Window**: Outer frame corners use a continuous curvature radius of `10px` to `12px` (traffic light controls inset by `16px` horizontally, `18px` vertically).
- **Controls & Buttons**: Native push buttons and input controls use `5px` to `6px` radius (`roundedness: 1`).
- **Segmented Controls**: Outer track uses `6px` radius; internal sliding segment uses `5px` radius with a `2px` internal margin.
- **Pills & Status Indicators**: Service status dots use `50%` circular radius (`8px` diameter). Tag labels and runner pool badges use `4px` subtle rounding.
- **Terminal Console Container**: Set inside cards with `6px` internal corner radius and `1px` crisp borders.

## Components

### Window Chrome & Titlebar
- **Traffic Lights**: Circular buttons (`12px` diameter, `8px` gap) positioned top-left (`Close: #FF5F56`, `Minimize: #FFBD2E`, `Maximize: #27C93F`). Hover displays internal symbol glyphs.
- **Unified Toolbar**: Seamless integration of titlebar and controls. Houses search fields, runner state filters, and unified segmented controls.

### Push Buttons
- **Default Action**: System Blue background (`#007AFF`), white text, `1px` subtle top highlight (`rgba(255, 255, 255, 0.15)`), active scale-down (`0.98`).
- **Standard Button**: Translucent fill (`rgba(255, 255, 255, 0.08)` dark / `rgba(0, 0, 0, 0.05)` light), border `1px solid rgba(255, 255, 255, 0.12)`, text primary.
- **Destructive Button**: Text `#FF3B30`, border `1px solid rgba(255, 59, 48, 0.3)`.

### Segmented Controls
- Continuous capsule track filled with `#1E1E1E` (dark) or `#E5E5EA` (light).
- Selected segment: `#3A3A3C` (dark) or `#FFFFFF` (light) with soft hairline shadow (`0 1px 3px rgba(0, 0, 0, 0.15)`).

### Service Status Indicators (launchd / Daemon)
- **Active / Listening**: `#34C759` pulse dot with green outline ring.
- **Busy / Executing Job**: Animated progress ring or alternating `#007AFF` pulse.
- **Offline / Stale**: `#8E8E93` solid dot.
- **Faulted**: `#FF3B30` indicator with retry stepper option.

### Data Tables & Runner Lists
- Alternating row zebra option disabled by default in favor of clean macOS lines.
- Hover row state: `rgba(255, 255, 255, 0.04)`.
- Selected row: Vibrant System Blue fill (`#007AFF`) with white text, or subtle selection tint (`rgba(0, 122, 255, 0.15)`) when table is out of focus.

### Inputs & Steppers
- Input fields: Inset background (`#181818`), `1px solid #383838`, focus ring `0 0 0 3px rgba(0, 122, 255, 0.35)`.
- Stepper controls: Stacked vertical arrow segment attached directly to the right border of numerical concurrency inputs.

### Terminal Output Area
- Fixed pitch stream with ANSI-color highlighting.
- Embedded mini action bar containing "Auto-scroll", "Clear", and "Export Log" toolbar icons.