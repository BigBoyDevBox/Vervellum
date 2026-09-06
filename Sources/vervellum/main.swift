import Foundation
import VervellumKit

// The whole executable. Everything else lives in VervellumKit, so the Linux front end
// and the shared research core compile as one module and need no public API surface
// between them — the only symbol this file needs is the entry point.
//
// Top-level code in `main.swift` rather than `@main`: the GTK main loop is entered from
// inside `VervellumLinuxApp.main()`, so there is nothing for Swift's async entry point
// to do, and `@main` with an async `main()` would start draining the dispatch main queue
// in competition with GLib's loop.
exit(VervellumLinuxApp.main())
