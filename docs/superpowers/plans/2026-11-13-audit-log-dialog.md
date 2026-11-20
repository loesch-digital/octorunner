# Audit Log Dialog for v0.5.0

The approved plan calls for category, severity, and runner filters, plus export.
The dialog uses SwiftData and the existing theme cards and supports German and
English. A toolbar button opens a resizable sheet.

1. Start with failing tests for real SwiftData filters, bounded loading, DTO
   export with Unicode and ISO dates, and NSHostingView rendering for empty and
   populated lists in Light and Dark appearances.
2. Build the dynamic FetchDescriptor using stored fields only. Load the 200 most
   recent events first and let users load more in batches. Run filtering and
   search in the database.
3. Show all details for the selected event, including before and after values.
   Snapshot the displayed rows as values and export JSON through the native save
   dialog. Limit export to the file the user selects in the dialog.
4. Add events for app startup and shutdown, and for update starts and failures.
   Preserve existing authentication, import, and configuration events. Crash
   detection is planned for the v0.6.0 supervisor.
5. Verify German and English, accessibility, and screenshots at multiple sizes.
   Run the Swift and Python tests and the build. Get an independent branch
   review, wait for PR CI to pass, merge, and verify CI on main.

Label the export action “Export Displayed Events.” It exports exactly the
current filtered set, including any additional events the user has loaded. The
export reads historical records and stored text without modifying them.
