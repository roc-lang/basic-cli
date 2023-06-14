# basic-cli

A basic [CLI](https://en.wikipedia.org/wiki/Command-line_interface) Roc Platform.

## Docs generation

You can generate the documentation locally and then start a web server to host your files.

```bash
roc docs src/main.roc
cd generated-docs
simple-http-server --nocache # You can install it with `cargo install simple-http-server`.
```

Open http://0.0.0.0:8000 in your browser.
