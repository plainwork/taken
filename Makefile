.PHONY: changelog version minor major test

V ?=

changelog:
	@if [ -z "$(V)" ]; then \
		echo "V is required (e.g., make version V=0.0.2)"; \
		exit 1; \
	fi
	@last_tag=$$(git describe --tags --abbrev=0 2>/dev/null || true); \
	if [ -n "$$last_tag" ]; then \
		range="$$last_tag..HEAD"; \
	else \
		range="HEAD"; \
	fi; \
	commits=$$(git log --no-merges --pretty=format:"- %s (%h)" $$range); \
	if [ -z "$$commits" ]; then \
		commits="- No changes."; \
	fi; \
	date=$$(date +%Y-%m-%d); \
	tmp=$$(mktemp); \
	{ \
		echo "# Changelog"; \
		echo ""; \
		echo "## v$(V) - $$date"; \
		echo "$$commits"; \
		echo ""; \
		if [ -f CHANGELOG.md ]; then \
			awk 'NR==1 && $$0=="# Changelog"{next} NR==2 && $$0==""{next} {print}' CHANGELOG.md; \
		fi; \
	} > "$$tmp"; \
	mv "$$tmp" CHANGELOG.md

version: test
	@set -e; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "Working tree is dirty. Commit or stash changes before versioning."; \
		exit 1; \
	fi; \
	if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then \
		echo "No upstream configured. Set the upstream before versioning."; \
		exit 1; \
	fi; \
	if [ -n "$$(git log @{u}..HEAD --oneline)" ]; then \
		echo "Unpushed commits detected. Push before versioning."; \
		exit 1; \
	fi; \
	if [ -n "$$(git log HEAD..@{u} --oneline)" ]; then \
		echo "Remote has new commits. Pull before versioning."; \
		exit 1; \
	fi; \
	v="$(V)"; \
	current=$$(cat VERSION 2>/dev/null || echo "0.0.0"); \
	IFS=. read -r major minor patch <<<"$$current"; \
	major=$${major:-0}; \
	minor=$${minor:-0}; \
	patch=$${patch:-0}; \
	if [ -z "$$v" ]; then \
		patch=$$((patch + 1)); \
		v="$$major.$$minor.$$patch"; \
		read -r -p "Use patch version $$v? [Y/n] " confirm; \
		case "$$confirm" in \
			n|N|no|NO) \
				read -r -p "Pick bump type (major/minor/patch): " bump; \
				case "$$bump" in \
					major) major=$$((major + 1)); minor=0; patch=0 ;; \
					minor) minor=$$((minor + 1)); patch=0 ;; \
					patch|"") patch=$$((patch + 1)) ;; \
					*) echo "Unknown bump type: $$bump"; exit 1 ;; \
				esac; \
				v="$$major.$$minor.$$patch"; \
				read -r -p "Use version $$v? [Y/n] " confirm2; \
				case "$$confirm2" in \
					n|N|no|NO) echo "Cancelled."; exit 1 ;; \
				esac; \
				;; \
		esac; \
	fi; \
	$(MAKE) changelog V="$$v"; \
	echo "$$v" > VERSION; \
	git add CHANGELOG.md VERSION; \
	git commit -m "Release v$$v"; \
	git tag "v$$v"; \
	git push origin HEAD; \
	git push origin "v$$v"

minor:
	@current=$$(cat VERSION 2>/dev/null || echo "0.0.0"); \
	IFS=. read -r major minor patch <<<"$$current"; \
	major=$${major:-0}; \
	minor=$${minor:-0}; \
	minor=$$((minor + 1)); \
	patch=0; \
	v="$$major.$$minor.$$patch"; \
	$(MAKE) version V="$$v"

major:
	@current=$$(cat VERSION 2>/dev/null || echo "0.0.0"); \
	IFS=. read -r major minor patch <<<"$$current"; \
	major=$${major:-0}; \
	major=$$((major + 1)); \
	minor=0; \
	patch=0; \
	v="$$major.$$minor.$$patch"; \
	$(MAKE) version V="$$v"

test:
	@true
