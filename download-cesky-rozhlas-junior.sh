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
EnableCron=false
MKDIR=false

function printHelp() {
    echo -n "Awesome super duper overengineered script to download stuff from Cesky Rozhlas Junor
Usage:  $(basename "$0") [OPTs] URLs

    URL -- URLs (space separated) of radio streams to be downloaded
           no param prior this is needed, it's NOT positional

    -h|--help           prints this help

    -t|--total          If serial and total number of parts was not 
                        determined properly OR for some reason you can 
                        overwrite the automatically determined number
    -n|--onlyTrack      If serial, download ONLY track number n
    -of|--output-file   Set output file name. Will NOT work with multiple
                        URLs nor if the requested is serial
    -od|--output-dir    PATH where to store downloaded file(s)
                        Will NOT create directory by default
    --mkdir             if output directory does not exists, will try to
                        create one

    --cron              Enable cron run. If enabled -od is mandatory, 
                        serials will be in output-dir/serial_name/


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
            --mkdir) MKDIR=true ; shift;;
            -c|--chars) ESCAPECHARS="$2"; shift 2;;
            -t|--total) cmdTotalTracks="$2"; shift 2;;
            -n|--onlyTrack) onlyOneTrack=true; onlyOneTrackID="$2"; shift 2;;
            -of|--output-file) cmdOutputFilename="$2"; shift 2;;
            -od|--output-dir) outputDirectory="$2"; shift 2;;
            --cron) EnableCron=true; MKDIR=true; shift;;
            #--interactive|-i) INTERACTIVE=true; shift ;;
            *)  URLs="$URLs $1"
                shift
                ;;
        esac
    done
}

function fillValues() {
    # This ugly thing will turn the HTML page into an array of URLs & episode names
    content="$( curl -s "${URL}" )"
    items="$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .children[].children[].text }' 2>/dev/null )"
    item="$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .text }' 2>/dev/null )"
    title="$(echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { title: .children[].title }' 2>/dev/null |  jq -c -r '.title'_2>/dev/null )"
    [ "$title" ] || title="$(echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { title: .text }' |  jq -c -r '.title' 2>/dev/null )"
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

        #~ if ( $EnableCron ); then
            #~ origOD="${outputDirectory}"
            #~ outputDirectory="${outputDirectory}"/"${title}"
        #~ fi

        if [ ! -d "${outputDirectory}" ]; then
            if ( "${MKDIR}" ); then
                
                if ( ! mkdir -p "${outputDirectory}"); then
                    echo "Create of ${outputDirectory} failed, please run manually 'mkdir -p ${outputDirectory}' and investigate"
                    exit 11
                fi
            else
                echo "Directory ${outputDirectory} does not exists, use --mkdir to create or create before"
                exit 12
            fi
        fi

        if [ -s "${outputDirectory}/${FileName}.mp3" ]; then
            echo "${outputDirectory}/${FileName} exists, skipping"
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
        
        echo "Downloading to ${outputDirectory}/${FileName}.mp3"
        curl -# "${url}" -o "${outputDirectory}/${FileName}.mp3"
        ( command -v id3tag ) && id3tag -1 -2 --song="${OrigName}" --desc="${description}" --album='Radio Junior' --genre=101 --artist="Radio Junior" --total="$totalTracks"  --track="${trackNum}" --comment="${URL}" "${outputDirectory}/${FileName}.mp3"
        #~ if ( $EnableCron ); then
            #~ outputDirectory="${origOD}"
        #~ fi 
    done < <(printf '%s\n' "${items}")
}

function downloadURLlist() {

    while IFS= read -r line; do
        url="$(echo """${line}"""| jq -r '.href')"
        URLs="$URLs https://junior.rozhlas.cz/$url"
        #echo "$URLs"
    done < <( curl -s "https://junior.rozhlas.cz/pribehy" | pup --charset utf-8 'div[class="b-008d__subblock--content"] a json{}' | jq -c '.[] | { href: .href,name: .text} | select(.name != null)' )

}


function main() {
    parseArgs "$@"
    verifyFunctions "true"  "${mandatoryApps[@]}"
    verifyFunctions "false" "${optionalApps[@]}"

    if ( "$EnableCron" ); then
        #-od needs to be passed in
        if [ "${outputDirectory}" == "." ]; then
            echo "Output directory needs to be passed in with --cron option"
            exit 3
        fi
        downloadURLlist
    fi

    for URL in $URLs; do
        items=''
        description=''
        title=''
        serial=false
        [ "$cmdTotalTracks" ] || totalTracks=1
        fillValues
        doDownload
    done
}

main "$@"
