#!/usr/bin/env bash

set -euxo pipefail

commit=$1

BUILDKITE_TOKEN=${BUILDKITE_TOKEN:-$BUILDKITE_AGENT_ACCESS_TOKEN}
BUILDKITE_ORGANIZATION_SLUG=${BUILDKITE_ORGANIZATION_SLUG:-tweag-1}
BUILDKITE_JOB_NAME=asterius-ghc-testsuite
ARTIFACT_FILENAME=${ARTIFACT_FILENAME:-test-report.csv}

BEARER_AUTH="Authorization: Bearer $BUILDKITE_TOKEN"
API_BASE="https://api.buildkite.com/v2/organizations/$BUILDKITE_ORGANIZATION_SLUG"

get_last_successful_build() {
    curl \
        -H "$BEARER_AUTH" \
        "$API_BASE/builds?commit=$commit" \
    | jq '.[0]'
}

get_artifacts() {
    last_build=$(mktemp)
    trap "rm -f $last_build" EXIT

    cat > "$last_build"

    job_id=$(< "$last_build" jq -r ".jobs[] | select(.name == \"$BUILDKITE_JOB_NAME\") | .id")
    build_number=$(< "$last_build" jq -r '.number')
    pipeline_slug=$(< "$last_build" jq -r '.pipeline.slug')

    curl \
        -H "$BEARER_AUTH" \
        "$API_BASE/pipelines/$pipeline_slug/builds/$build_number/jobs/$job_id/artifacts"
}

get_report_downloader_url() {
    jq "select(.[].filename == \"$ARTIFACT_FILENAME\") | .[0]" \
    | jq -r '.download_url'
}

download_download_url() {
    curl \
        -H "$BEARER_AUTH" \
        "$(cat)" \
    | jq -r '.url'
}

get_last_successful_build \
    | get_artifacts \
    | get_report_downloader_url \
    | download_download_url \
    | xargs -d'\n' curl
