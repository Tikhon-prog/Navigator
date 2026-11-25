#!/usr/bin/env bash
# Удаляет на GitHub ветки, которые уже влиты в main, заменены или были одноразовыми
# (CI-проверки). Коммиты закрытых PR остаются доступны через refs/pull/<N>/head.
# Запуск: bash tool/delete_old_branches.sh
set -u
BRANCHES=(
  fix/ci-rbac-test-db-init
  fix/0.2.2-release-readiness
  integration/q2-8v-grade10
  work/docker-dev-environment
  feature/pokolenie-school-hardening
  fix/8v-afternoon-lessons-main
  fix/backend-test-rbac-init
  fix/flutter-analyzer-warnings-main
  fix/info-local-ai-2026-11
  fix/ios-build-without-signing
  security/detect-yandex-oauth-tokens
  fix/8v-afternoon-lessons
  fix/flutter-analyzer-warnings
  feature/q2-8v-and-grade10-dop-profile
  feature/q2-8v-grade10-profile-main-sync
  feature/school-server-rbac-firebase
  feat/school-integration-server
  ai-navigation-study-hub
  ci/verify-navigator
  ci/verify-navigator-2
  ci/verify-navigator-3
  ci/verify-navigator-4
  ci/verify-navigator-5
  ci/verify-navigator-6
  ci/verify-navigator-7
  dependabot/github_actions/actions/checkout-7
  dependabot/github_actions/actions/setup-python-6
  dependabot/github_actions/actions/upload-artifact-7
)
for b in "${BRANCHES[@]}"; do
  git push origin --delete "$b" || echo "Пропущено: $b"
done
