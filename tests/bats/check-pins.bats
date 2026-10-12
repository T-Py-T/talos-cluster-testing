#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CHECK_PINS="${REPO_ROOT}/scripts/check-pins.sh"
  FIXTURE_ROOT=""
}

teardown() {
  if [[ -n "${FIXTURE_ROOT}" && -d "${FIXTURE_ROOT}" ]]; then
    rm -rf "${FIXTURE_ROOT}"
  fi
}

copy_lab_fixture() {
  FIXTURE_ROOT="$(mktemp -d)"
  cp "${REPO_ROOT}/lab-versions.env" "${FIXTURE_ROOT}/"
  cp "${REPO_ROOT}/compose.yaml" "${FIXTURE_ROOT}/"
  mkdir -p "${FIXTURE_ROOT}/.devcontainer"
  cp "${REPO_ROOT}/.devcontainer/setup.sh" "${FIXTURE_ROOT}/.devcontainer/"
}

@test "check-pins passes on the repository" {
  run env LAB_REPO_ROOT="${REPO_ROOT}" bash "${CHECK_PINS}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pin check OK"* ]]
}

@test "check-pins fails when compose anchor disagrees with lab-versions.env" {
  copy_lab_fixture
  sed -i 's/v1.13.11/v9.9.9/' "${FIXTURE_ROOT}/compose.yaml"
  run env LAB_REPO_ROOT="${FIXTURE_ROOT}" bash "${CHECK_PINS}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"anchor does not match"* ]]
}

@test "check-pins fails when setup.sh does not source lab-versions.env" {
  copy_lab_fixture
  sed -i '/lab-versions.env/d' "${FIXTURE_ROOT}/.devcontainer/setup.sh"
  run env LAB_REPO_ROOT="${FIXTURE_ROOT}" bash "${CHECK_PINS}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must source lab-versions.env"* ]]
}

@test "check-pins fails on invalid TALOS_VERSION format" {
  copy_lab_fixture
  echo 'TALOS_VERSION=not-a-version' >"${FIXTURE_ROOT}/lab-versions.env"
  run env LAB_REPO_ROOT="${FIXTURE_ROOT}" bash "${CHECK_PINS}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vMAJOR.MINOR.PATCH"* ]]
}
