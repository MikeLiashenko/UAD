extends RefCounted
## Build stamp, written by build.ps1 on every build — do not edit by hand.
## BUILD grows by one with each build; the database keeps the newest published one
## (uad/release) and a game that is behind offers the update in the main menu.
## People see the version name: VERSION (major.minor), the number of the build within that
## version, and the stage — "v1.5.1 Alpha". Version 1.5 (mods) begins after build VERSION_BASE:
## build 44 is v1.5.1, build 45 is v1.5.2 and so on. The builds before it keep their names: v1.0.N up
## to build 11, v1.1.N (N = build − 11) for builds 12 to 22, v1.3.N (N = build − 22) for 23 to 33,
## v1.4.N (N = build − 33) for 34 to 43.
## (Builds 34 … 43 first came out as v1.3.12 … v1.3.21 and were renamed to v1.4.1 … v1.4.10.)

const VERSION := "1.5"
const VERSION_BASE := 43
## Builds 12 … 22 came out as version 1.1.
const V11_BASE := 11
## Builds 23 … 33 came out as version 1.3.
const V13_BASE := 22
## Builds 34 … 43 came out as version 1.4.
const V14_BASE := 33
const STAGE := "Alpha"
const BUILD := 45
const DATE := "2026-10-25"
const COMMIT := "776b49d"


## "v1.5.1 Alpha" for the given build number (this build by default).
static func label(build: int = BUILD) -> String:
	if build <= V11_BASE:
		return "v1.0.%d %s" % [build, STAGE]
	if build <= V13_BASE:
		return "v1.1.%d %s" % [build - V11_BASE, STAGE]
	if build <= V14_BASE:
		return "v1.3.%d %s" % [build - V13_BASE, STAGE]
	if build <= VERSION_BASE:
		return "v1.4.%d %s" % [build - V14_BASE, STAGE]
	return "v%s.%d %s" % [VERSION, build - VERSION_BASE, STAGE]
