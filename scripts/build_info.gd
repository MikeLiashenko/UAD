extends RefCounted
## Build stamp, written by build.ps1 on every build — do not edit by hand.
## BUILD grows by one with each build; the database keeps the newest published one
## (uad/release) and a game that is behind offers the update in the main menu.
## People see the version name: VERSION (major.minor), the number of the build within that
## version, and the stage — "v1.3.1 Alpha". Version 1.3 begins after build VERSION_BASE: build 23
## is v1.3.1, build 24 is v1.3.2 and so on. The builds before it keep the name they came out
## under: v1.0.N up to build 11, v1.1.N (N = build − 11) for builds 12 to 22.

const VERSION := "1.3"
const VERSION_BASE := 22
## Builds 12 … 22 came out as version 1.1.
const V11_BASE := 11
const STAGE := "Alpha"
const BUILD := 43
const DATE := "2026-10-21"
const COMMIT := "3b96071"


## "v1.3.1 Alpha" for the given build number (this build by default).
static func label(build: int = BUILD) -> String:
	if build <= V11_BASE:
		return "v1.0.%d %s" % [build, STAGE]
	if build <= VERSION_BASE:
		return "v1.1.%d %s" % [build - V11_BASE, STAGE]
	return "v%s.%d %s" % [VERSION, build - VERSION_BASE, STAGE]
