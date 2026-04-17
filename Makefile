.PHONY: help install build test-place clean

DIST_DIR   := dist
TEST_PLACE := $(DIST_DIR)/test-place.rbxl
PACKAGE    := $(DIST_DIR)/rosa.rbxm

help:
	@echo "Rosa RBX Pipeline"
	@echo ""
	@echo "  make install      Install Wally dependencies"
	@echo "  make build        Build the distributable .rbxm package"
	@echo "  make test-place   Build a Roblox place for running tests in Studio"
	@echo "  make clean        Remove all build artifacts"
	@echo "  make serve        Rojo serves module to ReplicatedStorage

install:
	wally install

$(DIST_DIR):
	mkdir -p $(DIST_DIR)

build: install $(DIST_DIR)
	rojo build default.project.json --output $(PACKAGE)
	@echo "Built: $(PACKAGE)"

test-place: install $(DIST_DIR)
	rojo build test.project.json --output $(TEST_PLACE)
	@echo "Built: $(TEST_PLACE)"
	@echo "Opening. in Roblox Studio and run TestRunner under ServerScriptService."
	open $(TEST_PLACE)

clean:
	rm -rf $(DIST_DIR)

serve:
	rojo serve default.project.json

sourcemap:
	rojo sourcemap default.project.json --output sourcemap.json
