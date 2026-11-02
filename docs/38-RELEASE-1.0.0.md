# Forever Hearthstone 1.0.0

- Set the public addon author to bbwfan85.
- Removed personal workstation paths from source documentation and art provenance.
- Added packaging checks for unexpected files, common credential formats and personal home-directory paths.
- Retains the gameplay and progression features from 0.2.5. Network protocol remains 10.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from ForeverHearthstone-1.0.0.zip, then restart WoW completely.

## Validation

All 1,281 automated suites passed (98,042 assertions), plus 20 compiler tests (247 checks). The release build verified 1,031 texture references and Lua syntax. The packaged-addon smoke test passed, and all 3,970 ZIP entries matched the staged files. Source and package scans found no embedded credentials or remaining personal workstation identifiers. Third-party attribution remains intact.

Live two-player networking and in-game visual verification were not performed for this metadata and packaging release.
