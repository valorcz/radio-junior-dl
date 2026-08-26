#!/bin/bash

# This script requires:
#   * pup
#   * jq
#   * yt-dlp

mandatoryApps=(pup jq yt-dlp curl)
optionalApps=(iconv)

################################
#
# Widely used vars, list it here
# as it'd default values
#
################################
URLs=()
URL=''
DEBUG=false
ESCAPECHARS="!?. ;:"
outputDirectory='.'
onlyOneTrack=false
onlyOneTrackID=''
EnableCron=false
MKDIR=false
TRANSFORM=true
IGNORELIST="$HOME/.config/radiojunior/skip.list"
cmdTotalTracks=''
cmdOutputFilename=''

function printHelp() {
  echo -n "Awesome super duper overengineered script to download stuff from Cesky Rozhlas Junior
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
                        are worthy to download/listen more than once).
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

    -c|--chars \"\$CHARS\" -- replace these chars in filename by \"_\"
                             mp3 tag is not affected
    -d|--debug          -- enables debug output

Needs to have installed:
    * curl
    * jq 
    * pup (https://github.com/ericchiang/pup)
    * yt-dlp
Helps to have installed:
    * iconv

"
}

function verifyFunctions() {
  local MANDATORY="$1"
  shift
  local appList=("$@")
  for APP in "${appList[@]}"; do
    if ! command -v "$APP" >/dev/null 2>&1; then
      if [[ "$MANDATORY" == "true" ]]; then
        echo "ERROR: Application $APP not found" >&2
        exit 1
      else
        echo "WARNING: Application $APP not found, some features will not be provided" >&2
      fi
    fi
  done
}

function debugPrint() {
  if [[ "$DEBUG" == true ]]; then
    echo "DEBUG: $*"
  fi
}

function parseArgs() {
  while [ $# -gt 0 ]; do
    case $1 in
    -h | --help)
      printHelp
      exit 0
      ;;
    -d | --debug | -v | --verb)
      DEBUG=true
      shift
      ;;
    -ntr | --not-transform)
      TRANSFORM=false
      shift
      ;;
    --mkdir)
      MKDIR=true
      shift
      ;;
    -c | --chars)
      ESCAPECHARS="$2"
      shift 2
      ;;
    -i | --ignore)
      IGNORELIST="$2"
      shift 2
      ;;
    -t | --total)
      cmdTotalTracks="$2"
      shift 2
      ;;
    -n | --onlyTrack)
      onlyOneTrack=true
      onlyOneTrackID="$2"
      shift 2
      ;;
    -of | --output-file)
      cmdOutputFilename="$2"
      shift 2
      ;;
    -od | --output-dir)
      outputDirectory="$2"
      shift 2
      ;;
    --cron)
      EnableCron=true
      MKDIR=true
      shift
      ;;
    *)
      URLs+=("$1")
      shift
      ;;
    esac
  done

  local ignoreDir
  ignoreDir="$(dirname "$IGNORELIST")"
  if [ ! -d "$ignoreDir" ]; then
    mkdir -p "$ignoreDir"
  fi
  if [ ! -f "$IGNORELIST" ]; then
    touch "$IGNORELIST"
  fi
}

function fillValues() {
  local targetURL="$1"
  debugPrint "Processing $targetURL"

  local rawContent
  rawContent="$(curl -s "${targetURL}")"

  if command -v iconv >/dev/null 2>&1 && [[ "$TRANSFORM" == true ]] && [ "$(uname -s)" != "Darwin" ]; then
    content="$(echo "${rawContent}" | iconv -f UTF8 -t US-ASCII//TRANSLIT 2>/dev/null)"
  else
    content="${rawContent}"
    if [[ "$TRANSFORM" == true ]] && ! command -v iconv >/dev/null 2>&1; then
      debugPrint "iconv not found, not transforming"
    fi
  fi

  # Extract the JSON powering the audio player of Cesky rozhlas
  content_json="$(echo "${content}" | pup --charset utf-8 -p -i 4 'div.mujRozhlasPlayer attr{data-player}')"

  # Check if it contains a valid JSON
  if [ -z "${content_json}" ] || ! jq -e . >/dev/null 2>&1 <<<"${content_json}"; then
    debugPrint "Failed to parse JSON, or got false/null from player"
  fi

  # Populate metadata
  items="$(echo "${content_json}" | jq -c '.data.playlist[]? | { href: .audioLinks[]?.url, name: .title }' 2>/dev/null)"
  description="$(echo "${content_json}" | jq -rc '.data.series.title // empty' 2>/dev/null)"
  title="$(echo "${content_json}" | jq -rc '.data.playlist[]?.meta.ga.contentNameShort // empty' 2>/dev/null | sort -u)"
  creator="$(echo "${content_json}" | jq -rc '.data.playlist[]?.meta.ga.contentCreator // empty' 2>/dev/null | sort -u)"
  album="${description}"
  if [ -z "$album" ]; then
    album="$title"
  fi

  # Debug info
  debugPrint "title=$title"
  debugPrint "items=$items"
  debugPrint "album=$album"
  debugPrint "creator=$creator"

  if [ -n "${items}" ]; then
    serial=true
    if [ -n "$cmdTotalTracks" ]; then
      totalTracks="$cmdTotalTracks"
    else
      totalTracks="$(echo "${content_json}" | jq -rc '.data.series.totalParts // 1' 2>/dev/null)"
    fi
    if [ -n "${cmdOutputFilename}" ] && [[ "$onlyOneTrack" != true ]]; then
      echo "ERROR: Was set filename on serial -- this is not working, please remove it from CMD" >&2
      exit 1
    fi
  else
    serial=false
    totalTracks=1
  fi
  debugPrint "totalTracks=$totalTracks"
  debugPrint "serial=$serial"

  if [ -z "${items}" ]; then
    echo "Nothing found; the script probably needs to be fixed." >&2
    return 1
  fi
  return 0
}

