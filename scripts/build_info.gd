extends RefCounted
## Build stamp, written by build.ps1 on every build — do not edit by hand.
## BUILD grows by one with each build; the database keeps the newest published one
## (uad/release) and a game that is behind offers the update in the main menu.
## People see the version name: VERSION (major.minor) with the build number as the third part,
## and the stage — "v1.0.7 Alpha".

const VERSION := "1.0"
const STAGE := "Alpha"
const BUILD := 8
const DATE := "2026-09-26"
const COMMIT := "f899bf2"


## "v1.0.7 Alpha" for the given build number (this build by default).
static func label(build: int = BUILD) -> String:
	return "v%s.%d %s" % [VERSION, build, STAGE]
