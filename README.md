![bash_unit CI](https://github.com/pforret/pa/workflows/bash_unit%20CI/badge.svg)
![Shellcheck CI](https://github.com/pforret/pa/workflows/Shellcheck%20CI/badge.svg)
![GH Language](https://img.shields.io/github/languages/top/pforret/pa)
![GH stars](https://img.shields.io/github/stars/pforret/pa)
![GH tag](https://img.shields.io/github/v/tag/pforret/pa)
![GH License](https://img.shields.io/github/license/pforret/pa)
[![basher install](https://img.shields.io/badge/basher-install-white?logo=gnu-bash&style=flat)](https://basher.gitparade.com/package/)

# pforret/pa

![](assets/pa.jpg)

Run `php artisan` and `composer` with the correct PHP version for the project, derived from composer.json

## 🔥 Usage

```
Program : pa by peter@forret.com
Version : v0.2.0 (2025-03-20 09:22)
Purpose : php artisan replacement
Usage   : pa [-h] [-q] [-v] [-f] [-l <log_dir>] [-t <tmp_dir>] [-P <OVERRIDE_PHP>] <action>
Flags, options and parameters:
    -h|--help        : [flag] show usage [default: off]
    -q|--quiet       : [flag] no output [default: off]
    -v|--verbose     : [flag] also show debug messages [default: off]
    -f|--force       : [flag] do not ask for confirmation (always yes) [default: off]
    -l|--log_dir <?> : [option] folder for log files   [default: /home/forretp/log/pa]
    -t|--tmp_dir <?> : [option] folder for temp files  [default: /tmp/pa]
    -P|--OVERRIDE_PHP <?>: [option] override PHP binary to use (e.g. php8.1)
    <action>         : [parameter] action to perform (see pa -h for details)
✅  Remote: gh_pforret:pforret/pa.git
                                  
### TIPS & EXAMPLES
* use pa list to show the available PHP versions on this machine
  pa list
* use pa pick to show the best PHP version for this machine/repo
  pa pick
* use pa co to run 'composer' with the optimal PHP version
  pa co require author/package
  pa co install
* use pa serve to run 'php artisan serve' with unique port per project
  pa serve
 
>>> bash script created with pforret/bashew
```

## ⚡️ Examples

```bash
# run `php artisan`, but with the correct PHP version for this project
$ pa route:list
$ pa make:model ModelName

# run `composer install`, with the correct PHP version
> pa c install
> pa co install
> pa com install
> pa comp install
> pa composer install

# run `composer require` author/package, with the correct PHP version
> pa co require author/package

# run 'pa pick' to see what PHP version would be chosen in this folder
# will parse PHP requirements from composer.json like "^8.0" or "^7.4|^8.0" 
# and use the lowest version of PHP that is installed and qualifies
$ pa pick
/usr/bin/php7.4

# run 'pa serve' to start 'php artisan serve' command with right PHP version
# and a specific pseudo-random port per project (derived from folder name)
# or with the .env settings, if any
# e.g. APP_URL=http://project.test:8010
$ pa serve
--------------------------------
open http://project.test:8010 in 5 seconds
press CTRL-C to stop this server
--------------------------------

# show all available PHP versions on this machine
> pa list
# Installed on this machine [name]:
# - - - - - - - - - - - - - - - - - - - - -
# /usr/bin/php              8.0.26          ✅  Supported until 2023-11-26
# /usr/bin/php8.2           8.2.0           ✅  Supported until 2025-12-08
# /usr/bin/php8.1           8.1.13          ✅  Supported until 2024-11-25
# /usr/bin/php8.0           8.0.26          ✅  Supported until 2023-11-26
# /usr/bin/php7.4           7.4.33          ⛔  Unsupported since 2022-11-28
# /usr/local/bin/composer   2.5.1 2022-12-22
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
