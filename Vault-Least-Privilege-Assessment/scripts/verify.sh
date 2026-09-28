#!/usr/bin/env bash

set -u

echo "========================================"
echo " Vault Least-Privilege Verification"
echo "========================================"
echo

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local expected="$2"
    shift 2

    echo -n "[TEST] $name ... "

    output=$("$@" 2>&1)
    status=$?

    if [ "$expected" = "success" ] && [ "$status" -eq 0 ]; then
        echo "PASS"
        PASS=$((PASS + 1))

    elif [ "$expected" = "denied" ] && [ "$status" -ne 0 ] && \
         echo "$output" | grep -qi "permission denied"; then
        echo "PASS"
        PASS=$((PASS + 1))

    else
        echo "FAIL"
        echo "$output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Secret Access Tests ==="
echo

run_test \
    "Read demo-a" \
    "success" \
    vault kv get -mount=secret demo-a

run_test \
    "Read demo-b is denied" \
    "denied" \
    vault kv get -mount=secret demo-b

run_test \
    "Update demo-a is denied" \
    "denied" \
    vault kv put -mount=secret demo-a value=dummy-updated

run_test \
    "Update demo-b is denied" \
    "denied" \
    vault kv put -mount=secret demo-b value=dummy-updated

echo
echo "=== ACL Policy Administration Tests ==="
echo

run_test \
    "List ACL policies is denied" \
    "denied" \
    vault policy list

run_test \
    "Read existing ACL policy is denied" \
    "denied" \
    vault policy read assessment-existing

run_test \
    "Create ACL policy is denied" \
    "denied" \
    bash -c 'vault policy write assessment-new - <<EOF
path "secret/data/test" {
  capabilities = ["read"]
}
EOF'

run_test \
    "Update ACL policy is denied" \
    "denied" \
    bash -c 'vault policy write assessment-existing - <<EOF
path "secret/data/test-updated" {
  capabilities = ["read"]
}
EOF'

run_test \
    "Delete ACL policy is denied" \
    "denied" \
    vault policy delete assessment-existing

echo
echo "========================================"
echo " Results"
echo "========================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
