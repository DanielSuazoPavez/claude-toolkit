---
name: naming-analyzer
description: Analyze and suggest better variable, function, and class names based on context and conventions. Use when reviewing code for clarity, checking naming consistency, or improving readability.
---

# Naming Analyzer

Suggest better names based on context and conventions.

## Analysis Workflow

### Step 1: Gather Scope
```bash
# List all symbols in a file
grep -E "^(def |class |[A-Z_]+ =)" src/module.py

# Find all function definitions
grep -rn "def " src/ --include="*.py"
```

### Step 2: Categorize Issues
Run through each name asking:
1. **What does it do?** → If you can't tell, it's unclear
2. **Is it honest?** → Does behavior match name?
3. **Is it consistent?** → Same pattern as similar names?

### Step 3: Prioritize Fixes
| Severity | Criteria | Example |
|----------|----------|---------|
| Critical | Misleading - name lies | `get_x()` that mutates |
| Major | Unclear in large scope | `d` for date in 100-line function |
| Minor | Convention violation | `active` instead of `is_active` |

### Step 4: Report
Generate report grouped by severity, with:
- Location (file:line)
- Current name
- Issue description
- Suggested name

## What to Analyze

- Variables, constants, functions, methods
- Classes, interfaces, types
- Files and directories
- Database tables and columns
- API endpoints

## Issues to Identify

- Unclear or vague names
- Abbreviations that obscure meaning
- Inconsistent conventions
- Misleading names (doesn't match behavior)
- Too short or too long

## Conventions by Language

### Python
```python
# Variables/functions: snake_case
user_count = get_active_users()

# Classes: PascalCase
class UserService:

# Constants: UPPER_SNAKE_CASE
MAX_RETRY_ATTEMPTS = 3

# Boolean: is_, has_, can_ prefixes
is_active = True
```

### JavaScript/TypeScript
```javascript
// Variables/functions: camelCase
const userCount = getActiveUsers();

// Classes: PascalCase
class UserService {}

// Constants: UPPER_SNAKE_CASE
const MAX_RETRY_ATTEMPTS = 3;

// Boolean: is, has, can prefixes
const isActive = true;
```

## Common Problems

### Too Vague
```python
# Bad
def process(data): pass
info = get_data()

# Good
def process_payment(transaction): pass
user_profile = get_user_profile()
```

### Misleading
```python
# Bad - has side effects but name implies read-only
def get_user(id):
    user = fetch_user(id)
    user.last_login = datetime.now()
    save_user(user)
    return user

# Good
def fetch_and_update_user_login(id):
    ...
```

### Abbreviations
```python
# Bad
usr_cfg = load_config()

# Good
user_config = load_config()

# Acceptable (well-known)
html_element = document.get_element()
api_url = config.API_URL
```

### Booleans
```python
# Bad
login = user.authenticated
status = check_user()

# Good
is_logged_in = user.authenticated
is_user_valid = check_user()
has_permission = 'admin' in user.roles
can_edit_post = is_owner or is_admin
```

## Report Format

```markdown
## Critical (Misleading)
- `get_user()` at src/services.py:45
  - Issue: Has side effects but name implies read-only
  - Suggest: `fetch_and_update_user_login()`

## Major (Unclear)
- `d` at src/utils.py:12
  - Issue: Single-letter in large scope
  - Suggest: `current_date`

## Minor (Convention)
- `active` at src/models.py:34
  - Issue: Boolean without prefix
  - Suggest: `is_active`
```

## Naming Decision Tree

```
Is it a boolean?
├─ Yes → Use is/has/can/should prefix
└─ No → Is it a function?
    ├─ Yes → Use verb phrase
    └─ No → Is it a class?
        ├─ Yes → Use noun (PascalCase)
        └─ No → Is it a constant?
            ├─ Yes → UPPER_SNAKE_CASE
            └─ No → Descriptive noun
```

## Best Practices

- Clarity over brevity
- Full words over abbreviations (except well-known: api, url, id)
- Consistency within project > perfect naming
- Refactor names as understanding improves

## Refactoring Checklist

When renaming:
1. **Find all usages**: `grep -rn "old_name" src/ tests/`
2. **Update tests**: Test files often have matching names
3. **Update docs**: README, docstrings, comments
4. **Update imports**: Check all `from X import old_name`
5. **Commit separately**: Rename PR should be isolated from logic changes
