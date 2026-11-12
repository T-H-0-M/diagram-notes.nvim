NVIM ?= nvim
VELLUM_PATH ?= $(CURDIR)/.deps/vellum.nvim
VELLUM_REV = 4ec5d4979f7d3fb08a799a432a71b4c7feee9144

.PHONY: deps test test-export test-pdf test-preview test-setup test-notes smoke smoke-pdf check

deps: .deps/vellum.nvim/.git

.deps/vellum.nvim/.git:
	git clone https://github.com/blackhat-7/vellum.nvim .deps/vellum.nvim
	git -C .deps/vellum.nvim checkout --detach $(VELLUM_REV)

test: test-export test-preview test-setup test-notes test-pdf

test-export:
	$(NVIM) --headless --clean -l tests/excalidraw.lua

test-preview:
	VELLUM_PATH="$(VELLUM_PATH)" $(NVIM) --headless --clean -l tests/preview.lua

test-setup:
	$(NVIM) --headless --clean -l tests/setup.lua

test-notes:
	$(NVIM) --headless --clean -l tests/notes.lua

test-pdf:
	$(NVIM) --headless --clean -l tests/export.lua

smoke-pdf:
	VELLUM_PATH="$(VELLUM_PATH)" $(NVIM) --headless --clean -l tests/pdf_smoke.lua

smoke:
	$(NVIM) --headless --clean -l tests/render_smoke.lua
	python3 tests/check_png.py

check:
	stylua --check lua plugin tests
	git diff --check
