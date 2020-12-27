# dssh.sh

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/negokaz/dssh.sh?logoColor=%23000)](https://github.com/negokaz/dssh.sh/releases)
[![test](https://github.com/negokaz/dssh.sh/workflows/test/badge.svg)](https://github.com/negokaz/dssh.sh/actions?query=workflow%3Atest)

ssh client script for distributed systems

![](docs/img/ping.gif)

## Requirements

- `bash`
- `ssh`
- *nix basic commands (`xargs`, `cat`, and so on)

## Install

Place `dssh.sh` to a directory which definition in `PATH` environment variable.

```
curl -L https://raw.githubusercontent.com/negokaz/dssh.sh/master/dssh.sh \
    -o /usr/local/bin/dssh.sh
chmod +x /usr/local/bin/dssh.sh
```

## Usage

### Watch log being in destination servers

```
dssh.sh --ssh user@192.168.10.10 --ssh user@192.168.10.11 tail -F /var/log/messages
```

### Watch log with destination file

```
dssh.sh -f ssh.dests tail -F /var/log/messages
```

### Collect ERROR logs on server and sort they on localhost

```
dssh.sh -f ssh.dests --no-label bash -c 'cat /var/log/messages | grep ERROR' | sort | less -R
```

### Publish a file to destination servers

```
cat source.txt | dssh.sh -f ssh.dests --silent tee /tmp/dest.txt
```

### Fetch files from destination servers

```
dssh.sh -f ssh.dests -o out -a messages.log --silent cat /var/log/messages
```

## Destination file format

A destination file (`*.dests`) is a file that contains destinations for ssh.

Destinations are separated by line feeds like this:

```bash
# This is a comment
user@192.168.10.10

user@192.168.10.11 # You can place comments like a shell script
```

## License

Copyright (c) 2019 Kazuki Negoro

dssh.sh is released under the [MIT License](./LICENSE)
