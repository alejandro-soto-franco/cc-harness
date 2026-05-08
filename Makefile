# cc-harness Makefile — DESTDIR-aware so packagers can stage.
.POSIX:

PREFIX              ?= /usr/local
DESTDIR             ?=
BINDIR              ?= $(PREFIX)/bin
MANDIR              ?= $(PREFIX)/share/man
MAN1DIR             ?= $(MANDIR)/man1
BASH_COMPLETION_DIR ?= $(PREFIX)/share/bash-completion/completions
ZSH_COMPLETION_DIR  ?= $(PREFIX)/share/zsh/site-functions
FISH_COMPLETION_DIR ?= $(PREFIX)/share/fish/vendor_completions.d

VERSION := $(shell awk -F'"' '/^readonly CCH_VERSION=/{print $$2}' bin/cc-harness)
DIST    := dist
NAME    := cc-harness
TARBALL := $(DIST)/$(NAME)-$(VERSION).tar.gz

INSTALL ?= install
PANDOC  ?= pandoc
SHELLCHECK ?= shellcheck
SHFMT   ?= shfmt
BATS    := tests/bats/bin/bats

.PHONY: all completions man install uninstall test lint fmt fmt-check dist deb rpm clean help

all: completions man ## Build everything

help: ## List targets
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---------------------------------------------------------------- generated --

completions: completions/$(NAME).bash completions/$(NAME).zsh completions/$(NAME).fish ## Regenerate shell completions

completions/$(NAME).bash: bin/cc-harness
	@mkdir -p completions
	bin/cc-harness completion bash > $@

completions/$(NAME).zsh: bin/cc-harness
	@mkdir -p completions
	bin/cc-harness completion zsh > $@

completions/$(NAME).fish: bin/cc-harness
	@mkdir -p completions
	bin/cc-harness completion fish > $@

man: man/$(NAME).1 ## Build the man page

man/$(NAME).1: man/$(NAME).1.md
	$(PANDOC) -s -t man $< -o $@

# ----------------------------------------------------------------- install --

install: all ## Install bin, man, completions
	$(INSTALL) -D -m 0755 bin/cc-harness $(DESTDIR)$(BINDIR)/cc-harness
	$(INSTALL) -D -m 0644 man/$(NAME).1 $(DESTDIR)$(MAN1DIR)/$(NAME).1
	$(INSTALL) -D -m 0644 completions/$(NAME).bash $(DESTDIR)$(BASH_COMPLETION_DIR)/$(NAME)
	$(INSTALL) -D -m 0644 completions/$(NAME).zsh  $(DESTDIR)$(ZSH_COMPLETION_DIR)/_$(NAME)
	$(INSTALL) -D -m 0644 completions/$(NAME).fish $(DESTDIR)$(FISH_COMPLETION_DIR)/$(NAME).fish
	$(INSTALL) -D -m 0644 projects.conf.example $(DESTDIR)$(PREFIX)/share/$(NAME)/projects.conf.example

uninstall: ## Reverse install (config + state are left in place)
	rm -f $(DESTDIR)$(BINDIR)/cc-harness
	rm -f $(DESTDIR)$(MAN1DIR)/$(NAME).1
	rm -f $(DESTDIR)$(BASH_COMPLETION_DIR)/$(NAME)
	rm -f $(DESTDIR)$(ZSH_COMPLETION_DIR)/_$(NAME)
	rm -f $(DESTDIR)$(FISH_COMPLETION_DIR)/$(NAME).fish
	rm -f $(DESTDIR)$(PREFIX)/share/$(NAME)/projects.conf.example
	-rmdir $(DESTDIR)$(PREFIX)/share/$(NAME) 2>/dev/null || true

# ------------------------------------------------------------- test / lint --

test: ## Run the bats test suite
	$(BATS) tests/unit tests/integration

lint: ## shellcheck against bin/cc-harness, install.sh, test helpers
	$(SHELLCHECK) -x bin/cc-harness install.sh tests/test_helper.bash

fmt: ## Reformat with shfmt
	$(SHFMT) -i 4 -ci -bn -w bin/cc-harness install.sh tests/test_helper.bash

fmt-check: ## Verify shfmt would not modify any tracked file
	$(SHFMT) -i 4 -ci -bn -d bin/cc-harness install.sh tests/test_helper.bash

# --------------------------------------------------------------- packaging --

dist: all ## Build a release tarball + sha256
	@mkdir -p $(DIST)
	tar --transform 's,^,$(NAME)-$(VERSION)/,' -czf $(TARBALL) \
	    bin/cc-harness man/$(NAME).1 completions LICENSE README.md \
	    projects.conf.example Makefile
	cd $(DIST) && sha256sum $(NAME)-$(VERSION).tar.gz > $(NAME)-$(VERSION).tar.gz.sha256
	@echo "  -> $(TARBALL)"

deb: dist ## Build a .deb (requires fpm)
	@command -v fpm >/dev/null 2>&1 || { echo "fpm required for deb target"; exit 1; }
	fpm -s dir -t deb -n $(NAME) -v $(VERSION) \
	    --license MIT --maintainer "Alejandro Soto Franco <sotofranco.eng@gmail.com>" \
	    --url "https://github.com/alejandro-soto-franco/cc-harness" \
	    --description "Multi-session Claude Code launcher backed by tmux" \
	    --depends tmux --depends bash \
	    --package $(DIST)/ \
	    bin/cc-harness=/usr/bin/cc-harness \
	    man/$(NAME).1=/usr/share/man/man1/$(NAME).1 \
	    completions/$(NAME).bash=/usr/share/bash-completion/completions/$(NAME) \
	    completions/$(NAME).zsh=/usr/share/zsh/site-functions/_$(NAME) \
	    completions/$(NAME).fish=/usr/share/fish/vendor_completions.d/$(NAME).fish

rpm: dist ## Build a .rpm (requires fpm)
	@command -v fpm >/dev/null 2>&1 || { echo "fpm required for rpm target"; exit 1; }
	fpm -s dir -t rpm -n $(NAME) -v $(VERSION) \
	    --license MIT --maintainer "Alejandro Soto Franco <sotofranco.eng@gmail.com>" \
	    --url "https://github.com/alejandro-soto-franco/cc-harness" \
	    --description "Multi-session Claude Code launcher backed by tmux" \
	    --depends tmux --depends bash \
	    --package $(DIST)/ \
	    bin/cc-harness=/usr/bin/cc-harness \
	    man/$(NAME).1=/usr/share/man/man1/$(NAME).1 \
	    completions/$(NAME).bash=/usr/share/bash-completion/completions/$(NAME) \
	    completions/$(NAME).zsh=/usr/share/zsh/site-functions/_$(NAME) \
	    completions/$(NAME).fish=/usr/share/fish/vendor_completions.d/$(NAME).fish

clean: ## Remove generated artifacts
	rm -rf $(DIST) man/$(NAME).1
