# Contributing

## Code of Conduct

We are committed to providing a friendly, safe and welcoming environment for all. See the [Code of Conduct](https://github.com/roc-lang/roc/blob/main/CODE_OF_CONDUCT.md) for details.

## How to update the Roc version

This project uses pre-built Roc nightly releases. To update to a new nightly:

1. Find the desired nightly at https://github.com/roc-lang/nightlies/releases
2. Update both values in `Cargo.toml`:
   - The `# roc-nightly: YYYY-MM-DD` comment (date must match the nightly release)
   - The `roc_std_new` rev (full 40-char commit hash, first 7 chars must match the nightly)
3. Run `ci/all_tests.sh` to verify the new version works

## How to generate docs?

TODO describe how to generate docs once `roc docs` is implemented in the new compiler
