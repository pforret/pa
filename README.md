![bash_unit CI](https://github.com/pforret/pa/workflows/bash_unit%20CI/badge.svg)
![Shellcheck CI](https://github.com/pforret/pa/workflows/Shellcheck%20CI/badge.svg)
![GH Language](https://img.shields.io/github/languages/top/pforret/pa)
![GH stars](https://img.shields.io/github/stars/pforret/pa)
![GH tag](https://img.shields.io/github/v/tag/pforret/pa)
![GH License](https://img.shields.io/github/license/pforret/pa)
[![basher install](https://img.shields.io/badge/basher-install-white?logo=gnu-bash&style=flat)](https://basher.gitparade.com/package/)

# pa

php artisan replacement

## 🔥 Usage

```
Program : pa  by peter@forret.com
Version : v0.0.3 (2022-09-26 20:04)
Purpose : php artisan replacement
Usage   : pa [-h] [-q] [-v] [-f] [-l <log_dir>] [-t <tmp_dir>] <action> <input …>
Flags, options and parameters:
    -h|--help        : [flag] show usage [default: off]
    -q|--quiet       : [flag] no output [default: off]
    -v|--verbose     : [flag] also show debug messages [default: off]
    -f|--force       : [flag] do not ask for confirmation (always yes) [default: off]
    -l|--log_dir <?> : [option] folder for log files   [default: /home/pforret/log/pa]
    -t|--tmp_dir <?> : [option] folder for temp files  [default: /tmp/pa]
    <action>         : [choice] action to perform  [options: c,co,composer,r,run,check,update,env]
    <input>          : [parameters] input file/text (1 or more)
```

## ⚡️ Examples

```bash
> pa co install
> pa config install
# run composer install, with the correct PHP version
```

## 🚀 Installation

with [basher](https://github.com/basherpm/basher)

	$ basher install pforret/pa

or with `git`

	$ git clone https://github.com/pforret/pa.git
	$ cd pa

## 📝 Acknowledgements

* script created with [bashew](https://github.com/pforret/bashew)

&copy; 2022 Peter Forret
