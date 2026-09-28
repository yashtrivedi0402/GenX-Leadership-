# Vault Least-Privilege Assessment

## 1. Objective

This assessment demonstrates how to correct an overly broad HashiCorp Vault access policy and replace it with a least-privilege policy.

The deployment job should be able to:

- Read the `demo-a` secret.
- Have no access to `demo-b`.
- Not create or update secrets.
- Not administer Vault ACL policies.

The Vault development server is used for this assessment. The development server uses in-memory storage, so all data is disposable and is lost when the server is stopped.

---

## 2. Environment

- HashiCorp Vault
- Vault version: `2.0.0`
- Vault development server
- KV Version 2 secrets engine
- Vault address: `http://127.0.0.1:8200`
- Ubuntu 22.04.5 LTS on WSL2

The development server automatically provides the `secret/` KV v2 secrets engine.

The mount was verified using:

```bash
vault secrets list -detailed
```

The `secret/` mount was confirmed as KV Version 2.

---

## 3. Original Policy

The inherited policy was:

```hcl
path "secret/data/*" {
  capabilities = ["read", "update"]
}
```

This policy is broader than required.

### Problems with the original policy

The policy:

1. Allows access to multiple secrets under `secret/data/*`.
2. Allows reading secrets other than `demo-a`.
3. Allows updating existing secrets.
4. Does not follow the principle of least privilege.

The deployment job only needs read access to one specific secret, so access to the entire `secret/data/*` path is unnecessary.

---

## 4. Corrected Least-Privilege Policy

The broad policy was replaced with the following policy:

```hcl
path "secret/data/demo-a" {
  capabilities = ["read"]
}
```

The policy is stored in:

```text
policy/demo-a-reader.hcl
```

### Why this policy is sufficient

The deployment job requires only one operation:

```text
Read demo-a
```

Therefore:

- The path is restricted to `secret/data/demo-a`.
- Only the `read` capability is granted.
- No create, update, delete, or list capabilities are granted.
- Other secret paths are outside the policy.

This provides the required access without granting unnecessary permissions.

---

## 5. Vault Setup

Start a fresh Vault development server:

```bash
vault server -dev
```

Set the Vault address:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
```

The development server was verified using:

```bash
vault status
```

Example environment information:

```text
Initialized: true
Sealed:     false
Version:    2.0.0
Storage:    inmem
```

The `secret/` mount was verified as KV Version 2.

The root/dev token is used only for environment preparation and policy/secret setup. It is not used for the evaluated permission checks.

---

## 6. Installing the Policy

The least-privilege policy was installed using the root token:

```bash
vault policy write demo-a-reader policy/demo-a-reader.hcl
```

The installed policy was verified with:

```bash
vault policy read demo-a-reader
```

Expected policy:

```hcl
path "secret/data/demo-a" {
  capabilities = ["read"]
}
```

---

## 7. Restricted Token

A restricted token was created using:

```bash
vault token create -policy=demo-a-reader -no-default-policy
```

The token configuration was verified to ensure that the assigned policy is:

```text
demo-a-reader
```

and that no default policy was attached.

> The actual token value is intentionally not included in this repository.
>
> Never commit Vault tokens, root tokens, or real secret values to the repository.

---

## 8. Test Data

Two test paths are used:

```text
secret/demo-a
secret/demo-b
```

Dummy values were used for testing.

No real credentials or sensitive production values are used in this assessment.

---

## 9. Permission Verification

The permission checks were performed using the restricted token.

The root token was not used for evaluated permission checks.

### 9.1 Creation Denial Tests

Before either secret existed, attempts were made to create:

```text
secret/demo-a
secret/demo-b
```

using the restricted token.

**Both creation attempts were denied.**

This confirms that the restricted token does not have the create capability.

This absent-path phase is important because a create operation cannot be inferred only from update-denial tests on already-existing KV v2 secrets.

### 9.2 Secret Access Tests

After the test secrets were created using the root token, the restricted token was used for the following checks.

**Read demo-a**

Command:

```bash
vault kv get -mount=secret demo-a
```

Result: **PASS**

The restricted token can read `demo-a` as required.

**Read demo-b**

Command:

```bash
vault kv get -mount=secret demo-b
```

Result: `Permission denied`

Result: **PASS**

The restricted token cannot read `demo-b`.

**Update demo-a**

Command:

```bash
vault kv put -mount=secret demo-a value=dummy-updated
```

Result: `Permission denied`

Result: **PASS**

The restricted token cannot update `demo-a`.

**Update demo-b**

Command:

```bash
vault kv put -mount=secret demo-b value=dummy-updated
```

Result: `Permission denied`

Result: **PASS**

The restricted token cannot update `demo-b`.

---

## 10. ACL Policy Administration Tests

The restricted token was also tested against Vault ACL policy administration operations.

A disposable ACL policy named:

```text
assessment-existing
```

was created using the root token.

Another policy:

```text
assessment-new
```

was intentionally left absent for the creation test.

The restricted token was tested against the following operations:

| Operation | Expected Result | Result |
|---|---|---|
| List ACL policies | Denied | PASS |
| Read existing ACL policy | Denied | PASS |
| Create new ACL policy | Denied | PASS |
| Update existing ACL policy | Denied | PASS |
| Delete existing ACL policy | Denied | PASS |

These checks confirm that the restricted token cannot administer Vault ACL policies.

---

## 11. Automated Verification

A repeatable verification script is provided at:

```text
scripts/verify.sh
```

Run it with:

```bash
./scripts/verify.sh
```

The script verifies:

```text
Read demo-a
Read demo-b is denied
Update demo-a is denied
Update demo-b is denied