function doDownload() {
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local url
    url="$(echo "${line}" | jq -r '.href')"
    local OrigName
    OrigName="$(echo "${line}" | jq -r '.name')"

    local FileName
    if [ -n "${cmdOutputFilename}" ]; then
      FileName="${cmdOutputFilename}"
    else
      FileName="$(echo "${OrigName}" | tr -s "$ESCAPECHARS" '_' | tr -s '@' 'a' | sed -e 's/^_//g' -e 's/_$//g')"
    fi

    local shouldSkip=false
    for IgnoreItem in "$URL" "$FileName" "$OrigName"; do
      if matchIgnore "$IgnoreItem"; then
        shouldSkip=true
        break
      fi
    done
    if [[ "$shouldSkip" == true ]]; then
      continue
    fi

    local targetDir="${outputDirectory}"
    if [[ "$EnableCron" == true ]]; then
      debugPrint "Serial + Cron detected, changing path"
      local albumSubdir
      albumSubdir="$(echo "${album}" | tr -s "$ESCAPECHARS" '_' | tr '@' 'a' | sed -e 's/^_//g' -e 's/_$//g')"
      if [ -n "$albumSubdir" ]; then
        targetDir="${outputDirectory}/${albumSubdir}"
      fi
      debugPrint "targetDir=$targetDir"
    fi

    if [ ! -d "${targetDir}" ]; then
      if [[ "$MKDIR" == true ]]; then
        if ! mkdir -p "${targetDir}"; then
          echo "Create of ${targetDir} failed, please run manually 'mkdir -p ${targetDir}' and investigate" >&2
          exit 11
        fi
      else
        echo "Directory ${targetDir} does not exists, use --mkdir to create or create before" >&2
        exit 12
      fi
    fi

    local fileExists=false
    for existingFile in "${targetDir}/${FileName}".*; do
      if [ -s "$existingFile" ]; then
        fileExists=true
        break
      fi
    done
    if [[ "$fileExists" == true ]]; then
      if [[ "$EnableCron" != true ]]; then
        echo "${targetDir}/${FileName} exists, skipping"
      fi
      continue
    fi

    if [[ "$onlyOneTrack" == true ]]; then
      if [[ ! "${OrigName}" =~ ^${onlyOneTrackID}\.\ díl: ]] && [[ ! "${OrigName}" =~ ^0*${onlyOneTrackID}\. ]]; then
        continue
      fi
    fi

    if [[ "$serial" == true ]]; then
      trackNum="$(echo "${OrigName}" | sed -e 's/\. díl:\ .*//g')"
    else
      trackNum=1
    fi
    debugPrint "trackNum=$trackNum"

    if [[ "$EnableCron" != true ]]; then
      echo "Downloading to ${targetDir}/${FileName}.m4a"
    fi

    yt-dlp "${url}" -o "${targetDir}/${FileName}.%(ext)s"
  done < <(printf '%s\n' "${items}")
}

function downloadURLlist() {
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local url
    url="$(echo "${line}" | jq -r '.href')"
    if [ -n "$url" ] && [ "$url" != "null" ]; then
      URLs+=("https://junior.rozhlas.cz/${url#/}")
    fi
  done < <(curl -s "https://junior.rozhlas.cz/pribehy" | pup --charset utf-8 'div[class="b-008d__subblock--content"] a json{}' | jq -c '.[] | { href: .href, name: .text } | select(.name != null)')
}

function matchIgnore() {
  local STRING="$1"
  [ -s "${IGNORELIST}" ] || return 1
  while IFS= read -r MATCH; do
    [[ -z "$MATCH" || "$MATCH" =~ ^[[:space:]]*# ]] && continue
    if [[ "${STRING}" =~ ${MATCH} ]]; then
      echo "WARNING: $STRING is matched by $MATCH from ignorelist $IGNORELIST"
      echo -e "         URL: $URL will be skipped\n"
      return 0
    fi
  done <"${IGNORELIST}"
  return 1
}

function main() {
  parseArgs "$@"
  verifyFunctions "true" "${mandatoryApps[@]}"
  verifyFunctions "false" "${optionalApps[@]}"

  if [[ "$EnableCron" == true ]]; then
    if [ "${outputDirectory}" == "." ]; then
      echo "Output directory needs to be passed in with --cron option" >&2
      exit 3
    fi
    downloadURLlist
  fi

  for URL in "${URLs[@]}"; do
    items=''
    description=''
    title=''
    album=''
    creator=''
    serial=false
    [ -n "$cmdTotalTracks" ] || totalTracks=1
    if fillValues "$URL"; then
      doDownload
    fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
