# OctoRunner interface design

OctoRunner uses native macOS window controls and navigation. The main window keeps **Runners**, **Jobs & Workflow Runs**, and **Host Telemetry** in the sidebar. Runner configuration, logs, and audit details open from the corresponding context. **Settings** is a separate window.

## Appearance and interaction

- Use the shared theme in `DesignSystem` and verify Light and Dark appearances. The app follows the macOS appearance.
- Pair status colors with labels or symbols. Show runner availability separately from the last job result. A failed job and an unavailable runner call for different actions.
- Preserve readable content when windows resize. Use scrolling for long lists, forms, and logs. Keep filters and primary actions accessible at supported window sizes.
- Give controls useful accessibility labels and hints. Check keyboard focus and VoiceOver. Use WCAG 2.2 AA contrast targets of 4.5:1 for standard text and 3:1 for essential interface graphics.
- Write user-facing copy in English and German. Use the string catalogs for labels and status messages and check both languages when text may wrap.

[Current dialogs and workflows](user-guide.md) · [Current screenshots](../README.md#screenshots) · [Original design references](02-design-system-and-hig.md) · [Original screen studies](assets/screens)
