#!/usr/bin/env bash

set -euo pipefail

# update-pins.sh ===============================================================
# What it does:
# - For each github-source plugin in a marketplace.json, finds the newest
#   `<plugin-name>--v<semver>` git tag in that plugin's own repo and re-pins the
#   entry's source.ref and source.sha to that tag and its commit.
# - Writes "changed=true|false" to $GITHUB_OUTPUT (or stdout when run locally)
#   so CI can decide whether to open a pull request.
#
# Requirements:
#   - jq
#   - git (with network access to the plugin repos)

## Help ========================================================================

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
Re-pin each github-source plugin in a marketplace catalog to its latest release tag.

Usage: update-pins.sh [MANIFEST]

Arguments:
  MANIFEST   Path to marketplace.json (default: .claude-plugin/marketplace.json)

Options:
  -h, --help   Show this help message and exit

Example:
  update-pins.sh .claude-plugin/marketplace.json
HELP
    exit 0
fi

## Configuration ===============================================================

# Never block on a credential prompt; a missing or private repo should fail fast.
export GIT_TERMINAL_PROMPT=0

MANIFEST="${1:-.claude-plugin/marketplace.json}"

if [ ! -f "${MANIFEST}" ]; then
    echo "Error: marketplace manifest not found: ${MANIFEST}" >&2
    exit 2
fi

## Script ======================================================================

WORKING="$(mktemp)"
cp "${MANIFEST}" "${WORKING}"

PLUGIN_COUNT="$(jq '.plugins | length' "${MANIFEST}")"
echo "Scanning ${PLUGIN_COUNT} plugin(s) in ${MANIFEST}"

INDEX=0
while [ "${INDEX}" -lt "${PLUGIN_COUNT}" ]; do
    SOURCE_TYPE="$(jq -r ".plugins[${INDEX}].source.source // empty" "${MANIFEST}")"

    # Only github-source entries are auto-pinned; leave path/url/npm entries alone.
    if [ "${SOURCE_TYPE}" != "github" ]; then
        INDEX=$((INDEX + 1))
        continue
    fi

    NAME="$(jq -r ".plugins[${INDEX}].name" "${MANIFEST}")"
    REPO="$(jq -r ".plugins[${INDEX}].source.repo" "${MANIFEST}")"

    echo "Checking ${NAME} (${REPO}) for ${NAME}--v* tags"
    TAGS="$(git ls-remote --tags "https://github.com/${REPO}.git" || true)"

    if [ -z "${TAGS}" ]; then
        echo "  no tags reachable in ${REPO}, leaving pin unchanged"
        INDEX=$((INDEX + 1))
        continue
    fi

    # Highest semver tag: drop peeled ^{} suffix, keep only <name>--vX.Y.Z, version-sort.
    LATEST_TAG="$(printf '%s\n' "${TAGS}" \
        | awk '{print $2}' \
        | sed -e 's#refs/tags/##' -e 's#\^{}$##' \
        | grep -E "^${NAME}--v[0-9]+\.[0-9]+\.[0-9]+$" \
        | sort -V \
        | tail -n1 || true)"

    if [ -z "${LATEST_TAG}" ]; then
        echo "  no ${NAME}--v<semver> tag found, leaving pin unchanged"
        INDEX=$((INDEX + 1))
        continue
    fi

    # Commit SHA: prefer the peeled ^{} line (annotated tags), else the tag line.
    SHA="$(printf '%s\n' "${TAGS}" | awk -v ref="refs/tags/${LATEST_TAG}^{}" '$2 == ref {print $1}')"
    if [ -z "${SHA}" ]; then
        SHA="$(printf '%s\n' "${TAGS}" | awk -v ref="refs/tags/${LATEST_TAG}" '$2 == ref {print $1}')"
    fi

    echo "  pinning ${NAME} -> ref=${LATEST_TAG} sha=${SHA}"
    jq --argjson i "${INDEX}" --arg ref "${LATEST_TAG}" --arg sha "${SHA}" \
        '.plugins[$i].source.ref = $ref | .plugins[$i].source.sha = $sha' \
        "${WORKING}" > "${WORKING}.next"
    mv "${WORKING}.next" "${WORKING}"

    INDEX=$((INDEX + 1))
done

## Result ======================================================================

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

if diff -q "${MANIFEST}" "${WORKING}" >/dev/null; then
    echo "No pin changes."
    echo "changed=false" >> "${OUTPUT_FILE}"
    rm -f "${WORKING}"
else
    echo "Pins updated in ${MANIFEST}."
    mv "${WORKING}" "${MANIFEST}"
    echo "changed=true" >> "${OUTPUT_FILE}"
fi
