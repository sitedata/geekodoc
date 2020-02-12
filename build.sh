#!/bin/bash
#
# Copyright 2020 SUSE Linux GmbH
#
# Dependencies
#  Our main file is geekodoc-v?.rnc. It depends on:
#    * transclusion.rnc
#      a failed attempt to work with transclusions; can be probably removed
#    * its.rnc
#      integration of ITS 2.0 markup, see http://www.w3.org/TR/its20/
#    * docbook.rnc
#      the upstream schema file
#
# Process Flow
#  geekodoc-v?.rnc # (1)
#  +--> geekodoc-v?.rng #(2)
#       +--> geekodoc-v?-flat.rni # (3)
#            +--> geekodoc-v?-flat.rng # (4)
#                 +--> geekodoc-v?-flat.rnc # (5)
#
# (1) This is our main file; all changes go here
# (2) We need to create the XML format (RNG) first to process it with
#     our XML tools
# (3) The flat.rni file contains the "raw" representation of the
#     schema in one file; it is an intermediate file and is automatically
#     removed
# (4) Apply cleanups to flat.rni to create flat.rng
# (5) The end result, which can be used independently from DocBook or Geekodoc
#     source files
#
# Author: Thomas Schraitle
# Date:  Feb. 2020

# --- color codes
RED="\e[1;31m"
# VIOLET="\e[35m"
# BLUE="\e[94m"
YELLOW="\e[93m"
CYAN="\e[36m"
# GRAY="\e[37m"

BOLD="\e[1m"
# NORMAL=""
# REVERSE="\e[8m"
RESET="\e[0m"

# --- Global variables
ME="${0##*/}"
VERBOSITY=0
LOGGING_LEVEL="DEBUG"
declare -A LOGLEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
declare -A LEVEL2LOG=([0]="ERROR" [1]="WARN" [2]="INFO" [3]="DEBUG")
declare -A LOGCOLORS=([DEBUG]=$CYAN [INFO]=$BOLD [WARN]=$YELLOW [ERROR]=$RED)

# -- Paths
DOCBOOKXI_URI="http://www.oasis-open.org/docbook/xml/5.1/rng/docbookxi.rnc"
DOCBOOKXI_RNC_PATH="/usr/share/xml/docbook/schema/rng/5.1/docbookxi.rnc"
GEEKODOC_DIR="geekodoc"
GEEKODOC_RNG_DIR=${GEEKODOC_DIR}/rng
GEEKODOC1_PATH=${GEEKODOC_RNG_DIR}/5.1_1
GEEKODOC2_PATH=${GEEKODOC_RNG_DIR}/5.1_2
# XSLT_DIR=${GEEKODOC_DIR}/xsl
BUILD_DIR="build"

# === Naming
# The naming was unfortunate, so geekodoc5 version 1 refers to DocBook5,
# not Geekodoc v5;
# we'll provide a compatibility link from geekodoc-v1 -> geekodoc5
GEEKODOC1_NAME="geekodoc-v1"
GEEKODOC2_NAME="geekodoc-v2"


# -- Functions
function logger() {
    local log_priority="$1"
    local msg="$2"
    local color

    #check if level exists
    [[ ${LOGLEVELS[$log_priority]} ]] || return 1

    #check if level is enough
    (( ${LOGLEVELS[$log_priority]} < ${LOGLEVELS[$LOGGING_LEVEL]} )) && return 2

    color=${LOGCOLORS[$log_priority]}

    #log here
    echo -e "${color}${log_priority}:${RESET} ${msg}"
}

function logdebug {
    logger "DEBUG" "$1"
}

function loginfo {
    logger "INFO" "$1"
}

function logwarn {
    logger "WARN" "$1"
}

function logerror {
    logger "ERROR" "$1"
}

function exit_on_error {
    logerror "$1" >&2
    exit 1;
}

# Include some OS specific variables:
source /etc/os-release || exit_on_error "File /etc/os-release not found"


function usage {
    cat << EOF
Build Geekodoc

SYNOPSIS
  $ME -h|--help
  $ME [OPTIONS]

OPTIONS
  -v, -vv, -vvv   Log level, the more you add, the more messages
                  you get. Restricted to -vvv (=DEBUG)
  -b DIR, --builddir=DIR
                  Set the directory where to build (default: ".build")
                  HINT:
                  If the given directory already exists, it's renamed
                  with the "old" command.
EOF
}

function requires {
    loginfo "Check requirements..."
# * trang
# * python3-rnginline (from obs://devel:languages:python/python3-rnginline)
# * docbook_5 (from obs://Publishing)
    local SCRIPTS="trang rnginline"
    local res

    for script in $SCRIPTS; do
        res=$(command -v "$script" )
        if [ 1 -eq "$?" ]; then
            exit_on_error "'$script' not found."
        else
           logdebug "$res found"
        fi
    done
    loginfo "All requirements are ok."
}

