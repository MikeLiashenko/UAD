extends RefCounted
## Build stamp, written by build.ps1 on every build — do not edit by hand.
## BUILD grows by one with each build; the database keeps the newest published one
## (uad/release) and a game that is behind offers the update in the main menu.
## People see the version name: VERSION (major.minor), the number of the build within that
## version, and the stage — "v1.1.3 Alpha". Version 1.1 begins after build VERSION_BASE: build 12
## is v1.1.1, build 13 is v1.1.2 and so on. The builds up to it keep the name they came out
## under, v1.0.N.

const VERSION := "1.1"
const VERSION_BASE := 11
const STAGE := "Alpha"
const BUILD := 13
const DATE := "2026-10-11"
const COMMIT := "5ea2a96"


## "v1.1.3 Alpha" for the given build number (this build by default).
static func label(build: int = BUILD) -> String:
	if build <= VERSION_BASE:
		return "v1.0.%d %s" % [build, STAGE]
	return "v%s.%d %s" % [VERSION, build - VERSION_BASE, STAGE]
