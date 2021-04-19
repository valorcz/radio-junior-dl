#!/bin/bash

# This script requires:
#   * pup
#   * jq
#   * id3tag

mandatoryApps=(pup jq)
optionalApps=(id3tag)



################################
#
# Widely used vars, list it here
# as it'd default values
#
################################
URL=''
DEBUG=false
#INTERACTIVE=false
ESCAPECHARS="!?. ;:"

function verifyFunctions() {
    local MANDATORY="$1"
    shift
    appList=("$@")
    for APP in "${appList[@]}"; do
        if ( ! command -v "$APP" >/dev/null 2>&1 ); then
            if ( $MANDATORY ); then
                echo "ERROR: Application $APP not found" >&2
                exit 1
            else
                echo "WARNING: Application $APP not found, some features will not be provided" >&2
            fi
        fi
    done
}

function debugPrint() {
    if ( $DEBUG ); then
        echo "$@"
    fi
}

function parseArgs() {
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help) printHelp; exit; shift;;
            -d|--debug|-v|--verb) DEBUG=true ; shift;;
            -c|--chars) ESCAPECHARS="$2"; shift 2;;
            #--interactive|-i) INTERACTIVE=true; shift ;;
            *)  if [ $# -gt 1 ]; then
                    echo "$0: error - unrecognized option $1. Use -h for help." >&2;
                    exit 1
                else
                    URL="$1"
                fi 
                shift
                ;;
        esac
    done
}

function fillValues() {
    # This ugly thing will turn the HTML page into an array of URLs & episode names
    content=$( curl -s "${URL}" )
    items=$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .children[].children[].text }' 2>/dev/null )
    item=$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .text }' 2>/dev/null )
    description="$( echo "${content}" | pup --charset utf-8  'meta[name="description"]' json{} | jq -c '.[] | .content' )"

    # If items are empty, we may be downloading from a page with a single file
    if [ -z "${items}" ]; then
        items="${item}"
    fi

    # If still empty, something is wrong
    if [ -z "${items}" ]; then
      echo "Nothing found; the script probably needs to be fixed." >&2
      exit
    fi
}

function doDownload() {
    while IFS= read -r line
    do
        url="$(echo """${line}"""| jq -r '.href')"
        # Neuter the name a bit, even though it could be better
        name="$(echo """${line}""" | jq -r '.name' | tr -s "$ESCAPECHARS" '_' | sed -e's/^_//g' )"
        clearName="$(echo """${line}""" | jq -r '.name' )"
        #if the file exists and has a size greater than zero
        if [ -s "${name}.mp3" ]; then
            echo "${name} exists, skipping"
            continue
        fi
        echo "Downloading to ${name}.mp3"
        curl -# "${url}" -o "${name}.mp3"
        id3tag -1 -2 --song="${clearName}" --desc="${description}" --album='Radio Junior' --genre=101 --artist="Radio Junior" --comment="${URL}" "${name}.mp3"
    done < <(printf '%s\n' "${items}")
}


function main() {
    parseArgs "$@"
    verifyFunctions "true"  "${mandatoryApps[@]}"
    verifyFunctions "false" "${optionalApps[@]}"
    
    items=''
    description=''
    fillValues

    doDownload
}

main "$@"
