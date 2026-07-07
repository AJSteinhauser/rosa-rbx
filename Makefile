.PHONY: help install build test-place clean release

DIST_DIR   := dist
TEST_PLACE := $(DIST_DIR)/test-place.rbxl
PACKAGE    := $(DIST_DIR)/rosa.rbxm

help:
	@echo "Rosa RBX"
	@echo ""
	@echo "  make install      Install Wally dependencies and configure git hooks"
	@echo "  make build        Build the distributable .rbxm model"
	@echo "  make test-place   Build a Roblox place for running tests in Studio"
	@echo "  make release      Build and publish a GitHub release (version from wally.toml)"
	@echo "  make clean        Remove all build artifacts"
	@echo "  make serve        Rojo serves module to ReplicatedStorage"

install:
	wally install
	git config core.hooksPath .githooks
	@echo "Git hooks configured (pre-commit syncs version from wally.toml)"

$(DIST_DIR):
	mkdir -p $(DIST_DIR)

build: install $(DIST_DIR)
	rojo build model.project.json --output $(PACKAGE)
	open $(DIST_DIR)
	@echo "Built: $(PACKAGE)"

test-place: install $(DIST_DIR)
	rojo build test.project.json --output $(TEST_PLACE)
	@echo "Built: $(TEST_PLACE)"
	@echo "Opening. in Roblox Studio and run TestRunner under ServerScriptService."
	open $(TEST_PLACE)

release: build
	@VERSION=$$(grep '^version' wally.toml | sed 's/version = "\(.*\)"/\1/'); \
	TAG="v$$VERSION"; \
	if gh release view "$$TAG" > /dev/null 2>&1; then \
		echo "ERROR: Release $$TAG already exists. Increment the version in wally.toml first."; \
		exit 1; \
	fi; \
	gh release create "$$TAG" $(PACKAGE) --title "$$TAG" --generate-notes; \
	wally publish; \
	git add wally.lock && git commit -m "Wally publish $$TAG"; \
	echo "Released: $$TAG"

clean:
	rm -rf $(DIST_DIR)

serve:
	rojo serve default.project.json

sourcemap:
	rojo sourcemap default.project.json --output sourcemap.json