List ACL policies is denied
Read existing ACL policy is denied
Create ACL policy is denied
Update ACL policy is denied
Delete ACL policy is denied
```

Final verification result:

```text
Passed: 9
Failed: 0

ALL TESTS PASSED
```

The absent-path creation-denial phase is performed separately against a fresh development server because the assessment requires those checks before the test secrets exist.

---

## 12. KV Version 2 Path Explanation

Vault KV Version 2 uses different paths depending on the interface being used.

For the `demo-a` secret:

CLI path:

```text
secret/demo-a
```

The corresponding policy/API data path is:

```text
secret/data/demo-a
```

Therefore, the policy correctly uses:

```hcl
path "secret/data/demo-a" {
  capabilities = ["read"]
}
```

while the CLI command uses:

```bash
vault kv get -mount=secret demo-a
```

The `data/` segment is part of the KV v2 API/policy path and should not be added to the CLI secret name when using the `vault kv` command.

---

## 13. Access Model

The effective permission can be understood as:

```text
Restricted Token
       |
       v
demo-a-reader policy
       |
       v
secret/data/demo-a
       |
       +---- read  -> ALLOWED
       |
       +---- update -> DENIED
       |
       +---- create -> DENIED
       |
       +---- delete -> DENIED
       |
       +---- demo-b -> DENIED
```

The token does not receive the default policy because it was created using:

```text
-no-default-policy
```

This keeps the evaluated token restricted to the intended policy.

---

## 14. Security Considerations

The following practices were followed during the assessment:

- No real credentials were used.
- Dummy secret values were used for testing.
- Root/dev tokens were used only for setup.
- The restricted token was used for permission checks.
- Actual token values are not included in the repository.
- Real secret values are not included in the repository.
- The least-privilege policy grants only the required read capability.
- The restricted token has no default policy.

---

## 15. Limitations

This assessment uses the Vault development server.

The development server:

- Uses in-memory storage.
- Is intended for testing/development.
- Loses its data when the server is stopped.
- Is not intended to represent a production Vault deployment.

Production hardening, TLS, Raft storage, audit devices, snapshots, AppRole configuration, and persistent Vault infrastructure are outside the scope of this assessment.

---

## 16. Evidence

Screenshots can be added here to document the verification.

Suggested evidence:

**Vault Status and KV v2 Mount**

Add screenshot showing:

```bash
vault status
vault secrets list -detailed
```

**Least-Privilege Policy**

Add screenshot showing:

```bash
vault policy read demo-a-reader
```

Do not include any token values.

**Restricted Token Policy Assignment**

Add screenshot showing only the assigned policy names.

Do not expose the actual token.

**Secret Permission Checks**

Add screenshot showing:

- `demo-a` read succeeds.
- `demo-b` read is denied.
- Updates are denied.

**Automated Verification**

Add screenshot showing:

```bash
./scripts/verify.sh
```

with:

```text
Passed: 9
Failed: 0

ALL TESTS PASSED
```

---

## 17. Repository Structure

```text
vault-least-privilege-assessment/
│
├── .gitignore
├── README.md
│
├── policy/
│   └── demo-a-reader.hcl
│
├── scripts/
│   └── verify.sh
│
└── evidence/
    └── screenshots
```

---

## 18. Conclusion

The original Vault policy granted broader access than required:

```hcl
path "secret/data/*" {
  capabilities = ["read", "update"]
}
```

It was replaced with an exact-path, read-only policy:

```hcl
path "secret/data/demo-a" {
  capabilities = ["read"]
}
```

The restricted token was verified against secret access and ACL policy administration operations.

The automated verification completed with:

```text
Passed: 9
Failed: 0
```

The resulting configuration follows the least-privilege requirement for the deployment job while preventing access to unrelated secrets and administrative Vault ACL operations.
