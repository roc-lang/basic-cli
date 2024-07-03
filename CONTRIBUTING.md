# Contributing

## Code of Conduct

We are committed to providing a friendly, safe and welcoming environment for all. See the [Code of Conduct](https://github.com/roc-lang/roc/blob/main/CODE_OF_CONDUCT.md) for details.

## How to generate docs?

You can generate the documentation locally and then start a web server to host your files.

```bash
roc docs platform/main.roc
cd generated-docs
simple-http-server --nocache --index # comes pre-installed if you use `nix develop`, otherwise use `cargo install simple-http-server`.
```

Open http://0.0.0.0:8000 in your browser
