# CLI & Make Commands Reference

## 1. Quick Reference

**ONLY READ WHEN:** Need detailed command syntax or examples beyond `--help`.

Complete reference for `make` targets and CLI commands.

**IMPORTANT:** Verify targets exist before use. Run `make help` or check the Makefile.

---

## 2. Make Targets

**Note:** These are suggested conventions. Not all projects implement all targets. Always verify with `make help` or `grep -E '^[a-zA-Z_-]+:' Makefile` before using.

### Common Targets (verify availability)
```bash
make install              # Install deps with uv, setup pre-commit hooks
make test                 # Run tests
make lint                 # Run all pre-commit checks
make help                 # List available targets (if implemented)
```

### If target doesn't exist
- Check Makefile directly: `head -50 Makefile`
- Run underlying command: `uv run pytest` instead of `make test`
- Add missing target to Makefile if appropriate

### [Project-specific targets]
```bash
# Document actual project targets here after verification
```

---

## 3. CLI Commands

All commands run with `uv run [command]`.

### [Command Group 1]

```bash
# Add CLI commands here
uv run [app] --help       # Show available commands
```

### [Command Group 2]

```bash
# Add more CLI commands
```
