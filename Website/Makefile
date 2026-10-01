# Thin wrappers around npm scripts. Run `make` to list them.

.DEFAULT_GOAL := help
.PHONY: help install dev test deploy tail

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
