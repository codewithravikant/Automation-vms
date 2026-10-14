# CI sandbox (safe to edit)

Use this folder to **test the Git → Jenkins pipeline** without changing real app logic.

## How to test

From your **laptop**:

```bash
# 1) Add or change a file
echo "ping $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> test/ci-sandbox/TRIGGER.txt

# 2) Or delete a file you added earlier
# rm test/ci-sandbox/my-temp.txt

# 3) Commit + push (triggers webhook)
git add test/ci-sandbox/
git commit -m "ci-sandbox: trigger pipeline"
git push origin main
```

Then open Jenkins (tunnel): http://localhost:18080/job/alchemy-app/

Path routing treats `test/ci-sandbox/**` like **`app/`** → full app CI path (lint/build/deploy).

## Rules

- Only touch files under `test/ci-sandbox/`
- Do **not** put secrets here
- Deleting files under this folder also counts as a change (after commit + push)
