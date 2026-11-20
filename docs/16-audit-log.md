# Audit Log

Select **Audit Log** in the toolbar to open the local event history. The newest events appear first. Combine category, severity, and runner filters with a search of event titles and descriptions. The runner dropdown includes registered runners and names from the entire saved history, regardless of the current page or other filters. This keeps removed runners available for selection. Runner events show the associated runner on each row, and app-wide events have their own label.

The view initially loads up to 200 matches. **Load more events** adds up to 200 at a time. Search covers the full saved history. Click an event for its full details, including its ID, account, and before and after values when available.

**Export shown events…** saves the currently loaded, filtered events as JSON with schema version 1 and ISO 8601 timestamps. The app takes a snapshot before opening the save dialog. Load additional events first to include older entries. The export prompts for a destination. Opening the history reads the local event store without scanning user folders.

Alongside authentication, configuration, and runner events, the app records startup, shutdown, update start, update success and failure, and detected local process state changes. The first process measurement establishes a baseline. Runner process state and workflow job result are recorded separately. A force quit can bypass the regular shutdown entry. Full supervisor crash detection is part of v0.6.0.

New system and update events store a predefined set of metadata that excludes tokens, download URLs, and raw error messages. The export contains the visible audit information. Review saved runner names, account names, and configuration values before sharing it.

## Verification

- SwiftData filters, including combined filters, search, and load limits.
- JSON snapshots with Unicode, line breaks, stable identities, and timestamps.
- App and update events and process state changes without duplicate baseline entries.
- NSHostingView layout in a real window with empty and populated history at 680 and 1,100 points, in German and English and Light and Dark appearances.
- Native UI test in CI for opening, filtering, resetting, viewing details, and closing.
