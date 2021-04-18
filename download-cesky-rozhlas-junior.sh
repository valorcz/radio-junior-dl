#!/bin/bash

# This script requires:
#   * pup
#   * jq
#   * id3tag

mandatoryApps=(pup jq)
optionalApps=(id3tag)


for APP in "${mandatoryApps[@]}"; do
    if ( ! command -v "$APP" >/dev/null 2>&1 ); then
        echo "ERROR: Application $APP not found" >&2
        exit 1
    fi
done

for APP in "${optionalApps[@]}"; do
    if ( ! command -v "$APP" >/dev/null 2>&1 ); then
        echo "WARNING: Application $APP not found, some features will not be provided" >&2
    fi
done

# Just pass an Radio Junior URL
URL="{$1}"

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

# And now process it all
while IFS= read -r line
do
  url="$(echo """${line}"""| jq -r '.href')"
  # Neuter the name a bit, even though it could be better
  name="$(echo """${line}""" | jq -r '.name' | tr ': .' '___')"
  #if the file exists and has a size greater than zero
  if [ -s "${name}.mp3" ]; then
    continue
  fi
  echo "Downloading to ${name}.mp3"
  curl -# "${url}" -o "${name}.mp3"
  id3tag -1 -2 --song="${name}" --desc="${description}" --album='Radio Junior' --genre=101 --artist="Radio Junior" --comment="${URL}" "${name}.mp3"
done < <(printf '%s\n' "${items}")

