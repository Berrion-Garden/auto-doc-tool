# Dependency Graph: Fix FileTreeBuilder Exclusion Crash

```mermaid
graph TD
    M1["Milestone 1: Patch should_exclude? — Fix Crash and Verify on Both Fixtures"]
    
    M1 --> DONE["✅ Feature Complete"]
    
    style M1 fill:#4CAF50,stroke:#388E3C,color:white
    style DONE fill:#2196F3,stroke:#1976D2,color:white
```

## Build Order

| Order | Milestone | Type | Depends On |
|-------|-----------|------|------------|
| 1 | Milestone 1: Patch should_exclude? | Self-contained | Nothing |

**Total milestones: 1**

### Notes

- This is a single-milestone project because the bug fix is a 2-line change in one method of one file
- All prerequisites (gem loadable, fixture directories exist, previous fixes verified) are checked in playbook Section 0
- Milestone 1 is independently testable — no other milestone needs to complete first
- Feature complete immediately upon Milestone 1 verification passing
