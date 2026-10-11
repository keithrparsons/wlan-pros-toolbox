# Working in this repo

The WLAN Pros Toolbox is one Flutter app. Read ARCHITECTURE.md before changing structure, and CONTRIBUTING.md before adding a dependency.

## Accuracy first

- This app is used to make real decisions about real networks. A tool that is confidently wrong is worse than no tool.
- Cite the source for every formula, constant and table value in the code or its help entry.
- Every tool has a help entry in `assets/help/tool_help.json`; change it in the same commit as the tool.

## Keep the code simple

Write the simplest code that solves the stated problem.
- Prefer the boring, obvious implementation over the clever one.
- No speculative abstraction: no layers for needs that don't exist yet.
- No unrequested features: no options, settings or flags that weren't asked for.
- No error handling for conditions that cannot occur.
- Fewer files, fewer layers: a function beats a class.
- If a plan has machinery the requirements don't need, say so before building it.

## How to build

- Before a non-trivial change, propose two or three approaches and wait for the maintainer's pick.
- Build in phases small enough to review as one diff.
- A phase is done when `flutter analyze` is clean and `flutter test` passes. Then simplify it (remove what the phase does not need) and run both again.
- Commit after each green, simplified phase, so every phase is a rollback point.
- Never add a GPL-family dependency (see CONTRIBUTING.md).
