# Menu Bar Logo and Busy Detection

The user approved the OctoRunner logo with a status dot in front. Keep the
existing status colors, VoiceOver text, and tooltip. Use distinct status symbols
when Differentiate Without Color is enabled. Use the existing SVG geometry for
the scalable logo and keep the menu bar label free of TimelineView.

A live inspection found the listener at bin/Runner.Listener and the active
worker at bin.2.338.2/Runner.Worker. The local sampler matches only the exact
bin directory, so it reports IDLE.

- [x] Add a failing regression test for mixed and versioned binary directories, separate runners, and incorrect filenames. Apply the smallest parser fix and verify the test passes.
- [x] Add a failing image regression for a transparent logo, a separate status dot in Light and Dark appearances, and distinguishable status symbols. Draw the vector geometry from docs/assets/menubar_icon.svg and verify the test passes.
- [x] Run the full Swift and Python test suites, a native launch test, and the debug build. Review the rendered images.
- [ ] Push the feature branch and monitor PR CI until it passes. Then resume beta acceptance.

All 234 Swift tests and 18 Python tests passed, and the debug build succeeded.
The failing regression first reproduced the reported directory version
combination. The corrected sampler now returns busy=true for the running
listener and worker. All status images were reviewed in Light and Dark
appearances. An independent read-only review found no significant issues.
Restart the app normally to load the new build.
