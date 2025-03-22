[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# basic-cli

A Roc [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) to work with files, commands, HTTP, TCP, command line arguments,...

:eyes: **examples**:
  - [0.19.0](https://github.com/roc-lang/basic-cli/tree/0.19.0/examples)
  - [0.18.0](https://github.com/roc-lang/basic-cli/tree/0.18.0/examples)
  - [0.17.0](https://github.com/roc-lang/basic-cli/tree/0.17.0/examples)
  - [latest main branch](https://github.com/roc-lang/basic-cli/tree/main/examples)

:book: **documentation**:
  - [0.19.0](https://roc-lang.github.io/basic-cli/0.19.0/)
  - [0.18.0](https://roc-lang.github.io/basic-cli/0.18.0/)
  - [0.17.0](https://roc-lang.github.io/basic-cli/0.17.0/)
  - [latest main branch](https://roc-lang.github.io/basic-cli/main/)

## Running locally

If you clone this repo instead of using the release URL you'll need to build the platform once:
```sh
./jump-start.sh
roc build.roc --linker=legacy
```
Then you can run like usual:
```sh
$ roc examples/hello-world.roc
Hello, World!
```
