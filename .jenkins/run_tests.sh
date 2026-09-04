#!/usr/bin/env bash
# Test entry point called by Jenkinsfile.test.
# Writes result.json in the result contract format when done.
#
# Exit code:
#   0  all tests passed
#   1  one or more tests failed

set -euo pipefail

START=$(date +%s)
COMMIT=$(git rev-parse HEAD)
CAPABILITY="${RBLN_CAPABILITY:-rbln-demo}"

echo "============================================"
echo " LMCache RBLN test run"
echo " Commit   : ${COMMIT}"
echo " Capability: ${CAPABILITY}"
echo " Started  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"

TEST_STATUS="passed"

if python3 -m pytest tests/ \
       -x -q \
       --timeout=120 \
       -m "not gpu" \
       --tb=short 2>&1; then
    TEST_STATUS="passed"
else
    TEST_STATUS="failed"
fi

END=$(date +%s)
DURATION=$(( END - START ))

cat > result.json << EOF
{
  "capability":       "${CAPABILITY}",
  "workload":         "smoke",
  "commit":           "${COMMIT}",
  "status":           "${TEST_STATUS}",
  "duration_seconds": ${DURATION}
}
EOF

echo ""
echo "Result:"
cat result.json

[[ "${TEST_STATUS}" == "passed" ]] && exit 0 || exit 1
