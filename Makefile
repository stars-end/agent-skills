publish-baseline:
	@scripts/publish-baseline.zsh
	@scripts/validate-nakomi-baseline.sh

check-derived-freshness:
	@bash scripts/check-derived-freshness.sh

setup-git-hooks:
	@scripts/setup-git-hooks.sh

.PHONY: publish-baseline check-derived-freshness setup-git-hooks
