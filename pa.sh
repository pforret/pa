#!/usr/bin/env bash
### Created by Peter Forret ( pforret ) on 2022-09-26
### Based on https://github.com/pforret/bashew 1.18.8
script_version="0.0.0" # if there is a VERSION.md in this script's folder, it will take priority for version number
readonly script_author="peter@forret.com"
readonly script_created="2022-09-26"
readonly run_as_root=-1 # run_as_root: 0 = don't check anything / 1 = script MUST run as root / -1 = script MAY NOT run as root

## some initialisation
action=""
script_prefix=""
script_basename=""
install_package=""
temp_files=()

function Option:config() {
  grep <<<"
#commented lines will be filtered
flag|h|help|show usage
flag|q|quiet|no output
flag|v|verbose|also show debug messages
flag|f|force|do not ask for confirmation (always yes)
option|l|log_dir|folder for log files |$HOME/log/$script_prefix
option|t|tmp_dir|folder for temp files|/tmp/$script_prefix
option|P|OVERRIDE_PHP|override PHP binary to use (e.g. php8.1)
param|1|action|action to perform (see $script_prefix -h for details)
param|*|params|optional parameters for composer or artisan
" -v -e '^#' -e '^\s*$'
}

#####################################################################
## Put your Script:main script here
#####################################################################

Script:main() {
  IO:log "[$script_basename] $script_version started"

  Os:require awk
  Os:require jq

  action=$(Str:lower "$action")
  case $action in
  list)
    #TIP: use «$script_prefix list» to show the available PHP versions on this machine
    #TIP:> $script_prefix list
    IO:print "# Installed on this machine $(hostname):"
    IO:print "# - - - - - - - - - - - - - - - - - - - - -"
    list_installed_versions
    ;;

  pick)
    #TIP: use «$script_prefix pick» to show the best PHP version for this machine/repo
    #TIP:> $script_prefix pick
    choose_php
    ;;

  c | co | com | comp | composer)
    #TIP: use «$script_prefix co» to run 'composer' with the optimal PHP version
    #TIP:> $script_prefix co require author/package
    #TIP:> $script_prefix co install
    PHP_BIN="$(choose_php)"
    COMPBIN=$(command -v composer)
    IO:debug "Using PHP: $PHP_BIN // Composer $COMPBIN"
    IO:debug "$PHP_BIN $COMPBIN $(echo "${params:-}" | xargs)"
    if [[ -n "${params:-}" ]]; then
      "$PHP_BIN" "$COMPBIN" "${params}"
    else
      "$PHP_BIN" "$COMPBIN"
    fi
    ;;

  s | serve)
    #TIP: use «$script_prefix serve» to run 'php artisan serve' with unique port per project
    #TIP:> $script_prefix serve
    Os:require sha256sum
    PHP_BIN="$(choose_php)"
    local host=localhost
    local port
    port="8$(pwd | sha256sum | sed 's/[^0-9]//g' | cut -c1-3)"
    if [[ -f .env ]]; then
      local app_url
      local host_port
      # APP_URL=http://laravelserve:8080
      app_url=$(grep "APP_URL=" .env | cut -d= -f2)
      if [[ -n "$app_url" ]]; then
        host_port=$(echo "$app_url" | cut -d/ -f3)
        host=$(echo "$host_port" | cut -d: -f1)
        [[ "$host" != "$host_port" ]] && port=$(echo "$host_port" | cut -d: -f2)
      fi
    fi
    IO:debug "Using host: $host"
    IO:debug "Using port: $port"

    local url="http://$host:$port"
    local delay=5

    echo "--------------------------------"
    echo "open $url in $delay seconds"
    echo "press CTRL-C to stop this server"
    echo "--------------------------------"

    local today
    today=$(date "+%Y-%m-%d")
    local log_file="$log_dir/php.$today.log"
    (sleep "$delay" && explorer.exe "$url") &
    if [[ -f "artisan" ]] ; then
      IO:debug "Detected Laravel - run '$PHP_BIN artisan serve'"
      "$PHP_BIN" artisan serve -q --port="$port" --host="$host"
    else
      IO:debug "No framework detected - run '$PHP_BIN -S'"
      IO:debug "Log file: $log_file"
      "$PHP_BIN" -S "$host:$port" 2>> "$log_file"
    fi

    ;;

  *)
    # just pass it to php artisan
    if [[ ! -f artisan ]]; then
      IO:alert "Current folder  = $(pwd)"
      git status >/dev/null && IO:alert "Repository root = $(git rev-parse --show-toplevel)"
      IO:die "No 'artisan' script present, are you in the root folder of a Laravel project?"
    fi
    PHP_BIN="$(choose_php)"
    IO:debug "Using PHP: $PHP_BIN"
    "$PHP_BIN" artisan "$action" "${params:-}"

    ;;
  esac
  IO:log "[$script_basename] ended after $SECONDS secs"
  #TIP: >>> bash script created with «pforret/bashew»
}

#####################################################################
## Put your helper scripts here
#####################################################################

