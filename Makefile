LIFECYCLE := ./scripts/aws-profile-lifecycle.sh

PROFILE ?=
BUNDLE ?=
GITOPS_REVISION ?=
VOLUME_RECORD ?=
CONSENT ?=

.DEFAULT_GOAL := help

.PHONY: help check init status snapshot-volumes plan-up plan-down inspect apply-up apply-down
.PHONY: require-profile require-bundle require-gitops-revision require-volume-record

help:
	@printf '%s\n' \
		'MicroTodoSuite AWS profile lifecycle' \
		'' \
		'Profiles: PROFILE=economical|full (required)' \
		'' \
		'Read-only preparation:' \
		'  make check PROFILE=economical|full' \
		'  make init PROFILE=economical|full' \
		'  make status PROFILE=economical|full' \
		'' \
		'Saved-plan workflow:' \
		'  make plan-up PROFILE=economical|full' \
		'  make snapshot-volumes PROFILE=economical|full [CONSENT="<volume-id> ..."]' \
		'  make plan-down PROFILE=economical|full GITOPS_REVISION=<merged-commit> VOLUME_RECORD=<volume-record-directory>' \
		'  make inspect BUNDLE=<saved-plan-directory>' \
		'  make apply-up PROFILE=economical|full BUNDLE=<saved-plan-directory>' \
		'  make apply-down PROFILE=economical|full BUNDLE=<saved-plan-directory>' \
		'' \
		'Resource boundary: down removes runtime/ephemeral resources and preserves durable assets.' \
		'PersistentVolume data survives only as a snapshot taken by snapshot-volumes before GitOps quiescence.' \
		'Planning, inspection, and applying are always separate operations.'

require-profile:
	@case "$(PROFILE)" in \
		economical|full) ;; \
		*) printf 'ERROR: PROFILE must be economical or full.\n' >&2; exit 2 ;; \
	esac

require-bundle:
	@if [ -z "$(BUNDLE)" ]; then \
		printf 'ERROR: BUNDLE is required.\n' >&2; \
		exit 2; \
	fi

require-gitops-revision:
	@if [ -z "$(GITOPS_REVISION)" ]; then \
		printf 'ERROR: GITOPS_REVISION is required for plan-down.\n' >&2; \
		exit 2; \
	fi

require-volume-record:
	@if [ -z "$(VOLUME_RECORD)" ]; then \
		printf 'ERROR: VOLUME_RECORD is required for plan-down; run make snapshot-volumes before merging GitOps quiescence.\n' >&2; \
		exit 2; \
	fi

check: require-profile
	@$(LIFECYCLE) check $(PROFILE)

init: require-profile
	@$(LIFECYCLE) init $(PROFILE)

status: require-profile
	@$(LIFECYCLE) status $(PROFILE)

plan-up: require-profile
	@$(LIFECYCLE) plan $(PROFILE) up

snapshot-volumes: require-profile
	@$(strip $(LIFECYCLE) snapshot-volumes $(PROFILE) $(addprefix --consent ,$(CONSENT)))

plan-down: require-profile require-gitops-revision require-volume-record
	@$(LIFECYCLE) plan $(PROFILE) down --gitops-revision "$(GITOPS_REVISION)" --volume-record "$(VOLUME_RECORD)"

inspect: require-bundle
	@$(LIFECYCLE) inspect "$(BUNDLE)"

apply-up: require-profile require-bundle
	@$(LIFECYCLE) apply $(PROFILE) up "$(BUNDLE)"

apply-down: require-profile require-bundle
	@$(LIFECYCLE) apply $(PROFILE) down "$(BUNDLE)"
