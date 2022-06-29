#!/bin/bash

# This script requires:
#   * pup
#   * jq
#   * id3tag

mandatoryApps=(pup jq )
optionalApps=(id3tag iconv)



################################
#
# Widely used vars, list it here
# as it'd default values
#
################################
URL=''
DEBUG=false
ESCAPECHARS="!?. ;:"
outputDirectory='.'
onlyOneTrack=false
EnableCron=false
MKDIR=false
DOWNLOADTAG='-#'
TRANSFORM=true
IGNORELIST="$HOME/.config/radiojunior/skip.list"

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
    -ntr|--not-transform   Do NOT transform and keep non-ascii chars
                        Default on MacOS

    -i|--ignore         File (path) with files to skip (not all stories
                        are worthy to download/listen more then once.
                        You can either:
                        * URL or it's part of page with story 
                            (to be found in description tag)
                        * Name of the file (after transformations)
                        This is matched as parts, beware however of too 
                        generic part (ie matching 'junior' will just cause
                        nothing will be downloaded).
                        One match per line
                        The default is ~/.config/radiojunior/skip.list

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
            -ntr|--not-transform) TRANSFORM=false ; shift;;
            --mkdir) MKDIR=true ; shift;;
            -c|--chars) ESCAPECHARS="$2"; shift 2;;
            -i|--ignore) IGNORELIST="$2";  shift 2;;
            -t|--total) cmdTotalTracks="$2"; shift 2;;
            -n|--onlyTrack) onlyOneTrack=true; onlyOneTrackID="$2"; shift 2;;
            -of|--output-file) cmdOutputFilename="$2"; shift 2;;
            -od|--output-dir) outputDirectory="$2"; shift 2;;
            --cron) EnableCron=true; DOWNLOADTAG="-s"; MKDIR=true; shift;;
            *)  URLs="$URLs $1"
                shift
                ;;
        esac
    done
    ( "${DEBUG}" ) && DOWNLOADTAG="-#"

    if [ ! -f "$IGNORELIST" ]; then 
        echo "WARNING: Ignore list was not found, using and setting default to $HOME/.config/radiojunior/skip.list" >&2 ;
        IGNORELIST="$HOME/.config/radiojunior/skip.list"
    fi
    
    
    
    [ -d "$(dirname "$IGNORELIST")" ] || mkdir -p "$(dirname "$IGNORELIST")"
    [ -f "$IGNORELIST" ] || touch "$IGNORELIST"
    
}

function fillValuesNew() {
    # This ugly thing will turn the HTML page into an array of URLs & episode names
    debugPrint "Processing $URL in a new way"
    if ( command -v "$APP" >/dev/null 2>&1 ) && ( "${TRANSFORM}" ) && [ "$(uname -s)" != "Darwin" ]; then
        content="$( curl -s "${URL}" | iconv -f UTF8 -t US-ASCII//TRANSLIT 2>/dev/null )"
    else
        content="$( curl -s "${URL}" )"
        debugPrint "Iconv not found, not transforming"
    fi

    content_json="$( echo "${content}" | pup --charset utf-8 -p -i 4 'div.mujRozhlasPlayer attr{data-player}' )"
   # TODO: Check if it contains a valid JSON

    items="$( echo "${content_json}" | jq -c '.data.playlist[] | { href: .audioLinks[].url, name: .title }' 2>/dev/null )"
    description="$( echo "${content_json}" | jq -c '.data.series.title' )"
    title="$( echo "${content_json}" | jq -c '.meta.ga.contentNameShort' )"

    debugPrint "title=$title"  
    debugPrint "item=$item"  
    debugPrint "items=$items"  
    debugPrint "album=\"$album\""  
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
    debugPrint "totalTracks=$totalTracks"
    debugPrint "serial: $serial"

    # If still empty, something is wrong
    if [ -z "${items}" ]; then
      echo "Nothing found; the script probably needs to be fixed." >&2
      return 
    fi
}

function fillValues() {
    # This ugly thing will turn the HTML page into an array of URLs & episode names
    debugPrint "Processing $URL"
    if ( command -v "$APP" >/dev/null 2>&1 ) && ( "${TRANSFORM}" ) && [ "$(uname -s)" != "Darwin" ]; then
        content="$( curl -s "${URL}" | iconv -f UTF8 -t US-ASCII//TRANSLIT 2>/dev/null )"
    else
        content="$( curl -s "${URL}" )"
        debugPrint "Iconv not found, not transforming"
    fi
    items="$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .children[].children[].text }' 2>/dev/null )"
    item="$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .text }' 2>/dev/null )"
    title="$(echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { title: .children[].title }' 2>/dev/null |  jq -c -r '.title' 2>/dev/null | cut -d':' -f1 | head -1 )"
    album="$(echo "${content}" | pup --charset utf-8 'meta[name=twitter:title] json{}' | jq -c '.[] | { album: .content }' | jq -c -r '.album' 2>/dev/null | awk -F'[|.]*' '{print $1}' | sed -e's/[[:space:]]$//g' )"
    [ "$title" ] || title="$(echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { title: .text }' |  jq -c -r '.title' 2>/dev/null  | cut -d':' -f1 | head -1 )"
    description="$( echo "${content}" | pup --charset utf-8  'meta[name="description"]' json{} | jq -c '.[] | .content' )"
    debugPrint "title=$title"  
    debugPrint "item=$item"  
    debugPrint "items=$items"  
    debugPrint "album=\"$album\""  
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
    debugPrint "totalTracks=$totalTracks"
    debugPrint "serial: $serial"

    # If still empty, something is wrong
    if [ -z "${items}" ]; then
      echo "Nothing found; the script probably needs to be fixed." >&2
      return 
    fi
}

