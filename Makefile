LIFECYCLE := ./scripts/aws-profile-lifecycle.sh

PROFILE ?=
BUNDLE ?=
RECEIPT ?=
VOLUME_RECORD ?=
CONSENT ?=

.DEFAULT_GOAL := help

.PHONY: help check init status snapshot-volumes quiescence-receipt plan-up plan-down inspect apply-up apply-down
.PHONY: require-profile require-bundle require-quiescence-receipt require-volume-record

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
		'  make quiescence-receipt PROFILE=economical|full VOLUME_RECORD=<volume-record-directory>' \
		'  make plan-down PROFILE=economical|full RECEIPT=<quiescence-receipt-directory> VOLUME_RECORD=<volume-record-directory>' \
		'  make inspect BUNDLE=<saved-plan-directory>' \
		'  make apply-up PROFILE=economical|full BUNDLE=<saved-plan-directory>' \
		'  make apply-down PROFILE=economical|full BUNDLE=<saved-plan-directory>' \
		'' \
		'Resource boundary: down removes runtime/ephemeral resources and preserves durable assets.' \
		'PersistentVolume data survives only as a snapshot taken by snapshot-volumes before the quiescence receipt.' \
		'During a down apply, a post-destroy runtime sweep removes controller runtime resources' \
		'between the cluster destruction and the first networking apply.' \
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

require-quiescence-receipt:
	@if [ -z "$(RECEIPT)" ]; then \
		printf 'ERROR: RECEIPT is required for plan-down; run make quiescence-receipt first.\n' >&2; \
		exit 2; \
	fi

require-volume-record:
	@if [ -z "$(VOLUME_RECORD)" ]; then \
		printf 'ERROR: VOLUME_RECORD is required for plan-down; run make snapshot-volumes before make quiescence-receipt.\n' >&2; \
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

quiescence-receipt: require-profile require-volume-record
	@$(LIFECYCLE) quiescence-receipt $(PROFILE) --volume-record "$(VOLUME_RECORD)"

plan-down: require-profile require-quiescence-receipt require-volume-record
	@$(LIFECYCLE) plan $(PROFILE) down --receipt "$(RECEIPT)" --volume-record "$(VOLUME_RECORD)"

inspect: require-bundle
	@$(LIFECYCLE) inspect "$(BUNDLE)"

apply-up: require-profile require-bundle
	@$(LIFECYCLE) apply $(PROFILE) up "$(BUNDLE)"

apply-down: require-profile require-bundle
	@$(LIFECYCLE) apply $(PROFILE) down "$(BUNDLE)"
