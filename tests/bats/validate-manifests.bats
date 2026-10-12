#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  VALIDATE="${REPO_ROOT}/scripts/validate-lab-manifests.sh"
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
  cp "${REPO_ROOT}/.devcontainer/devcontainer.json" "${FIXTURE_ROOT}/.devcontainer/"
  mkdir -p "${FIXTURE_ROOT}/.github"
  cp "${REPO_ROOT}/.github/dependabot.yml" "${FIXTURE_ROOT}/.github/"
}

@test "validate-lab-manifests passes on the repository" {
  run env LAB_REPO_ROOT="${REPO_ROOT}" bash "${VALIDATE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lab manifest validation OK"* ]]
}

@test "validate-lab-manifests fails when workspaceFolder is wrong" {
  copy_lab_fixture
  sed -i 's|/workspaces/|/work/|' "${FIXTURE_ROOT}/.devcontainer/devcontainer.json"
  run env LAB_REPO_ROOT="${FIXTURE_ROOT}" bash "${VALIDATE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"workspaceFolder"* ]]
}

@test "validate-lab-manifests fails when a Talos service is missing" {
  copy_lab_fixture
  sed -i '/^  talos-worker:/,$d' "${FIXTURE_ROOT}/compose.yaml"
  run env LAB_REPO_ROOT="${FIXTURE_ROOT}" bash "${VALIDATE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing service"* ]]
}
