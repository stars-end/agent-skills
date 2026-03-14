publish-baseline:
	@scripts/publish-baseline.zsh
	@scripts/validate-nakomi-baseline.sh

setup-git-hooks:
	@scripts/setup-git-hooks.sh

.PHONY: publish-baseline setup-git-hooks
