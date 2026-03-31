# Contributing to daraja

## Branching

| Branch | Purpose |
|---|---|
| `main` | Stable releases only — tagged and versioned |
| `develop` | Integration — all features land here |
| `feat/<name>` | Feature work — branched from `develop` |
| `fix/<name>` | Bug fixes — branched from `develop` |
| `release/<version>` | Release prep — branched from `develop`, merges to `main` |

## Workflow

```
git checkout develop
git pull origin develop
git checkout -b feat/your-feature
# work
git push origin feat/your-feature
# open PR → develop
```

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org):

```
feat: add phone normalisation to DarajaClient
fix: correct EAT offset in password generation
test: add timeout cascade integration tests
docs: update function deployment guide
refactor: extract polling logic into separate method
chore: bump appwrite to 23.1.0
```

- Imperative mood, lowercase, no period
- Reference an issue if one exists: `feat: add STK Query fallback (#12)`

## Code rules

- No emojis
- No commented-out code
- No unnecessary comments — only comment non-obvious constraints or external API quirks
- No defensive code for impossible scenarios
- No stubs, placeholders, or TODO scaffolding committed to `develop` or `main`