function doDownload() {
    while IFS= read -r line
    do
  #  echo $line
        url="$(echo """${line}"""| jq -r '.href')"
        # Neuter the name a bit, even though it could be better
        if [ "${cmdOutputFilename}" ]; then
            FileName="${cmdOutputFilename}"
        else
            FileName="$(echo """${line}""" | jq -r '.name' | tr -s "$ESCAPECHARS" '_' | tr -s '@' 'a' | sed -e's/^_//g' )"
        fi
        OrigName="$(echo """${line}""" | jq -r '.name' )"
        #if the file exists and has a size greater than zero
        for IgnoreItem in "$URL" "$FileName" "$OrigName"; do
            ( matchIgnore "$IgnoreItem" ) || continue
        done
        if ( $EnableCron ); then
            debugPrint "Serial + Cron detected, changing path"
            origOD="${outputDirectory}"
            outputDirectory="${outputDirectory}"/"$( echo "${album}" | tr -s "$ESCAPECHARS" '_' | tr '@' 'a' | sed -e's/^_//g' )"
            debugPrint "origOD=$origOD"
            debugPrint "outputDirectory=$outputDirectory"
        fi

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
            ( "${EnableCron}" ) || echo "${outputDirectory}/${FileName} exists, skipping"
            if ( "${EnableCron}" ); then
                debugPrint "Reverting path updating"
                outputDirectory="${origOD}"
                debugPrint "outputDirectory=$outputDirectory"
            fi
            continue
        fi


        if ( "${onlyOneTrack}" ); then
            if [[ ! "${OrigName}" =~ "${onlyOneTrackID}. díl: "* ]] ; then
                if ( "${EnableCron}" ); then
                    debugPrint "Reverting path updating"
                    outputDirectory="${origOD}"
                    debugPrint "outputDirectory=$outputDirectory"
                fi
                continue
            fi
        fi

        if ( "$serial" ); then
            trackNum="$( echo "${OrigName}" | sed -e's/\. díl:\ .*//g' )"
        else
            trackNum=1
        fi
        debugPrint "trackNum=$trackNum"

        ( "${EnableCron}" ) || echo "Downloading to ${outputDirectory}/${FileName}.mp3"
        curl "$DOWNLOADTAG" "${url}" -o "${outputDirectory}/${FileName}.mp3"
        TMPFILE="$(mktemp)"
        ( command -v id3tag >/dev/null 2>&1) && id3tag -1 -2 --song="${OrigName}" --comment="${description}" --album="${album}" --genre=101 --artist="Radio Junior" --total="$totalTracks"  --track="${trackNum}" --desc="${URL}" "${outputDirectory}/${FileName}.mp3" > "${TMPFILE}"
        ( "${EnableCron}" ) || cat "${TMPFILE}"
        rm -f "${TMPFILE}"
        if ( "${EnableCron}" ); then
            debugPrint "Reverting path updating"
            outputDirectory="${origOD}"
            debugPrint "outputDirectory=$outputDirectory"
        fi
    done < <(printf '%s\n' "${items}")
}

function downloadURLlist() {

    while IFS= read -r line; do
        url="$(echo """${line}"""| jq -r '.href')"
        URLs="$URLs https://junior.rozhlas.cz/$url"
#echo "$URLs"
    done < <( curl -s "https://junior.rozhlas.cz/pribehy" | pup --charset utf-8 'div[class="b-008d__subblock--content"] a json{}' | jq -c '.[] | { href: .href,name: .text} | select(.name != null)' )

}

function matchIgnore() {
    STRING="$1"
    [ -s "${IGNORELIST}" ] || return
    while read -r MATCH; do
        if [[ "${STRING}" =~ ${MATCH} ]]; then
            echo "WARNING: $STRING is matched by $MATCH from ignorelist $IGNORELIST"
            echo -e "         URL: $URL will be skipped\n"
            # 1=false
            return 1
        fi
    done < <( sed -e'/^$/d' "${IGNORELIST}" )
    true
    return
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
        #( matchIgnore "$URL" ) || continue
        items=''
        description=''
        title=''
        serial=false
        [ "$cmdTotalTracks" ] || totalTracks=1
        fillValuesNew
        doDownload
    done
}

main "$@"