function choose_php() {
  IO:debug "Find PHP binary to use"
  # first check override PHP
  if [[ -n "$OVERRIDE_PHP" ]]; then
    PHP_BIN=$(command -v "$OVERRIDE_PHP")
    if [[ -n "$PHP_BIN" ]]; then
      IO:debug "Override: $PHP_BIN"
      echo "$PHP_BIN" && return 0
    fi
  fi
  COMPOSER_JSON="composer.json"
  # if no composer.json
  if [[ ! -f "$COMPOSER_JSON" ]]; then
    PHP_BIN=$(command -v "php")
    if [[ -n "$PHP_BIN" ]]; then
      IO:debug "No Composer: $PHP_BIN"
      echo "$PHP_BIN" && return 0
    fi
  fi
  # if composer.json has no php require statement
  composer_php_requirement=$(jq <"$COMPOSER_JSON" -r ".require.php")
  if [[ -z "$composer_php_requirement" ]]; then
    PHP_BIN=$(command -v "php")
    if [[ -n "$PHP_BIN" ]]; then
      IO:debug "No Composer: $PHP_BIN"
      echo "$PHP_BIN" && return 0
    fi
  fi

  # https://getcomposer.org/doc/articles/versions.md
  echo "$composer_php_requirement" | tr '|' "\n" |
    while read -r spec; do
      case "${spec:0:1}" in
      "^")
        # https://getcomposer.org/doc/articles/versions.md#caret-version-range-
        # ^1.2.3 is equivalent to >=1.2.3 <2.0.0
        min_version=${spec:1}
        min_decimal=$(semver2decimal "$min_version")
        max_decimal=$(((min_decimal / 1000000 + 1) * 1000000 - 1))
        IO:debug "Allowed: $spec : $min_decimal - $max_decimal"
        filter_allowed_phps "$min_decimal" "$max_decimal"
        ;;

      "~")
        # https://getcomposer.org/doc/articles/versions.md#tilde-version-range-
        # ~1.2 is equivalent to >=1.2 <2.0.0, while ~1.2.3 is equivalent to >=1.2.3 <1.3.0
        min_version=${spec:1}
        min_decimal=$(semver2decimal "$min_version")
        if [[ -z $(echo "$min_version" | cut -d. -f3) ]]; then
          max_decimal=$(((min_decimal / 1000000 + 1) * 1000000 - 1))
        else
          max_decimal=$(((min_decimal / 1000 + 1) * 1000 - 1))
        fi
        IO:debug "Allowed: $spec : $min_decimal - $max_decimal"
        filter_allowed_phps "$min_decimal" "$max_decimal"
        ;;

      *)
        # https://getcomposer.org/doc/articles/versions.md#exact-version-constraint
        min_version=${spec}
        min_decimal=$(semver2decimal "$min_version")
        if [[ -z $(echo "$min_version" | cut -d. -f3) ]]; then
          max_decimal=$(((min_decimal / 1000 + 1) * 1000))
        else
          max_decimal="$((min_decimal + 1))"
        fi
        IO:debug "allowed: $spec : $min_decimal - $max_decimal"
        filter_allowed_phps "$min_decimal" "$max_decimal"
        ;;
      esac
    done |
    sort -u | head -1 | cut -d';' -f2
}

function list_installed_versions() {
  local version
  local found_php
  local found_composer

  for line in $(detect_installed_php_binaries); do
    binary=$(echo "$line" | cut -d";" -f1)
    version=$(echo "$line" | cut -d";" -f2)
    printf "# %-25s %-15s %s\n" "$binary" "$version" "$(version_end_of_support "$version")"
  done
  found_composer=$(command -v composer)
  [[ -n "$found_composer" ]] && printf "# %-25s %-15s %s\n" "$found_composer" "$($found_composer --version | awk 'NR == 1 {gsub(/ version/,""); print $2,$3}')" " "
}

function detect_installed_php_binaries() {
  local cache_versions
  # this is slow, so keep a cache
  cache_versions=$tmp_dir/versions.$(date '+%Y-%m-%d').txt
  ((force)) && rm -f "$cache_versions"
  if [[ ! -f "$cache_versions" ]]; then
    for version in "" 8.3 8.2 8.1 8.0 8 7.4 7.3 7.2 7.1 7.0 7 5.6 5.5 5.4 5.3 5.2 5.1 5.0; do
      found_php=$(command -v "php$version")
      [[ -n "$found_php" ]] && echo "$found_php;$(detect_php_version "$found_php")" >>"$cache_versions"
    done
    IO:debug "Cached PHP versions in $cache_versions"
  fi
  cat "$cache_versions"
}

function filter_allowed_phps() {
  local minimum="$1"
  local maximum="$2"
  detect_installed_php_binaries |
    while IFS=";" read -r php_path detect_php_version; do
      dec_version=$(semver2decimal "$detect_php_version")
      [[ "$dec_version" -lt "$minimum" ]] && continue
      [[ "$dec_version" -ge "$maximum" ]] && continue
      echo "$dec_version;$php_path"
    done |
    sort -u
}

function version_end_of_support() {
  # https://www.php.net/supported-versions.php
  local today
  today=$(date "+%Y-%m-%d")
  case "$(echo "$1" | cut -d. -f1-2)" in
  5.0) support_ends="2005-09-05" ;;
  5.1) support_ends="2006-08-24" ;;
  5.2) support_ends="2011-01-06" ;;
  5.3) support_ends="2014-08-14" ;;
  5.4) support_ends="2015-09-03" ;;
  5.5) support_ends="2016-07-21" ;;
  5.6) support_ends="2018-12-31" ;;

  7.0) support_ends="2019-01-10" ;;
  7.1) support_ends="2019-12-01" ;;
  7.2) support_ends="2020-11-30" ;;
  7.3) support_ends="2021-12-06" ;;
  7.4) support_ends="2022-11-28" ;;

  8.0) support_ends="2023-11-26" ;;
  8.1) support_ends="2024-11-25" ;;
  8.2) support_ends="2025-12-08" ;;
  8.3) support_ends="2026-11-30" ;;

  *) support_ends="" ;;
  esac

  if [[ "$today" < "$support_ends" ]]; then
    echo "$char_succes  Supported until $support_ends"
  else
    echo "$char_fail  Unsupported since $support_ends"
  fi

}

function detect_php_version() {
  "${1:-php}" -v | awk 'NR == 1 { print $2 }'
}

function semver2decimal() {
  # input: 2.3.4
  # output: 2003004
  echo "$1" |
    awk -F. '{print int($1)*1000000 + int($2)*1000 + int($3)}'
}

