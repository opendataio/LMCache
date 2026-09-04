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
PYTEST_OUTPUT=$(mktemp)

# --- MOCK FAILURE (remove before production) ---
cat > "${PYTEST_OUTPUT}" << 'MOCK'
FAILED tests/v1/test_kv_cache_manager.py::test_allocate_block_out_of_memory
FAILED tests/v1/test_kv_cache_manager.py::test_free_unallocated_block
short test summary info
FAILED tests/v1/test_kv_cache_manager.py::test_allocate_block_out_of_memory - AssertionError: expected KVCacheManager to raise RuntimeError but got None
FAILED tests/v1/test_kv_cache_manager.py::test_free_unallocated_block - ValueError: block 42 is not allocated
2 failed, 38 passed in 12.34s
MOCK
TEST_STATUS="failed"
# --- END MOCK ---

END=$(date +%s)
DURATION=$(( END - START ))

# Collect failed test names and first error summary (max 5 lines)
FAILED_TESTS=$(grep -E "^FAILED " "${PYTEST_OUTPUT}" | head -5 | sed 's/FAILED //' || true)
ERROR_SUMMARY=$(grep -A3 "^FAILED\|^ERROR\|short test summary" "${PYTEST_OUTPUT}" | head -10 | tr '\n' ' ' | sed 's/"/\\"/g' || true)
rm -f "${PYTEST_OUTPUT}"

python3 - << PYEOF
import json
data = {
    "capability":       "${CAPABILITY}",
    "workload":         "smoke",
    "commit":           "${COMMIT}",
    "status":           "${TEST_STATUS}",
    "duration_seconds": ${DURATION},
    "failed_tests":     """${FAILED_TESTS}""".strip().splitlines(),
    "error_summary":    """${ERROR_SUMMARY}""".strip(),
}
with open("result.json", "w") as f:
    json.dump(data, f, indent=2)
PYEOF

echo ""
echo "Result:"
cat result.json

[[ "${TEST_STATUS}" == "passed" ]] && exit 0 || exit 1
