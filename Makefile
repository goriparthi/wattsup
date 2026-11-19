# Every target delegates to scripts/, so CI, humans and agents run the identical code path.
.PHONY: help build test ci bundle install run dmg release clean

help:
	@echo "wattsup targets:"
	@echo "  make build    Release build of the binary"
	@echo "  make test     Unit tests"
	@echo "  make ci       Everything CI runs"
	@echo "  make bundle   Assemble and sign dist/Wattsup.app"
	@echo "  make install  Install to ~/Applications and launch"
	@echo "  make run      Debug build, launched with the dashboard open"
	@echo "  make dmg      Signed DMG in dist/, notarized when NOTARY_PROFILE is set"
	@echo "  make release  Test, notarized DMG, GitHub release"
	@echo "  make clean    Remove .build and dist"

build:
	@scripts/build.sh
test:
	@scripts/test.sh
ci:
	@scripts/ci.sh
bundle:
	@scripts/bundle.sh
install:
	@scripts/install.sh
run:
	@swift build && .build/debug/wattsup --dashboard
dmg:
	@scripts/package-dmg.sh
release:
	@scripts/release.sh
clean:
	@rm -rf .build dist
