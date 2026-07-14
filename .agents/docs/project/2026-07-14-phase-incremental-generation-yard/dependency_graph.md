# Dependency Graph

## Execution Order
1. Milestone 1: Timestamp Tracker (no dependencies — new utility, independent of everything else)
2. Milestone 2: Wire Incremental Flag into CLI (depends on: Milestone 1 — needs TimestampTracker to exist)
3. Milestone 3: YARD Gem Integration (depends on: Milestone 2 — needs gemspec updated first, but Milestone 2 doesn't touch gemspec; Milestone 3 adds `yard` dep to gemspec. Can run in parallel with Milestone 2 if yard dep is added first, but Milestone 4 handles gemspec polish so ordering is: M2 and M3 can be parallel IF gemspec changes are coordinated)
4. Milestone 4: Version Bump, Gemspec Polish, Cleanup (depends on: Milestone 2, Milestone 3 — needs CLI and YardReader to be stable before bumping version)

### Note on Milestone 2 and 3 ordering:
Milestone 3 adds the `yard` dependency to `gemspec`. Milestone 2 doesn't touch `gemspec`. They can run in parallel since they modify different files.

If run in parallel, Milestone 4 must merge both gemspec changes (yard dep from M3, metadata from M4). The plan accounts for this — M4 is listed last and handles all gemspec metadata.
