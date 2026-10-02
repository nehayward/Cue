# Thin wrappers around npm scripts. Run `make` to list them.

.DEFAULT_GOAL := help
.PHONY: help install dev test deploy tail og

help:  ## Show this help.
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

install:  ## Install dependencies (once).
	npm install

dev:  ## Run locally at http://localhost:8787 with live reload.
	npm run dev

test:  ## Run the tests.
	npm test

deploy: test  ## Test, then publish to cue.dance.
	npm run deploy

tail:  ## Stream production logs.
	npm run tail

CHROME ?= /Applications/Google Chrome.app/Contents/MacOS/Google Chrome

og:  ## Render the social card (scripts/og-card.html) to public/og.jpg.
	"$(CHROME)" --headless=new --disable-gpu --hide-scrollbars --force-prefers-reduced-motion \
		--window-size=1200,630 --virtual-time-budget=5000 \
		--screenshot="$(CURDIR)/build-og.png" "file://$(CURDIR)/scripts/og-card.html" 2>/dev/null
	sips -s format jpeg -s formatOptions 86 build-og.png --out public/og.jpg >/dev/null
	rm build-og.png
	@echo "public/og.jpg updated"
