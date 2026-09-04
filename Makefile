.PHONY: install uninstall test lint

PREFIX ?= $(HOME)/.local
BINDIR  = $(PREFIX)/bin

install:
	@echo "==> Installing nixpm to $(BINDIR)"
	@mkdir -p $(BINDIR)
	@cp bin/nixpm $(BINDIR)/nixpm
	@chmod +x $(BINDIR)/nixpm
	@echo "==> Done. Make sure $(BINDIR) is in your PATH."

uninstall:
	@echo "==> Removing $(BINDIR)/nixpm"
	@rm -f $(BINDIR)/nixpm

test:
	@bash -n bin/nixpm
	@echo "Syntax OK"

lint: test
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck bin/nixpm; \
	else \
		echo "shellcheck not installed, skipping"; \
	fi
