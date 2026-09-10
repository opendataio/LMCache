#!/usr/bin/env bash
# Test entry point called by Jenkinsfile.test (MetaX MACA variant).
# Writes result.json in the result contract format when done.
#
# The pytest exclusion list below mirrors the one already verified on the
# MACA Buildkite lane (.buildkite/metax/run-unit-tests.sh, see
# LMCache/LMCache#4949) instead of re-discovering the same MACA capability
# gaps independently. Keep the two lists in sync if either changes.
#
# Exit code:
#   0  all tests passed
#   1  one or more tests failed

set -euo pipefail

START=$(date +%s)
COMMIT=$(git rev-parse HEAD)
CAPABILITY="${MACA_CAPABILITY:-maca-demo}"

echo "============================================"
echo " LMCache MACA test run"
echo " Commit   : ${COMMIT}"
echo " Capability: ${CAPABILITY}"
echo " Started  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"

echo "--- environment ---"
echo "MACA_PATH=${MACA_PATH:-<unset>}"
which python3; python3 --version
which pip
python3 -c "import torch; print('torch', torch.__version__, 'cuda available:', torch.cuda.is_available())" || true
echo "-------------------"

# MACA SDK env (cu-bridge nvcc-compatible compiler + runtime libs). Only
# fall back to /opt/maca if the image hasn't already set MACA_PATH.
export MACA_PATH="${MACA_PATH:-/opt/maca}"
export CUCC_PATH="${MACA_PATH}/tools/cu-bridge"
export PATH="${CUCC_PATH}/bin:${CUCC_PATH}/tools:${MACA_PATH}/mxgpu_llvm/bin:${MACA_PATH}/bin:${PATH}"
export LD_LIBRARY_PATH="${MACA_PATH}/lib:${MACA_PATH}/mxgpu_llvm/lib:${MACA_PATH}/ompi/lib:${LD_LIBRARY_PATH:-}"

# MetaX GPUs require this whenever multiple processes access the same GPU
# concurrently, which several tests in this suite do (matches the Buildkite
# lane's common-setup.sh).
export MACA_MPS_MODE=1

# This K8s pod can't reach some external hosts (github.com, huggingface.co)
# directly -- route through the internal proxy. The Buildkite bare-metal
# lane doesn't need this: that host already has a system-wide proxy.
export http_proxy=http://192.168.2.103:31080
export https_proxy=http://192.168.2.103:31080

pip install -r requirements/common.txt
pip install -r requirements/test.txt
pip install pytest-timeout pytest-asyncio pytest-benchmark

# Compile & install LMCache itself with MACA support, against the
# already-installed torch/MACA toolchain baked into this image.
BUILD_WITH_MACA=1 pip install -e . --no-build-isolation

TEST_STATUS="passed"
PYTEST_OUTPUT=$(mktemp)

# Exclusion list mirrors .buildkite/metax/run-unit-tests.sh (LMCache/LMCache#4949)
# -- see that file's inline comments for the evidence behind each entry
# (Triton FP8 gap, NVIDIA-only cuda.bindings dependency, single-GPU-host
# flake, torch_ops scenarios).
if LMCACHE_TRACK_USAGE="false" python3 -m pytest \
       --timeout=120 \
       --tb=short \
       --ignore=tests/disagg --ignore=tests/v1/test_pos_kernels.py \
       --ignore=tests/v1/test_nixl_batched_contains.py \
       --ignore=tests/v1/test_device_id_race.py \
       --ignore=tests/v1/test_nixl_multipath.py \
       --ignore=tests/skipped \
       --ignore=tests/v1/storage_backend/test_eic.py \
       --deselect="tests/v1/distributed/serde/test_turboquant.py::test_turboquant_direct_roundtrip_cuda[turboquant_k8v4-2.6-0.95]" \
       --ignore=tests/v1/mp_coordinator/test_instances_usage_e2e.py \
       --ignore=tests/v1/platform/test_cuda_ipc_wrapper.py \
       --ignore=tests/v1/platform/test_timeline_semaphore_event_ipc.py \
       --ignore=tests/v1/multiprocess/test_mq.py \
       --ignore=tests/v1/multiprocess/test_cb_plan_executor_gpu.py \
       --ignore=tests/v1/multiprocess/test_custom_types.py \
       --ignore=tests/v1/multiprocess/test_engine_driven_transfer.py \
       --ignore=tests/v1/multiprocess/test_free_locks.py \
       --ignore=tests/v1/multiprocess/test_query_lookup_hits.py \
       --deselect="tests/cli/commands/bench/test_server_bench.py::TestUnregisterKVCache::test_data_mode_sends_engine_driven_unregister" \
       --deselect="tests/v1/mp_coordinator/test_key_directory.py::test_token_ids_outside_uint32_leave_the_binding_unfilled" \
       --deselect="tests/v1/test_torch_ops.py::TestScenarios::test_1_scenario[cuda_ops-load_and_reshape_flash-scenario_load_and_reshape_flash]" \
       --deselect="tests/v1/test_torch_ops.py::TestScenarios::test_2_compare[multi_layer_block_kv_transfer]" \
       --deselect="tests/v1/distributed/l2_adapters/test_p2p_l2_adapter_integration.py::test_p2p_adapter_end_to_end" \
       2>&1 | tee "${PYTEST_OUTPUT}"; then
    TEST_STATUS="passed"
else
    TEST_STATUS="failed"
fi

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
