# Dune Binary Installer

## Install Dune

Paste this into your terminal to install Dune:
```
curl -4fsSL https://github.com/gridbugs/dune-bin-install/releases/download/gridbugs-v3/install.sh | sh
```

No installation of opam or OCaml is necessary. Dune will be installed under `~/.local` by default.

## Non-interactive Installation

By default the install script is interactive, prompting for the install location
and whether or not to update the shell config file. This information can be
specified on the command-line instead which prevents the script from prompting.
In some situations it's necessary to install Dune non-interactively, such as
when building a docker image. To do this, run the script with
`--install-root PATH` and one of `--update-shell-config` and
`--no-update-shell-config`.

For example to install Dune while building a docker image from a Dockerfile,
assuming `curl` is installed and the current user is root, one could use:
```dockerfile
RUN curl -4fsSL https://github.com/gridbugs/dune-bin-install/releases/download/gridbugs-v3/install.sh | sh -s 3.20.1 --install-root /usr --no-update-shell-config
```
Note the `--install-root /usr`, which causes dune to be installed system-wide,
with its executable installed to `/usr/bin/dune`. Since `/usr/bin` is almost
certainly already in `$PATH`, this will make the `dune` command available
without needing to modify the environment.

##  Tests

### `test_errors.sh`

This script exercises error cases. It takes the path to the install script as
an argument. Its expected output is in `errors.expected_output`. Run the tests
with:

```bash
diff <(./test_errors.sh ./install.sh) test_errors.expected_output
```

### `test_interactive.tcl`

This is an expect script for running the interactive installation script and
sending it various inputs at prompts, and asserting that it responds the way we
expect.

### `test.dockerfile`

A Dockerfile that installs dune using the install script, then assets some
facts to test that the installation succeeded. Build an image with the
Dockerfile to run the tests (`docker build . -f test.dockerfile`).