function decimal2semver() {
  #input: 2003004
  # output: 2.3.4
  echo "$1" |
    awk -F. '{print ($1/1000000)%1000,($1/1000)%1000,$1%1000}'
}

#####################################################################
################### DO NOT MODIFY BELOW THIS LINE ###################
#####################################################################

# set strict mode -  via http://redsymbol.net/articles/unofficial-bash-strict-mode/
# removed -e because it made basic [[ testing ]] difficult
set -uo pipefail
IFS=$'\n\t'
force=0
help=0
error_prefix=""

#to enable verbose even before option parsing
verbose=0
[[ $# -gt 0 ]] && [[ $1 == "-v" ]] && verbose=1

#to enable quiet even before option parsing
quiet=0
[[ $# -gt 0 ]] && [[ $1 == "-q" ]] && quiet=1

### stdIO:print/stderr output
function IO:initialize() {
  [[ "${BASH_SOURCE[0]:-}" != "${0}" ]] && sourced=1 || sourced=0
  [[ -t 1 ]] && piped=0 || piped=1 # detect if output is piped
  if [[ $piped -eq 0 ]]; then
    txtReset=$(tput sgr0)
    txtError=$(tput setaf 160)
    txtInfo=$(tput setaf 2)
    txtWarn=$(tput setaf 214)
    txtBold=$(tput bold)
    txtItalic=$(tput sitm)
    txtUnderline=$(tput smul)
  else
    txtReset=""
    txtError=""
    txtInfo=""
    txtInfo=""
    txtWarn=""
    txtBold=""
    txtItalic=""
    txtUnderline=""
  fi

  [[ $(echo -e '\xe2\x82\xac') == '€' ]] && unicode=1 || unicode=0 # detect if unicode is supported
  if [[ $unicode -gt 0 ]]; then
    char_succes="✅"
    char_fail="⛔"
    char_alert="✴️"
    char_wait="⏳"
    info_icon="🌼"
    config_icon="🌱"
    clean_icon="🧽"
    require_icon="🔌"
  else
    char_succes="OK "
    char_fail="!! "
    char_alert="?? "
    char_wait="..."
    info_icon="(i)"
    config_icon="[c]"
    clean_icon="[c]"
    require_icon="[r]"
  fi
  error_prefix="${txtError}>${txtReset}"
}

function IO:print() {
  ((quiet)) && true || printf '%b\n' "$*"
}

function IO:debug() {
  ((verbose)) && IO:print "${txtInfo}# $* ${txtReset}" >&2
  true
}

function IO:die() {
  IO:print "${txtError}${char_fail} $script_basename${txtReset}: $*" >&2
  tput bel
  Script:exit
}

function IO:alert() {
  IO:print "${txtWarn}${char_alert}${txtReset}: ${txtUnderline}$*${txtReset}" >&2
}

function IO:success() {
  IO:print "${txtInfo}${char_succes}${txtReset}  ${txtBold}$*${txtReset}"
}

function IO:announce() {
  IO:print "${txtInfo}${char_wait}${txtReset}  ${txtItalic}$*${txtReset}"
  sleep 1
}

function IO:progress() {
  ((quiet)) || (
    local screen_width
    screen_width=$(tput cols 2>/dev/null || echo 80)
    local rest_of_line
    rest_of_line=$((screen_width - 5))

    if ((piped)); then
      IO:print "... $*" >&2
    else
      printf "... %-${rest_of_line}b\r" "$*                                             " >&2
    fi
  )
}

### interactive
function IO:confirm() {
  ((force)) && return 0
  read -r -p "$1 [y/N] " -n 1
  echo " "
  [[ $REPLY =~ ^[Yy]$ ]]
}

function IO:question() {
  local ANSWER
  local DEFAULT=${2:-}
  read -r -p "$1 ($DEFAULT) > " ANSWER
  [[ -z "$ANSWER" ]] && echo "$DEFAULT" || echo "$ANSWER"
}

function IO:log() {
  [[ -n "${log_file:-}" ]] && echo "$(date '+%H:%M:%S') | $*" >>"$log_file"
}

function Tool:calc() {
  awk "BEGIN {print $*} ; "
}

function Tool:time() {
  if [[ $(command -v perl) ]]; then
    perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
  elif [[ $(command -v php) ]]; then
    php -r 'echo microtime(true) . "\n"; '
  elif [[ $(command -v python) ]]; then
    python -c "import time; print(time.time()) "
  else
    date "+%s" | awk '{printf("%.3f\n",$1)}'
  fi
}

### string processing

function Str:trim() {
  local var="$*"
  # remove leading whitespace characters
  var="${var#"${var%%[![:space:]]*}"}"
  # remove trailing whitespace characters
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

function Str:lower() {
  if [[ -n "$1" ]]; then
    local input="$*"
    echo "${input,,}"
  else
    awk '{print tolower($0)}'
  fi
}

function Str:upper() {
  if [[ -n "$1" ]]; then
    local input="$*"
    echo "${input^^}"
  else
    awk '{print toupper($0)}'
  fi
}

function Str:ascii() {
  # remove all characters with accents/diacritics to latin alphabet
  # shellcheck disable=SC2020
  sed 'y/àáâäæãåāǎçćčèéêëēėęěîïííīįìǐłñńôöòóœøōǒõßśšûüǔùǖǘǚǜúūÿžźżÀÁÂÄÆÃÅĀǍÇĆČÈÉÊËĒĖĘĚÎÏÍÍĪĮÌǏŁÑŃÔÖÒÓŒØŌǑÕẞŚŠÛÜǓÙǕǗǙǛÚŪŸŽŹŻ/aaaaaaaaaccceeeeeeeeiiiiiiiilnnooooooooosssuuuuuuuuuuyzzzAAAAAAAAACCCEEEEEEEEIIIIIIIILNNOOOOOOOOOSSSUUUUUUUUUUYZZZ/'
}

function Str:slugify() {
  # Str:slugify <input> <separator>
  # Str:slugify "Jack, Jill & Clémence LTD"      => jack-jill-clemence-ltd
  # Str:slugify "Jack, Jill & Clémence LTD" "_"  => jack_jill_clemence_ltd
  separator="${2:-}"
  [[ -z "$separator" ]] && separator="-"
  Str:lower "$1" |
    Str:ascii |
    awk '{
          gsub(/[\[\]@#$%^&*;,.:()<>!?\/+=_]/," ",$0);
          gsub(/^  */,"",$0);
          gsub(/  *$/,"",$0);
          gsub(/  */,"-",$0);
          gsub(/[^a-z0-9\-]/,"");
          print;
          }' |
    sed "s/-/$separator/g"
}

function Str:title() {
  # Str:title <input> <separator>
  # Str:title "Jack, Jill & Clémence LTD"     => JackJillClemenceLtd
  # Str:title "Jack, Jill & Clémence LTD" "_" => Jack_Jill_Clemence_Ltd
  separator="${2:-}"
  # shellcheck disable=SC2020
  Str:lower "$1" |
    tr 'àáâäæãåāçćčèéêëēėęîïííīįìłñńôöòóœøōõßśšûüùúūÿžźż' 'aaaaaaaaccceeeeeeeiiiiiiilnnoooooooosssuuuuuyzzz' |
    awk '{ gsub(/[\[\]@#$%^&*;,.:()<>!?\/+=_-]/," ",$0); print $0; }' |
    awk '{
          for (i=1; i<=NF; ++i) {
              $i = toupper(substr($i,1,1)) tolower(substr($i,2))
          };
          print $0;
          }' |
    sed "s/ /$separator/g" |
    cut -c1-50
}

function Str:digest() {
  local length=${1:-6}
  if [[ -n $(command -v md5sum) ]]; then
    # regular linux
    md5sum | cut -c1-"$length"
  else
    # macos
    md5 | cut -c1-"$length"
  fi
}

trap "IO:die \"ERROR \$? after \$SECONDS seconds \n\
\${error_prefix} last command : '\$BASH_COMMAND' \" \
\$(< \$script_install_path awk -v lineno=\$LINENO \
'NR == lineno {print \"\${error_prefix} from line \" lineno \" : \" \$0}')" INT TERM EXIT
# cf https://askubuntu.com/questions/513932/what-is-the-bash-command-variable-good-for

Script:exit() {
  for temp_file in "${temp_files[@]-}"; do
    [[ -f "$temp_file" ]] && (
      IO:debug "Delete temp file [$temp_file]"
      rm -f "$temp_file"
    )
  done
  trap - INT TERM EXIT
  IO:debug "$script_basename finished after $SECONDS seconds"
  exit 0
}

Script:check_version() {
  (
    # shellcheck disable=SC2164
    pushd "$script_install_folder" &>/dev/null
    if [[ -d .git ]]; then
      local remote
      remote="$(git remote -v | grep fetch | awk 'NR == 1 {print $2}')"
      IO:success "Remote: $remote"
      IO:progress "Check for latest version"
      git remote update &>/dev/null
      if [[ $(git rev-list --count "HEAD...HEAD@{upstream}" 2>/dev/null) -gt 0 ]]; then
        IO:print "There is a more recent update of this script - run <<$script_prefix update>> to update"
      fi
    fi
    # shellcheck disable=SC2164
    popd &>/dev/null
  )
}

Script:git_pull() {
  # run in background to avoid problems with modifying a running interpreted script
  (
    sleep 1
    cd "$script_install_folder" && git pull
  ) &
}

Script:show_tips() {
  ((sourced)) && return 0
  # shellcheck disable=SC2016
  grep <"${BASH_SOURCE[0]}" -v '$0' |
    awk \
      -v green="$txtInfo" \
      -v yellow="$txtWarn" \
      -v reset="$txtReset" \
      '
      /TIP: /  {$1=""; gsub(/«/,green); gsub(/»/,reset); print "*" $0}
      /TIP:> / {$1=""; print " " yellow $0 reset}
      ' |
    awk \
      -v script_basename="$script_basename" \
      -v script_prefix="$script_prefix" \
      '{
      gsub(/\$script_basename/,script_basename);
      gsub(/\$script_prefix/,script_prefix);
      print ;
      }'
}

Script:check() {
  local name
  if [[ -n $(Option:filter flag) ]]; then
    IO:print "## ${txtInfo}boolean flags${txtReset}:"
    Option:filter flag |
      while read -r name; do
        if ((piped)); then
          eval "echo \"$name=\$${name:-}\""
        else
          eval "echo -n \"$name=\$${name:-}  \""
        fi
      done
    IO:print " "
    IO:print " "
  fi

  if [[ -n $(Option:filter option) ]]; then
    IO:print "## ${txtInfo}option defaults${txtReset}:"
    Option:filter option |
      while read -r name; do
        if ((piped)); then
          eval "echo \"$name=\$${name:-}\""
        else
          eval "echo -n \"$name=\$${name:-}  \""
        fi
      done
    IO:print " "
    IO:print " "
  fi

  if [[ -n $(Option:filter list) ]]; then
    IO:print "## ${txtInfo}list options${txtReset}:"
    Option:filter list |
      while read -r name; do
        if ((piped)); then
          eval "echo \"$name=(\${${name}[@]})\""
        else
          eval "echo -n \"$name=(\${${name}[@]})  \""
        fi
      done
    IO:print " "
    IO:print " "
  fi

  if [[ -n $(Option:filter param) ]]; then
    if ((piped)); then
      IO:debug "Skip parameters for .env files"
    else
      IO:print "## ${txtInfo}parameters${txtReset}:"
      Option:filter param |
        while read -r name; do
          # shellcheck disable=SC2015
          ((piped)) && eval "echo \"$name=\\\"\${$name:-}\\\"\"" || eval "echo -n \"$name=\\\"\${$name:-}\\\"  \""
        done
      echo " "
    fi
    IO:print " "
  fi

  if [[ -n $(Option:filter choice) ]]; then
    if ((piped)); then
      IO:debug "Skip choices for .env files"
    else
      IO:print "## ${txtInfo}choice${txtReset}:"
      Option:filter choice |
        while read -r name; do
          # shellcheck disable=SC2015
          ((piped)) && eval "echo \"$name=\\\"\${$name:-}\\\"\"" || eval "echo -n \"$name=\\\"\${$name:-}\\\"  \""
        done
      echo " "
    fi
    IO:print " "
  fi

  IO:print "## ${txtInfo}required commands${txtReset}:"
  Script:show_required
}

Option:usage() {
  IO:print "Program : ${txtInfo}$script_basename${txtReset} by ${txtWarn}$script_author${txtReset}"
  IO:print "Version : ${txtInfo}v$script_version${txtReset} (${txtWarn}$script_modified${txtReset})"
  IO:print "Purpose : ${txtInfo}php artisan replacement${txtReset}"
  echo -n "Usage   : $script_basename"
  Option:config |
    awk '
  BEGIN { FS="|"; OFS=" "; oneline="" ; fulltext="Flags, options and parameters:"}
  $1 ~ /flag/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [flag] %s [default: off]",$2,$3,$4) ;
    oneline  = oneline " [-" $2 "]"
    }
  $1 ~ /option/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [option] %s",$2,$3 " <?>",$4) ;
    if($5!=""){fulltext = fulltext "  [default: " $5 "]"; }
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /list/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [list] %s (array)",$2,$3 " <?>",$4) ;
    fulltext = fulltext "  [default empty]";
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /secret/  {
    fulltext = fulltext sprintf("\n    -%1s|--%s <%s>: [secret] %s",$2,$3,"?",$4) ;
      oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /param/ {
    if($2 == "1"){
          fulltext = fulltext sprintf("\n    %-17s: [parameter] %s","<"$3">",$4);
          oneline  = oneline " <" $3 ">"
     }
     if($2 == "?"){
          fulltext = fulltext sprintf("\n    %-17s: [parameter] %s (optional)","<"$3">",$4);
          oneline  = oneline " <" $3 "?>"
     }
     if($2 == "n"){
          fulltext = fulltext sprintf("\n    %-17s: [parameters] %s (1 or more)","<"$3">",$4);
          oneline  = oneline " <" $3 " …>"
     }
    }
  $1 ~ /choice/ {
        fulltext = fulltext sprintf("\n    %-17s: [choice] %s","<"$3">",$4);
        if($5!=""){fulltext = fulltext "  [options: " $5 "]"; }
        oneline  = oneline " <" $3 ">"
    }
    END {print oneline; print fulltext}
  '
}

function Option:filter() {
  Option:config | grep "$1|" | cut -d'|' -f3 | sort | grep -v '^\s*$'
}

function Script:show_required() {
  grep 'Os:require' "$script_install_path" |
    grep -v -E '\(\)|grep|# Os:require' |
    awk -v install="# $install_package " '
    function ltrim(s) { sub(/^[ "\t\r\n]+/, "", s); return s }
    function rtrim(s) { sub(/[ "\t\r\n]+$/, "", s); return s }
    function trim(s) { return rtrim(ltrim(s)); }
    NF == 2 {print install trim($2); }
    NF == 3 {print install trim($3); }
    NF > 3  {$1=""; $2=""; $0=trim($0); print "# " trim($0);}
  ' |
    sort -u
}

function Option:initialize() {
  local init_command
  init_command=$(Option:config |
    grep -v "verbose|" |
    awk '
    BEGIN { FS="|"; OFS=" ";}
    $1 ~ /flag/   && $5 == "" {print $3 "=0; "}
    $1 ~ /flag/   && $5 != "" {print $3 "=\"" $5 "\"; "}
    $1 ~ /option/ && $5 == "" {print $3 "=\"\"; "}
    $1 ~ /option/ && $5 != "" {print $3 "=\"" $5 "\"; "}
    $1 ~ /choice/   {print $3 "=\"\"; "}
    $1 ~ /list/     {print $3 "=(); "}
    $1 ~ /secret/   {print $3 "=\"\"; "}
    ')
  if [[ -n "$init_command" ]]; then
    eval "$init_command"
  fi
}

function Option:has_single() { Option:config | grep 'param|1|' >/dev/null; }
function Option:has_choice() { Option:config | grep 'choice|1' >/dev/null; }
function Option:has_optional() { Option:config | grep 'param|?|' >/dev/null; }
function Option:has_multi() { Option:config | grep 'param|n|' >/dev/null; }
function Option:has_any() { Option:config | grep 'param|*|' >/dev/null; }

function Option:parse() {
  if [[ $# -eq 0 ]]; then
    Option:usage >&2
    Script:exit
  fi

  ## first process all the -x --xxxx flags and options
  while true; do
    # flag <flag> is saved as $flag = 0/1
    # option <option> is saved as $option
    if [[ $# -eq 0 ]]; then
      ## all parameters processed
      break
    fi
    if [[ ! $1 == -?* ]]; then
      ## all flags/options processed
      break
    fi
    local save_option
    save_option=$(Option:config |
      awk -v opt="$1" '
        BEGIN { FS="|"; OFS=" ";}
        $1 ~ /flag/   &&  "-"$2 == opt {print $3"=1"}
        $1 ~ /flag/   && "--"$3 == opt {print $3"=1"}
        $1 ~ /option/ &&  "-"$2 == opt {print $3"=$2; shift"}
        $1 ~ /option/ && "--"$3 == opt {print $3"=$2; shift"}
        $1 ~ /list/ &&  "-"$2 == opt {print $3"+=($2); shift"}
        $1 ~ /list/ && "--"$3 == opt {print $3"=($2); shift"}
        $1 ~ /secret/ &&  "-"$2 == opt {print $3"=$2; shift #noshow"}
        $1 ~ /secret/ && "--"$3 == opt {print $3"=$2; shift #noshow"}
        ')
    if [[ -n "$save_option" ]]; then
      if echo "$save_option" | grep shift >>/dev/null; then
        local save_var
        save_var=$(echo "$save_option" | cut -d= -f1)
        IO:debug "$config_icon parameter: ${save_var}=$2"
      else
        IO:debug "$config_icon flag: $save_option"
      fi
      eval "$save_option"
    else
      IO:die "cannot interpret option [$1]"
    fi
    shift
  done

  ((help)) && (
    Option:usage
    Script:check_version
    IO:print "                                  "
    echo "### TIPS & EXAMPLES"
    Script:show_tips

  ) && Script:exit

  local option_list
  local option_count
  local choices
  local single_params
  ## then run through the given parameters
  if Option:has_choice; then
    choices=$(Option:config | awk -F"|" '
      $1 == "choice" && $2 == 1 {print $3}
      ')
    option_list=$(xargs <<<"$choices")
    option_count=$(wc <<<"$choices" -w | xargs)
    IO:debug "$config_icon Expect : $option_count choice(s): $option_list"
    [[ $# -eq 0 ]] && IO:die "need the choice(s) [$option_list]"

    local choices_list
    local valid_choice
    for param in $choices; do
      [[ $# -eq 0 ]] && IO:die "need choice [$param]"
      [[ -z "$1" ]] && IO:die "need choice [$param]"
      IO:debug "$config_icon Assign : $param=$1"
      # check if choice is in list
      choices_list=$(Option:config | awk -F"|" -v choice="$param" '$1 == "choice" && $3 = choice {print $5}')
      valid_choice=$(tr <<<"$choices_list" "," "\n" | grep "$1")
      [[ -z "$valid_choice" ]] && IO:die "choice [$1] is not valid, should be in list [$choices_list]"

      eval "$param=\"$1\""
      shift
    done
  else
    IO:debug "$config_icon No choices to process"
    choices=""
    option_count=0
  fi

  if Option:has_single; then
    single_params=$(Option:config | awk -F"|" '
      $1 == "param" && $2 == 1 {print $3}
      ')
    option_list=$(xargs <<<"$single_params")
    option_count=$(wc <<<"$single_params" -w | xargs)
    IO:debug "$config_icon Expect : $option_count single parameter(s): $option_list"
    [[ $# -eq 0 ]] && IO:die "need the parameter(s) [$option_list]"

    for param in $single_params; do
      [[ $# -eq 0 ]] && IO:die "need parameter [$param]"
      [[ -z "$1" ]] && IO:die "need parameter [$param]"
      IO:debug "$config_icon Assign : $param=$1"
      eval "$param=\"$1\""
      shift
    done
  else
    IO:debug "$config_icon No single params to process"
    single_params=""
    option_count=0
  fi

  if Option:has_optional; then
    local optional_params
    local optional_count
    optional_params=$(Option:config | grep 'param|?|' | cut -d'|' -f3)
    optional_count=$(wc <<<"$optional_params" -w | xargs)
    IO:debug "$config_icon Expect : $optional_count optional parameter(s): $(echo "$optional_params" | xargs)"

    for param in $optional_params; do
      IO:debug "$config_icon Assign : $param=${1:-}"
      eval "$param=\"${1:-}\""
      shift
    done
  else
    IO:debug "$config_icon No optional params to process"
    optional_params=""
    optional_count=0
  fi

  if Option:has_any; then
    IO:debug "Process: all the rest of the parameters"
    local multi_count
    local multi_param
    multi_param=$(Option:config | grep 'param|\*|' | cut -d'|' -f3)
    eval "$multi_param=( $* )"
    shift $#
  fi

  if Option:has_multi; then
    #IO:debug "Process: multi param"
    local multi_count
    local multi_param
    multi_count=$(Option:config | grep -c 'param|n|')
    multi_param=$(Option:config | grep 'param|n|' | cut -d'|' -f3)
    IO:debug "$config_icon Expect : $multi_count multi parameter: $multi_param"
    ((multi_count > 1)) && IO:die "cannot have >1 'multi' parameter: [$multi_param]"
    ((multi_count > 0)) && [[ $# -eq 0 ]] && IO:die "need the (multi) parameter [$multi_param]"
    # save the rest of the params in the multi param
    if [[ -n "$*" ]]; then
      IO:debug "$config_icon Assign : $multi_param=$*"
      eval "$multi_param=( $* )"
    fi
  else
    multi_count=0
    multi_param=""
    [[ $# -gt 0 ]] && IO:die "cannot interpret extra parameters"
  fi
}

function Os:require() {
  local install_instructions
  local binary
  local words
  local path_binary
  # $1 = binary that is required
  binary="$1"
  path_binary=$(command -v "$binary" 2>/dev/null)
  [[ -n "$path_binary" ]] && IO:debug "️$require_icon required [$binary] -> $path_binary" && return 0
  # $2 = how to install it
  words=$(echo "${2:-}" | wc -w)
  if ((force)); then
    IO:announce "Installing [$1] ..."
    case $words in
    0) eval "$install_package $1" ;;
      # Os:require ffmpeg -- binary and package have the same name
    1) eval "$install_package $2" ;;
      # Os:require convert imagemagick -- binary and package have different names
    *) eval "${2:-}" ;;
      # Os:require primitive "go get -u github.com/fogleman/primitive" -- non-standard package manager
    esac
  else
    install_instructions="$install_package $1"
    [[ $words -eq 1 ]] && install_instructions="$install_package $2"
    [[ $words -gt 1 ]] && install_instructions="${2:-}"

    IO:alert "$script_basename needs [$binary] but it cannot be found"
    IO:alert "1) install package  : $install_instructions"
    IO:alert "2) check path       : export PATH=\"[path of your binary]:\$PATH\""
    IO:die "Missing program/script [$binary]"
  fi
}

function Os:folder() {
  if [[ -n "$1" ]]; then
    local folder="$1"
    local max_days=${2:-365}
    if [[ ! -d "$folder" ]]; then
      IO:debug "$clean_icon Create folder : [$folder]"
      mkdir -p "$folder"
    else
      IO:debug "$clean_icon Cleanup folder: [$folder] - delete files older than $max_days day(s)"
      find "$folder" -mtime "+$max_days" -type f -exec rm {} \;
    fi
  fi
}

function Os:follow_link() {
  [[ ! -L "$1" ]] && echo "$1" && return 0
  local file_folder
  local link_folder
  local link_name
  file_folder="$(dirname "$1")"
  # resolve relative to absolute path
  [[ "$file_folder" != /* ]] && link_folder="$(cd -P "$file_folder" &>/dev/null && pwd)"
  local symlink
  symlink=$(readlink "$1")
  link_folder=$(dirname "$symlink")
  link_name=$(basename "$symlink")
  [[ -z "$link_folder" ]] && link_folder="$file_folder"
  [[ "$link_folder" == \.* ]] && link_folder="$(cd -P "$file_folder" && cd -P "$link_folder" &>/dev/null && pwd)"
  IO:debug "$info_icon Symbolic ln: $1 -> [$symlink]"
  Os:follow_link "$link_folder/$link_name"
}

function Os:notify() {
  # cf https://levelup.gitconnected.com/5-modern-bash-scripting-techniques-that-only-a-few-programmers-know-4abb58ddadad
  local message="$1"
  local source="${2:-$script_basename}"

  [[ -n $(command -v notify-send) ]] && notify-send "$source" "$message"                                      # for Linux
  [[ -n $(command -v osascript) ]] && osascript -e "display notification \"$message\" with title \"$source\"" # for MacOS
}

function Os:busy() {
  # show spinner as long as process $pid is running
  local pid="$1"
  local message="${2:-}"
  local frames=("|" "/" "-" "\\")
  (
    while kill -0 "$pid" &>/dev/null; do
      for frame in "${frames[@]}"; do
        printf "\r[ $frame ] %s..." "$message"
        sleep 0.5
      done
    done
    printf "\n"
  )
}

function Os:beep() {
  local type="${1=-info}"
  case $type in
  *)
    tput bel
    ;;
  esac
}

function Script:meta() {
  local git_repo_remote=""
  local git_repo_root=""
  local os_kernel=""
  local os_machine=""
  local os_name=""
  local os_version=""
  local script_hash="?"
  local script_lines="?"
  local shell_brand=""
  local shell_version=""

  script_prefix=$(basename "${BASH_SOURCE[0]}" .sh)
  script_basename=$(basename "${BASH_SOURCE[0]}")
  execution_day=$(date "+%Y-%m-%d")

  script_install_path="${BASH_SOURCE[0]}"
  IO:debug "$info_icon Script path: $script_install_path"
  script_install_path=$(Os:follow_link "$script_install_path")
  IO:debug "$info_icon Linked path: $script_install_path"
  script_install_folder="$(cd -P "$(dirname "$script_install_path")" && pwd)"
  IO:debug "$info_icon In folder  : $script_install_folder"
  if [[ -f "$script_install_path" ]]; then
    script_hash=$(Str:digest <"$script_install_path" 8)
    script_lines=$(awk <"$script_install_path" 'END {print NR}')
  fi

  # get shell/operating system/versions
  shell_brand="sh"
  shell_version="?"
  [[ -n "${ZSH_VERSION:-}" ]] && shell_brand="zsh" && shell_version="$ZSH_VERSION"
  [[ -n "${BASH_VERSION:-}" ]] && shell_brand="bash" && shell_version="$BASH_VERSION"
  [[ -n "${FISH_VERSION:-}" ]] && shell_brand="fish" && shell_version="$FISH_VERSION"
  [[ -n "${KSH_VERSION:-}" ]] && shell_brand="ksh" && shell_version="$KSH_VERSION"
  IO:debug "$info_icon Shell type : $shell_brand - version $shell_version"

  os_kernel=$(uname -s)
  os_version=$(uname -r)
  os_machine=$(uname -m)
  install_package=""
  case "$os_kernel" in
  CYGWIN* | MSYS* | MINGW*)
    os_name="Windows"
    ;;
  Darwin)
    os_name=$(sw_vers -productName)       # macOS
    os_version=$(sw_vers -productVersion) # 11.1
    install_package="brew install"
    ;;
  Linux | GNU*)
    if [[ $(command -v lsb_release) ]]; then
      # 'normal' Linux distributions
      os_name=$(lsb_release -i | awk -F: '{$1=""; gsub(/^[\s\t]+/,"",$2); gsub(/[\s\t]+$/,"",$2); print $2}')    # Ubuntu/Raspbian
      os_version=$(lsb_release -r | awk -F: '{$1=""; gsub(/^[\s\t]+/,"",$2); gsub(/[\s\t]+$/,"",$2); print $2}') # 20.04
    else
      # Synology, QNAP,
      os_name="Linux"
    fi
    [[ -x /bin/apt-cyg ]] && install_package="apt-cyg install"     # Cygwin
    [[ -x /bin/dpkg ]] && install_package="dpkg -i"                # Synology
    [[ -x /opt/bin/ipkg ]] && install_package="ipkg install"       # Synology
    [[ -x /usr/sbin/pkg ]] && install_package="pkg install"        # BSD
    [[ -x /usr/bin/pacman ]] && install_package="pacman -S"        # Arch Linux
    [[ -x /usr/bin/zypper ]] && install_package="zypper install"   # Suse Linux
    [[ -x /usr/bin/emerge ]] && install_package="emerge"           # Gentoo
    [[ -x /usr/bin/yum ]] && install_package="yum install"         # RedHat RHEL/CentOS/Fedora
    [[ -x /usr/bin/apk ]] && install_package="apk add"             # Alpine
    [[ -x /usr/bin/apt-get ]] && install_package="apt-get install" # Debian
    [[ -x /usr/bin/apt ]] && install_package="apt install"         # Ubuntu
    ;;

  esac
  IO:debug "$info_icon System OS  : $os_name ($os_kernel) $os_version on $os_machine"
  IO:debug "$info_icon Package mgt: $install_package"

  # get last modified date of this script
  script_modified="??"
  [[ "$os_kernel" == "Linux" ]] && script_modified=$(stat -c %y "$script_install_path" 2>/dev/null | cut -c1-16) # generic linux
  [[ "$os_kernel" == "Darwin" ]] && script_modified=$(stat -f "%Sm" "$script_install_path" 2>/dev/null)          # for MacOS

  IO:debug "$info_icon Version  : $script_version"
  IO:debug "$info_icon Created  : $script_created"
  IO:debug "$info_icon Modified : $script_modified"

  IO:debug "$info_icon Lines    : $script_lines lines / md5: $script_hash"
  IO:debug "$info_icon User     : $USER@$HOSTNAME"

  # if run inside a git repo, detect for which remote repo it is
  if git status &>/dev/null; then
    git_repo_remote=$(git remote -v | awk '/(fetch)/ {print $2}')
    IO:debug "$info_icon git remote : $git_repo_remote"
    git_repo_root=$(git rev-parse --show-toplevel)
    IO:debug "$info_icon git folder : $git_repo_root"
  fi

  # get script version from VERSION.md file - which is automatically updated by pforret/setver
  [[ -f "$script_install_folder/VERSION.md" ]] && script_version=$(cat "$script_install_folder/VERSION.md")
  # get script version from git tag file - which is automatically updated by pforret/setver
  [[ -n "$git_repo_root" ]] && [[ -n "$(git tag &>/dev/null)" ]] && script_version=$(git tag --sort=version:refname | tail -1)
}

function Script:initialize() {
  log_file=""
  if [[ -n "${tmp_dir:-}" ]]; then
    # clean up tmp_dir folder after 1 day
    Os:folder "$tmp_dir" 1
  fi
  if [[ -n "${log_dir:-}" ]]; then
    # clean up log_dir folder after 30 days
    Os:folder "$log_dir" 30
    log_file="$log_dir/$script_prefix.$execution_day.log"
    IO:debug "$config_icon log_file: $log_file"
  fi
}

function Os:tempfile() {
  local extension=${1:-txt}
  local file="${tmp_dir:-/tmp}/$execution_day.$RANDOM.$extension"
  IO:debug "$config_icon tmp_file: $file"
  temp_files+=("$file")
  echo "$file"
}

function Os:import_env() {
  local env_files
  env_files=(
    "$script_install_folder/.env"
    "$script_install_folder/.$script_prefix.env"
    "$script_install_folder/$script_prefix.env"
    "./.env"
    "./.$script_prefix.env"
    "./$script_prefix.env"
  )

  for env_file in "${env_files[@]}"; do
    if [[ -f "$env_file" ]]; then
      IO:debug "$config_icon Read  dotenv: [$env_file]"
      local clean_file
      clean_file=$(Os:clean_env "$env_file")
      # shellcheck disable=SC1090
      source "$clean_file" && rm "$clean_file"
    fi
  done
}

function Os:clean_env() {
  local input="$1"
  local output="$1.__.sh"
  [[ ! -f "$input" ]] && IO:die "Input file [$input] does not exist"
  IO:debug "$clean_icon Clean dotenv: [$output]"
  awk <"$input" '
      function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
      function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
      function trim(s) { return rtrim(ltrim(s)); }
      /=/ { # skip lines with no equation
        $0=trim($0);
        if(substr($0,1,1) != "#"){ # skip comments
          equal=index($0, "=");
          key=trim(substr($0,1,equal-1));
          val=trim(substr($0,equal+1));
          if(match(val,/^".*"$/) || match(val,/^\047.*\047$/)){
            print key "=" val
          } else {
            print key "=\"" val "\""
          }
        }
      }
  ' >"$output"
  echo "$output"
}

IO:initialize # output settings
Script:meta   # find installation folder

[[ $run_as_root == 1 ]] && [[ $UID -ne 0 ]] && IO:die "user is $USER, MUST be root to run [$script_basename]"
[[ $run_as_root == -1 ]] && [[ $UID -eq 0 ]] && IO:die "user is $USER, CANNOT be root to run [$script_basename]"

Option:initialize # set default values for flags & options
Os:import_env     # overwrite with .env if any

if [[ $sourced -eq 0 ]]; then
  Option:parse "$@" # overwrite with specified options if any
  Script:initialize # clean up folders
  Script:main "$@"  # run Script:main program
  Script:exit       # exit and clean up
else
  # just disable the trap, don't execute Script:main
  trap - INT TERM EXIT
fi