function get_docbook5_path {
    local path
    local res
    loginfo "Retrieve XML catalog entry..."

    path=$(xmlcatalog /etc/xml/catalog "$DOCBOOKXI_URI")
    res=$?
    logdebug "Detected OS '$ID'..."

    if [ 0 -gt "$res" ]; then
        # error, could not be found, so fall back
        case $ID in
          opensuse*|sle*)
            path="/usr/share/xml/docbook/schema/rng/5.1/docbookxi.rnc"
            ;;
          debian*|ubuntu*)
            path="/usr/share/xml/docbook/schema/rng/5.1/docbookxi.rnc"
            ;;
          fedora|redhat*)
            path="/usr/share/xml/docbook5/schema/rng/5.1/docbookxi.rnc"
            ;;
          *)
            exit_on_error "Couldn't find OS $ID..."
            ;;
        esac
        DOCBOOKXI_URI="$path"
        logdebug "Use $path"
    else
        # success, use the result, but cut off the "file://" schema
        path="${path#file://*}"
    fi
    logdebug "Use '$path' path for DocBook5"
}

function create_build_env {
    loginfo "Create build environment..."
    # Dir structure
    if [[ -n $BUILD_DIR ]] && [[ -d $BUILD_DIR ]]; then
       rm -rf $BUILD_DIR 2>/dev/null
    fi
    mkdir -p $BUILD_DIR
    [[ -d $BUILD_DIR/$GEEKODOC1_PATH ]] || mkdir -p $BUILD_DIR/$GEEKODOC1_PATH
    [[ -d $BUILD_DIR/$GEEKODOC2_PATH ]] || mkdir -p $BUILD_DIR/$GEEKODOC2_PATH

    cp $GEEKODOC1_PATH/*.rnc $BUILD_DIR/$GEEKODOC1_PATH
    cp $GEEKODOC2_PATH/*.rnc $BUILD_DIR/$GEEKODOC2_PATH
    # Copy DocBook5 schema:
    cp $DOCBOOKXI_RNC_PATH $BUILD_DIR/$GEEKODOC1_PATH
    cp $DOCBOOKXI_RNC_PATH $BUILD_DIR/$GEEKODOC2_PATH
    logdebug "Build environment created."
}

function rnc_to_rng {
    local files="$1"

    loginfo "Convert RNC -> RNG..."
    for f in $files; do
       rnc="$f.rnc"
       rng="$f.rng"
       logdebug "Converting $rnc -> $rng"
       trang "$rnc" "$rng"
    done
}

function make_flat {
    local files="$1"

    loginfo "Convert RNG -> RNI (flatten)..."
    for f in $files; do
      rng="$f.rng"
      rni="$f-flat.rni"
      logdebug "Converting $rng -> $rni"
      rnginline "$rng" "$rni"
    done
}


function cleanup_xml {
    local files="$1"

    loginfo "Cleanup flat RNI..."
    for f in $files; do
      rng="$f-flat.rng"
      rni="$f-flat.rni"
      logdebug "Cleanup $rni -> $rng"
      xmllint -o "$rng" --nsclean --format "$rni"
    done
}

function rngflat_to_rnc {
    local files="$1"

    loginfo "Convert flat RNG -> flat RNC..."
    for f in $files; do
      rng="$f-flat.rng"
      rnc="$f-flat.rnc"
      logdebug "Cleanup $rng -> $rnc"
      trang "$rng" "$rnc"
    done
}

function copy_flat_rnc {
    local files="$1"

    loginfo "Copy flat RNC files..."
    for f in $files; do
        rnc="$f-flat.rnc"
        target="${f#$BUILD_DIR/}"
        target="${target%/*}"
        logdebug "Copy $rnc -> $target"
        sed -i 's/[[:blank:]]*$//' "$rnc"
        cp "$rnc" "$target"
    done
}

# -- CLI parsing
ARGS=$(getopt -o h,:v,b: -l help,builddir: -n "$ME" -- "$@")
eval set -- "$ARGS"
while true; do
  case "$1" in
    --help|-h)
        usage
        exit 0
        shift
        ;;
    -b|--builddir)
        BUILD_DIR="$2"
        shift 2
        ;;
    -v)
        VERBOSITY=$((VERBOSITY+1))
        shift
        ;;
    --) shift ; break ;;
    *) exit_on_error "Wrong parameter: $1" ;;
  esac
done

# Fall back to 3 (=DEBUG) if we got more than 4
[[ $VERBOSITY -ge 3 ]] && VERBOSITY=3
LOGGING_LEVEL=${LEVEL2LOG[$VERBOSITY]}

# -- Process
files="$BUILD_DIR/$GEEKODOC1_PATH/$GEEKODOC1_NAME \
       $BUILD_DIR/$GEEKODOC2_PATH/$GEEKODOC2_NAME"
requires "$files"
get_docbook5_path
create_build_env "$files"
rnc_to_rng "$files"
make_flat "$files"
cleanup_xml "$files"
rngflat_to_rnc "$files"
copy_flat_rnc "$files"

loginfo "Finished."
