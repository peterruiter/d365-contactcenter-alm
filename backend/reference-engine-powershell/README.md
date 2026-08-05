# Reference engine (PowerShell)

This is not the app. It's a reference implementation of the cross-environment compare, plan, write, and rollback logic, written in PowerShell so it runs standalone and documents the exact Web API operations the backend performs.

The code app in `../../app` calls a backend that does this work under a service principal. When we build that backend (Azure Function), this module is the spec: same manifest, same GUID remapping, same stage ordering, same ruleset double-write. Port it, don't reinvent it.

See `../../docs/architecture.md` for how the pieces fit.
