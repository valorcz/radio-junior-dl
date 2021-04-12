#!/bin/bash

# This script requires:
#   * pup
#   * jq

# Just pass an Radio Junior URL
URL="{$1}"
GOEXECDIR="$(go env GOPATH)"
PATH=$PATH:$GOEXECDIR/bin

# This ugly thing will turn the HTML page into an array of URLs & episode names
content=$( curl -s "${URL}" )
items=$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .children[].children[].text }' 2>/dev/null )
item=$( echo "${content}" | pup --charset utf-8 'div[class="sm2-playlist-wrapper"] a json{}' | jq -c '.[] | { href: .href, name: .text }' 2>/dev/null )

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
  echo "Downloading to ${name}.mp3"
  curl -# "${url}" -o "${name}.mp3"
done < <(printf '%s\n' "${items}")

