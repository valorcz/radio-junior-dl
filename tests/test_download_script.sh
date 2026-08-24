#!/usr/bin/env bash

# Test Suite for download-cesky-rozhlas-junior.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/download-cesky-rozhlas-junior.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  [${GREEN}PASS${NC}] $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  [${RED}FAIL${NC}] $1: $2"
}

# Create a temporary sandbox directory for test artifacts
TEST_TMP_DIR="$(mktemp -d /tmp/test_radio_junior_XXXXXX)"
trap 'rm -rf "${TEST_TMP_DIR}"' EXIT

echo "=== Running Tests for download-cesky-rozhlas-junior.sh ==="

# ---------------------------------------------------------
# Test 1: parseArgs functionality
# ---------------------------------------------------------
echo "Test Suite: parseArgs"

(
    source "${SCRIPT_PATH}"
    parseArgs -d --mkdir -od "/tmp/output_dir" -t 5 -n 2 -c "@#" "https://example.com/1" "https://example.com/2"

    [[ "$DEBUG" == true ]] || { fail "parseArgs DEBUG flag" "Expected true, got $DEBUG"; exit 1; }
    [[ "$MKDIR" == true ]] || { fail "parseArgs MKDIR flag" "Expected true, got $MKDIR"; exit 1; }
    [[ "$outputDirectory" == "/tmp/output_dir" ]] || { fail "parseArgs outputDirectory" "Expected /tmp/output_dir, got $outputDirectory"; exit 1; }
    [[ "$cmdTotalTracks" == "5" ]] || { fail "parseArgs cmdTotalTracks" "Expected 5, got $cmdTotalTracks"; exit 1; }
    [[ "$onlyOneTrack" == true ]] || { fail "parseArgs onlyOneTrack" "Expected true, got $onlyOneTrack"; exit 1; }
    [[ "$onlyOneTrackID" == "2" ]] || { fail "parseArgs onlyOneTrackID" "Expected 2, got $onlyOneTrackID"; exit 1; }
    [[ "$ESCAPECHARS" == "@#" ]] || { fail "parseArgs ESCAPECHARS" "Expected @#, got $ESCAPECHARS"; exit 1; }
    [[ "${#URLs[@]}" -eq 2 ]] || { fail "parseArgs URLs count" "Expected 2, got ${#URLs[@]}"; exit 1; }
    [[ "${URLs[0]}" == "https://example.com/1" ]] || { fail "parseArgs URLs[0]" "Expected https://example.com/1, got ${URLs[0]}"; exit 1; }
    [[ "${URLs[1]}" == "https://example.com/2" ]] || { fail "parseArgs URLs[1]" "Expected https://example.com/2, got ${URLs[1]}"; exit 1; }
    pass "parseArgs flags and multiple URLs parsed correctly"
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 2: Custom ignore list path in parseArgs
# ---------------------------------------------------------
(
    source "${SCRIPT_PATH}"
    custom_ignore="${TEST_TMP_DIR}/custom/skip.list"
    parseArgs -i "${custom_ignore}"
    [[ "$IGNORELIST" == "${custom_ignore}" ]] || { fail "Custom ignore list path" "Expected ${custom_ignore}, got $IGNORELIST"; exit 1; }
    [[ -f "${custom_ignore}" ]] || { fail "Custom ignore file creation" "File ${custom_ignore} does not exist"; exit 1; }
    pass "Custom ignore list is preserved and created"
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 3: verifyFunctions
# ---------------------------------------------------------
echo "Test Suite: verifyFunctions"

(
    source "${SCRIPT_PATH}"
    verifyFunctions "true" "bash" "sh" 2>/dev/null
    pass "verifyFunctions succeeds for available binaries"
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

(
    source "${SCRIPT_PATH}"
    if ( verifyFunctions "true" "non_existent_mandatory_binary_xyz_123" 2>/dev/null ); then
        fail "verifyFunctions mandatory error" "Should have failed for missing mandatory binary"
        exit 1
    else
        pass "verifyFunctions exits with error on missing mandatory binary"
    fi
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

(
    source "${SCRIPT_PATH}"
    verifyFunctions "false" "non_existent_optional_binary_xyz_123" 2>/dev/null
    pass "verifyFunctions warns but does not exit on missing optional binary"
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 4: matchIgnore
# ---------------------------------------------------------
echo "Test Suite: matchIgnore"

(
    source "${SCRIPT_PATH}"
    IGNORELIST="${TEST_TMP_DIR}/test_skip.list"
    cat <<EOF > "${IGNORELIST}"
# This is a comment
skip_this_episode
bad-story
EOF
    URL="https://radio.cz/pribeh"

    if matchIgnore "01_skip_this_episode_final" >/dev/null; then
        pass "matchIgnore correctly matches ignored pattern"
    else
        fail "matchIgnore" "Failed to match '01_skip_this_episode_final'"
        exit 1
    fi

    if matchIgnore "01_good_episode_final" >/dev/null; then
        fail "matchIgnore" "Should not have matched '01_good_episode_final'"
        exit 1
    else
        pass "matchIgnore correctly ignores non-matching pattern"
    fi
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 5: fillValues metadata extraction with mocked curl and pup
# ---------------------------------------------------------
echo "Test Suite: fillValues metadata parsing"

(
    source "${SCRIPT_PATH}"
    MOCK_BIN="${TEST_TMP_DIR}/mock_bin"
    mkdir -p "${MOCK_BIN}"

    VALID_JSON='{"data":{"series":{"title":"Test Serial Title","totalParts":"5"},"playlist":[{"title":"1. díl: Kapitola první","audioLinks":[{"url":"https://audio.cz/ep1.mp3"}],"meta":{"ga":{"contentNameShort":"Kapitola první","contentCreator":"Autor Autor"}}}]}'

    cat <<EOF > "${MOCK_BIN}/curl"
#!/usr/bin/env bash
echo '<div class="mujRozhlasPlayer" data-player="${VALID_JSON}"></div>'
EOF
    chmod +x "${MOCK_BIN}/curl"

    cat <<'EOF' > "${MOCK_BIN}/pup"
#!/usr/bin/env bash
cat <<'JSON'
{"data":{"series":{"title":"Test Serial Title","totalParts":"5"},"playlist":[{"title":"1. díl: Kapitola první","audioLinks":[{"url":"https://audio.cz/ep1.mp3"}],"meta":{"ga":{"contentNameShort":"Kapitola první","contentCreator":"Autor Autor"}}}]}}
JSON
EOF
    chmod +x "${MOCK_BIN}/pup"

    PATH="${MOCK_BIN}:$PATH"
    TRANSFORM=false
    fillValues "https://dummy.rozhlas.cz/serial" >/dev/null 2>&1

    [[ "$description" == "Test Serial Title" ]] || { fail "fillValues description" "Expected 'Test Serial Title', got '$description'"; exit 1; }
    [[ "$album" == "Test Serial Title" ]] || { fail "fillValues album" "Expected 'Test Serial Title', got '$album'"; exit 1; }
    [[ "$totalTracks" == "5" ]] || { fail "fillValues totalTracks" "Expected 5, got '$totalTracks'"; exit 1; }
    [[ "$serial" == true ]] || { fail "fillValues serial" "Expected true, got '$serial'"; exit 1; }
    pass "fillValues correctly extracts album, description, totalTracks and playlist items"
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 6: doDownload ignore list skipping & already downloaded skipping
# ---------------------------------------------------------
echo "Test Suite: doDownload logic"

(
    source "${SCRIPT_PATH}"
    MOCK_BIN="${TEST_TMP_DIR}/mock_bin_dl"
    mkdir -p "${MOCK_BIN}"

    LOGFILE="${TEST_TMP_DIR}/yt_calls.log"
    cat <<EOF > "${MOCK_BIN}/yt-dlp"
#!/usr/bin/env bash
outpath="\${3//%(ext)s/mp3}"
echo "DOWNLOADED: \$1 -> \$outpath" >> "${LOGFILE}"
mkdir -p "\$(dirname "\$outpath")"
echo "dummy audio content" > "\$outpath"
EOF
    chmod +x "${MOCK_BIN}/yt-dlp"
    PATH="${MOCK_BIN}:$PATH"

    items='{"href":"https://audio.cz/1.mp3","name":"1. díl: První příběh"}
{"href":"https://audio.cz/2.mp3","name":"2. díl: Druhý příběh"}'
    
    outputDirectory="${TEST_TMP_DIR}/downloads"
    MKDIR=true
    IGNORELIST="${TEST_TMP_DIR}/skip_2.list"
    echo "Druhý příběh" > "${IGNORELIST}"
    album="TestAlbum"
    serial=true

    doDownload >/dev/null 2>&1

    if grep -q "1.mp3" "${LOGFILE}" && ! grep -q "2.mp3" "${LOGFILE}"; then
        pass "doDownload downloaded item 1 and skipped ignored item 2"
    else
        fail "doDownload ignore skipping" "Log output did not match expected downloads: $(cat "${LOGFILE}" 2>/dev/null)"
        exit 1
    fi

    rm -f "${LOGFILE}"
    doDownload >/dev/null 2>&1

    if [ ! -f "${LOGFILE}" ] || [ ! -s "${LOGFILE}" ]; then
        pass "doDownload correctly skipped already downloaded file"
    else
        fail "doDownload existing file check" "File was re-downloaded: $(cat "${LOGFILE}")"
        exit 1
    fi
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 7: doDownload single track filter (--onlyTrack)
# ---------------------------------------------------------
(
    source "${SCRIPT_PATH}"
    MOCK_BIN="${TEST_TMP_DIR}/mock_bin_onlytrack"
    mkdir -p "${MOCK_BIN}"

    LOGFILE="${TEST_TMP_DIR}/yt_onlytrack.log"
    cat <<EOF > "${MOCK_BIN}/yt-dlp"
#!/usr/bin/env bash
echo "\$1" >> "${LOGFILE}"
EOF
    chmod +x "${MOCK_BIN}/yt-dlp"
    PATH="${MOCK_BIN}:$PATH"

    items='{"href":"https://audio.cz/1.mp3","name":"1. díl: Epizoda 1"}
{"href":"https://audio.cz/2.mp3","name":"2. díl: Epizoda 2"}'
    outputDirectory="${TEST_TMP_DIR}/downloads_onlytrack"
    MKDIR=true
    IGNORELIST="${TEST_TMP_DIR}/empty.list"
    onlyOneTrack=true
    onlyOneTrackID=2
    serial=true
    doDownload >/dev/null 2>&1

    if grep -q "2.mp3" "${LOGFILE}" && ! grep -q "1.mp3" "${LOGFILE}"; then
        pass "doDownload --onlyTrack filtered only track 2"
    else
        fail "doDownload --onlyTrack" "Log did not contain expected track: $(cat "${LOGFILE}" 2>/dev/null)"
        exit 1
    fi
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 8: doDownload cron mode subdirectory structuring
# ---------------------------------------------------------
(
    source "${SCRIPT_PATH}"
    MOCK_BIN="${TEST_TMP_DIR}/mock_bin_cron"
    mkdir -p "${MOCK_BIN}"

    LOGFILE="${TEST_TMP_DIR}/yt_cron.log"
    cat <<EOF > "${MOCK_BIN}/yt-dlp"
#!/usr/bin/env bash
echo "PATH: \$3" >> "${LOGFILE}"
EOF
    chmod +x "${MOCK_BIN}/yt-dlp"
    PATH="${MOCK_BIN}:$PATH"

    items='{"href":"https://audio.cz/1.mp3","name":"01_Pribeh"}'
    outputDirectory="${TEST_TMP_DIR}/cron_output"
    MKDIR=true
    IGNORELIST="${TEST_TMP_DIR}/empty_cron.list"
    touch "${IGNORELIST}"
    EnableCron=true
    album="Moje Pohadky!"
    serial=true

    doDownload >/dev/null 2>&1

    if grep -q "cron_output/Moje_Pohadky/01_Pribeh" "${LOGFILE}"; then
        pass "doDownload under --cron created sanitized album subdirectory"
    else
        fail "doDownload --cron path" "Expected album subpath in log: $(cat "${LOGFILE}" 2>/dev/null)"
        exit 1
    fi
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

# ---------------------------------------------------------
# Test 9: doDownload custom output filename with single track
# ---------------------------------------------------------
(
    source "${SCRIPT_PATH}"
    MOCK_BIN="${TEST_TMP_DIR}/mock_bin_custom_of"
    mkdir -p "${MOCK_BIN}"

    LOGFILE="${TEST_TMP_DIR}/yt_custom_of.log"
    cat <<EOF > "${MOCK_BIN}/yt-dlp"
#!/usr/bin/env bash
echo "TARGET: \$3" >> "${LOGFILE}"
EOF
    chmod +x "${MOCK_BIN}/yt-dlp"
    PATH="${MOCK_BIN}:$PATH"

    items='{"href":"https://audio.cz/1.mp3","name":"1. díl: Epizoda 1"}'
    outputDirectory="${TEST_TMP_DIR}/custom_of_dir"
    MKDIR=true
    IGNORELIST="${TEST_TMP_DIR}/empty_of.list"
    touch "${IGNORELIST}"
    cmdOutputFilename="custom_target_name"
    onlyOneTrack=true
    onlyOneTrackID=1
    serial=true

    doDownload >/dev/null 2>&1

    if grep -q "custom_target_name" "${LOGFILE}"; then
        pass "doDownload respected custom output filename"
    else
        fail "doDownload custom output filename" "Log did not contain custom name: $(cat "${LOGFILE}" 2>/dev/null)"
        exit 1
    fi
) && TESTS_PASSED=$((TESTS_PASSED + 1)) && TESTS_RUN=$((TESTS_RUN + 1)) || { TESTS_FAILED=$((TESTS_FAILED + 1)); TESTS_RUN=$((TESTS_RUN + 1)); }

echo ""
echo "=== Test Summary ==="
echo "Total Tests:  ${TESTS_RUN}"
echo "Passed:       ${TESTS_PASSED}"
echo "Failed:       ${TESTS_FAILED}"

if [ "${TESTS_FAILED}" -eq 0 ]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
