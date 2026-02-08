publish-baseline:
	@scripts/publish-baseline.zsh

setup-git-hooks:
	@scripts/setup-git-hooks.sh

.PHONY: publish-baseline setup-git-hooks regenerate-agents-md

regenerate-agents-md:
	@scripts/generate-agents-index.sh
