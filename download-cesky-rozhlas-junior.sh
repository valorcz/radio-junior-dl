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
outputDirectory='.'
onlyOneTrack=false

function printHelp() {
    echo -n "Awesome super duper overengineered script to download stuff from Cesky Rozhlas Junor
Usage:  $(basename "$0") [OPTs] URLs

    URL -- URLs (space separated) of radio streams to be downloaded
           no param prior this is needed, it's NOT positional

    -h|--help             -- prints this help

    -c|--chars \"$CHARS\" -- replace these chars in filename by \"_\"
                             mp3 tag is not affected
    --debug               -- enables debug output

Needs to have installed:
    * jq 
    * pup ( https://github.com/ericchiang/pup )
Helps to have installed:
    * id3tag

"

}


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
        echo "DEBUG: $*"
    fi
}

function parseArgs() {
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help) printHelp; exit 0; shift;;
            -d|--debug|-v|--verb) DEBUG=true ; shift;;
            -c|--chars) ESCAPECHARS="$2"; shift 2;;
            -t|--total) cmdTotalTracks="$2"; shift 2;;
            -n|--onlyTrack) onlyOneTrack=true; onlyOneTrackID="$2"; shift 2;;
            -of|--output-file) cmdOutputFilename="$2"; shift 2;;
            -od|--output-dir) outputDirectory="$2"; shift 2;;
            #--interactive|-i) INTERACTIVE=true; shift ;;
            *)  URLs="$URLs $1"
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
    if [ "${items}" ]; then
        serial=true
        if [ "$cmdTotalTracks" ]; then
            totalTracks="$cmdTotalTracks"
        else
            totalTracks="$(echo "${content}" | pup --charset utf-8 'div[class="b-041k__metadata"]' json{} | jq -c '.[] | { name:  .children[].text} | select(.name != null)' | awk '{print $(NF-1)}')"
        fi
        if [ "${cmdOutputFilename}" ] && [ ! "${onlyOneTrack}" ]; then
            echo "ERROR: Was set filename on serial -- this is not working, please remove it from CMD" >&2
            exit 1
        fi
    else
        serial=false
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
        if [ "${cmdOutputFilename}" ]; then
            FileName="${cmdOutputFilename}"
        else
            FileName="$(echo """${line}""" | jq -r '.name' | tr -s "$ESCAPECHARS" '_' | sed -e's/^_//g' )"
        fi
        OrigName="$(echo """${line}""" | jq -r '.name' )"
        #if the file exists and has a size greater than zero
        if [ -s "${FileName}.mp3" ]; then
            echo "${FileName} exists, skipping"
            continue
        fi

        if ( "${onlyOneTrack}" ); then
            [[ "${OrigName}" =~ "${onlyOneTrackID}. díl: "* ]] || continue
        fi

        if ( "$serial" ); then
            trackNum="$( echo "${OrigName}" | sed -e's/\. díl:\ .*//g' )"
        else
            trackNum=1
        fi

        echo "Downloading to ${FileName}.mp3"
        curl -# "${url}" -o "${outputDirectory}/${FileName}.mp3"
         ( command -v id3tag ) && id3tag -1 -2 --song="${OrigName}" --desc="${description}" --album='Radio Junior' --genre=101 --artist="Radio Junior" --total="$totalTracks"  --track="${trackNum}" --comment="${URL}" "${outputDirectory}/${FileName}.mp3"
         
    done < <(printf '%s\n' "${items}")
}


function main() {
    parseArgs "$@"
    verifyFunctions "true"  "${mandatoryApps[@]}"
    verifyFunctions "false" "${optionalApps[@]}"
    
    for URL in $URLs; do
        items=''
        description=''
        serial=false
        [ "$cmdTotalTracks" ] || totalTracks=1
        fillValues
        doDownload
    done
}

main "$@"
