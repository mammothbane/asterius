#!/usr/bin/env bash

set -euxo pipefail

commit=$1

BUILDKITE_TOKEN=${BUILDKITE_TOKEN:-$BUILDKITE_AGENT_ACCESS_TOKEN}
BUILDKITE_ORGANIZATION_SLUG=${ORG:-tweag-1}
BUILDKITE_JOB_NAME=asterius-ghc-testsuite
ARTIFACT_FILENAME=${ARTIFACT_FILENAME:-test-report.csv}

BEARER_AUTH="Authorization: Bearer $BUILDKITE_TOKEN"
API_BASE="https://api.buildkite.com/v2/organizations/$ORG"

get_last_successful_build() {
    curl \
        -H "$BEARER_AUTH" \
        "$API_BASE/builds?commit=$commit&state=passed" \
    jq '.[0]'
}

get_last_successful_build() {
    cat builds.json
}

get_artifacts() {
    last_build=$(cat)

    job_id=$(jq -r --args ".jobs[] | select(.name == \"$BUILDKITE_JOB_NAME\") | .id" "$last_build")
    build_number=$(jq -r --args '.number' "$last_build")
    pipeline_slug=$(jq -r --args '.pipeline.slug' "$last_build")

    curl \
        -H "$BEARER_AUTH" \
        "$API_BASE/pipelines/$pipeline_slug/builds/$build_number/jobs/$job_id/artifacts"
}

get_download_url() {
    target_url=$(jq '.download_url')

    curl \
        -H "$BEARER_AUTH" \
        "$target_url" \
    | jq '.url'
}

get_last_successful_build \
    | get_artifacts \
    | jq "select(.filename == \"$ARTIFACT_FILENAME\") | .[0]" \
    | get_download_url \
    | xargs -d'\n' curl
