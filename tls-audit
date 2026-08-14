#!/usr/bin/env bash

#
# tls-audit.sh
#
# Lightweight TLS endpoint auditing using OpenSSL.
#
# Tests:
#   - TLS 1.0, 1.1, 1.2 and 1.3
#   - Individual cipher-suite support
#   - Certificate details
#   - Certificate verification
#   - Certificate expiry
#   - Default negotiated protocol/cipher
#   - ALPN
#   - Ephemeral key
#
# Output:
#   Human-readable detailed report (default)
#   Human-readable summary (--summary)
#   JSON (--json)
#   CSV (--csv)
#
# Usage:
#   tls-audit.sh [options] <hostname> [port]
#
# Examples:
#   tls-audit.sh example.com
#   tls-audit.sh example.com 8443
#   tls-audit.sh --summary example.com
#   tls-audit.sh --json example.com
#   tls-audit.sh --csv example.com
#   tls-audit.sh --no-delay example.com
#

set -u


###############################################################################
# Defaults
###############################################################################

OPENSSL="${OPENSSL:-openssl}"
DELAY="${DELAY:-0.1}"

OUTPUT_MODE="normal"
USE_COLOUR=1

HOST=""
PORT="443"


###############################################################################
# Usage
###############################################################################

usage()
{
    cat <<EOF
Usage:
  $(basename "$0") [options] <hostname> [port]

Options:
  -s, --summary       Show summary only
  -j, --json          Output JSON
  -c, --csv           Output CSV
      --no-delay      Do not pause between cipher tests
      --no-colour     Disable coloured output
      --no-color      Same as --no-colour
  -h, --help          Show this help

Environment:
  OPENSSL=/path       OpenSSL binary to use
  DELAY=seconds       Delay between cipher tests (default: 0.1)

Examples:
  $(basename "$0") example.com
  $(basename "$0") example.com 8443
  $(basename "$0") --summary example.com
  $(basename "$0") --json example.com > result.json
  $(basename "$0") --csv example.com > result.csv

Exit codes:
  0   Scan completed; no audit issues detected
  1   Scan completed; audit issues detected
  2   Connection or TLS handshake failed
  3   Usage/local dependency error
EOF
}


###############################################################################
# Arguments
###############################################################################

while [[ $# -gt 0 ]]; do

    case "$1" in

        -s|--summary)
            OUTPUT_MODE="summary"
            shift
            ;;

        -j|--json)
            OUTPUT_MODE="json"
            USE_COLOUR=0
            shift
            ;;

        -c|--csv)
            OUTPUT_MODE="csv"
            USE_COLOUR=0
            shift
            ;;

        --no-delay)
            DELAY=0
            shift
            ;;

        --no-colour|--no-color)
            USE_COLOUR=0
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        -*)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 3
            ;;

        *)
            if [[ -z "$HOST" ]]; then
                HOST="$1"
            elif [[ "$PORT" == "443" ]]; then
                PORT="$1"
            else
                echo "ERROR: Too many arguments." >&2
                usage >&2
                exit 3
            fi

            shift
            ;;

    esac

done


if [[ -z "$HOST" ]]; then
    usage >&2
    exit 3
fi


if ! [[ "$PORT" =~ ^[0-9]+$ ]] ||
   (( PORT < 1 || PORT > 65535 ))
then
    echo "ERROR: Invalid port: $PORT" >&2
    exit 3
fi


SERVER="${HOST}:${PORT}"


###############################################################################
# Dependencies
###############################################################################

if ! command -v "$OPENSSL" >/dev/null 2>&1; then
    echo "ERROR: OpenSSL not found: $OPENSSL" >&2
    exit 3
fi

OPENSSL_VERSION="$("$OPENSSL" version 2>/dev/null)"


###############################################################################
# Colours
###############################################################################

if [[ "$USE_COLOUR" -eq 1 && -t 1 ]]; then

    GREEN=$'\033[0;32m'
    RED=$'\033[0;31m'
    YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'

else

    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    BOLD=""
    DIM=""
    RESET=""

fi


###############################################################################
# Results
###############################################################################

supported=0
rejected=0
local_unsupported=0
issues=0

declare -a TLS10_SUPPORTED=()
declare -a TLS11_SUPPORTED=()
declare -a TLS12_SUPPORTED=()
declare -a TLS13_SUPPORTED=()

declare -a AUDIT_MESSAGES=()


###############################################################################
# Certificate/default negotiation results
###############################################################################

subject=""
issuer=""
not_before=""
not_after=""
serial=""
fingerprint=""

pubkey_algorithm=""
pubkey_bits=""
signature_algorithm=""

verify_status="unknown"
expiry_days=""

default_protocol=""
default_cipher=""
peer_signature=""
temp_key=""
alpn=""


###############################################################################
# Helpers
###############################################################################

is_human_output()
{
    [[ "$OUTPUT_MODE" == "normal" ||
       "$OUTPUT_MODE" == "summary" ]]
}


verbose_output()
{
    [[ "$OUTPUT_MODE" == "normal" ]]
}


have_option()
{
    "$OPENSSL" s_client -help 2>&1 |
        grep -q -- "$1"
}


protocol_supported_locally()
{
    case "$1" in

        tls1)
            have_option "-tls1"
            ;;

        tls1_1)
            have_option "-tls1_1"
            ;;

        tls1_2)
            have_option "-tls1_2"
            ;;

        tls1_3)
            have_option "-tls1_3" &&
                have_option "-ciphersuites"
            ;;

        *)
            return 1
            ;;

    esac
}


protocol_label()
{
    case "$1" in
        tls1)   echo "TLS 1.0" ;;
        tls1_1) echo "TLS 1.1" ;;
        tls1_2) echo "TLS 1.2" ;;
        tls1_3) echo "TLS 1.3" ;;
    esac
}


record_supported()
{
    local proto="$1"
    local cipher="$2"

    case "$proto" in

        tls1)
            TLS10_SUPPORTED+=("$cipher")
            ;;

        tls1_1)
            TLS11_SUPPORTED+=("$cipher")
            ;;

        tls1_2)
            TLS12_SUPPORTED+=("$cipher")
            ;;

        tls1_3)
            TLS13_SUPPORTED+=("$cipher")
            ;;

    esac
}


extract_error()
{
    local result="$1"
    local error=""

    error=$(
        printf '%s\n' "$result" |
        grep -Ei \
            'SSL routines:|ssl3_read_bytes:.*alert|tlsv1 alert|sslv3 alert' |
        tail -n 1
    )

    if [[ -n "$error" ]]; then

        error=$(
            printf '%s\n' "$error" |
            sed -E \
                -e 's/^.*error:[0-9A-Fa-f]+:SSL routines://' \
                -e 's#:\.\./ssl/.*$##' \
                -e 's/^ *//' \
                -e 's/ *$//'
        )

    fi

    if [[ -z "$error" ]]; then

        if grep -qi 'no cipher match' <<< "$result"; then
            error="no cipher match"

        elif grep -qi 'handshake failure' <<< "$result"; then
            error="handshake failure"

        elif grep -qi 'protocol version' <<< "$result"; then
            error="protocol version"

        elif grep -qi 'connection refused' <<< "$result"; then
            error="connection refused"

        elif grep -qi 'connect:errno=' <<< "$result"; then
            error="connection failed"

        fi

    fi

    printf '%s' "$error"
}


add_issue()
{
    local severity="$1"
    local message="$2"

    AUDIT_MESSAGES+=("${severity}|${message}")

    if [[ "$severity" == "WARN" ||
          "$severity" == "FAIL" ]]
    then
        ((issues++))
    fi
}


###############################################################################
# JSON helpers
###############################################################################

json_escape()
{
    local value="$1"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}

    printf '%s' "$value"
}


json_array()
{
    local first=1
    local value

    printf '['

    for value in "$@"; do

        if [[ "$first" -eq 0 ]]; then
            printf ','
        fi

        printf '"%s"' "$(json_escape "$value")"

        first=0

    done

    printf ']'
}


###############################################################################
# CSV helper
###############################################################################

csv_escape()
{
    local value="$1"

    value=${value//\"/\"\"}

    printf '"%s"' "$value"
}


###############################################################################
# Connectivity / initial handshake
###############################################################################

if verbose_output; then

    echo
    echo "${BOLD}TLS Endpoint Audit${RESET}"
    echo "======================================================================"
    echo "Target:           $SERVER"
    echo "OpenSSL:          $OPENSSL_VERSION"
    echo "SNI hostname:     $HOST"
    echo "======================================================================"
    echo

    printf 'Checking connectivity... '

fi


HANDSHAKE=$(
    "$OPENSSL" s_client \
        -connect "$SERVER" \
        -servername "$HOST" \
        -showcerts \
        </dev/null 2>&1
)


if ! grep -qE \
    'Protocol *:|Protocol version:|New, TLSv' \
    <<< "$HANDSHAKE"
then

    if is_human_output; then

        if verbose_output; then
            echo "${RED}FAILED${RESET}"
            echo
        fi

        echo "ERROR: Could not establish a TLS connection to $SERVER." >&2

    fi

    exit 2

fi


if verbose_output; then
    echo "${GREEN}OK${RESET}"
fi


###############################################################################
# Extract leaf certificate
###############################################################################

CERT=$(
    printf '%s\n' "$HANDSHAKE" |
    awk '
        /-----BEGIN CERTIFICATE-----/ && !found {
            found=1
        }

        found {
            print
        }

        /-----END CERTIFICATE-----/ && found {
            exit
        }
    '
)


###############################################################################
# Certificate information
###############################################################################

if [[ -n "$CERT" ]]; then

    CERT_INFO=$(
        printf '%s\n' "$CERT" |
        "$OPENSSL" x509 \
            -noout \
            -subject \
            -issuer \
            -dates \
            -serial \
            -fingerprint \
            -sha256 2>/dev/null
    )

    CERT_TEXT=$(
        printf '%s\n' "$CERT" |
        "$OPENSSL" x509 \
            -noout \
            -text 2>/dev/null
    )

    subject=$(
        printf '%s\n' "$CERT_INFO" |
        sed -n 's/^subject=//p'
    )

    issuer=$(
        printf '%s\n' "$CERT_INFO" |
        sed -n 's/^issuer=//p'
    )

    not_before=$(
        printf '%s\n' "$CERT_INFO" |
        sed -n 's/^notBefore=//p'
    )

    not_after=$(
        printf '%s\n' "$CERT_INFO" |
        sed -n 's/^notAfter=//p'
    )

    serial=$(
        printf '%s\n' "$CERT_INFO" |
        sed -n 's/^serial=//p'
    )

    fingerprint=$(
        printf '%s\n' "$CERT_INFO" |
        sed -n 's/^sha256 Fingerprint=//Ip'
    )

    pubkey_algorithm=$(
        printf '%s\n' "$CERT_TEXT" |
        sed -n \
            's/^[[:space:]]*Public Key Algorithm: //p' |
        head -1
    )

    pubkey_bits=$(
        printf '%s\n' "$CERT_TEXT" |
        sed -n \
            's/^[[:space:]]*Public-Key: (\([0-9]*\) bit).*/\1/p' |
        head -1
    )

    signature_algorithm=$(
        printf '%s\n' "$CERT_TEXT" |
        sed -n \
            's/^[[:space:]]*Signature Algorithm: //p' |
        head -1
    )

fi


###############################################################################
# Verification status
###############################################################################

verify_line=$(
    printf '%s\n' "$HANDSHAKE" |
    grep 'Verify return code:' |
    tail -1
)

if [[ "$verify_line" =~ Verify\ return\ code:\ 0 ]]; then

    verify_status="OK"

else

    verify_status=$(
        printf '%s\n' "$verify_line" |
        sed -E \
            's/^.*Verify return code: [0-9]+ \((.*)\).*$/\1/'
    )

    [[ -z "$verify_status" ]] &&
        verify_status="unknown"

fi


###############################################################################
# Certificate expiry
###############################################################################

if [[ -n "$CERT" ]]; then

    enddate=$(
        printf '%s\n' "$CERT" |
        "$OPENSSL" x509 \
            -noout \
            -enddate 2>/dev/null |
        cut -d= -f2-
    )

    #
    # GNU date is available on the majority of Linux systems where this
    # script is likely to run. If it is unavailable or cannot parse the
    # OpenSSL date, expiry_days remains unknown.
    #
    if command -v date >/dev/null 2>&1; then

        expiry_epoch=$(
            date -d "$enddate" +%s 2>/dev/null || true
        )

        now_epoch=$(
            date +%s 2>/dev/null || true
        )

        if [[ -n "$expiry_epoch" &&
              -n "$now_epoch" ]]
        then

            expiry_days=$(
                echo $(( (expiry_epoch - now_epoch) / 86400 ))
            )

        fi

    fi

fi


###############################################################################
# Default negotiation
###############################################################################

BRIEF=$(
    "$OPENSSL" s_client \
        -brief \
        -connect "$SERVER" \
        -servername "$HOST" \
        </dev/null 2>&1
)


default_protocol=$(
    printf '%s\n' "$BRIEF" |
    sed -n 's/^Protocol version: //p' |
    head -1
)

default_cipher=$(
    printf '%s\n' "$BRIEF" |
    sed -n 's/^Ciphersuite: //p' |
    head -1
)

peer_signature=$(
    printf '%s\n' "$BRIEF" |
    sed -n 's/^Peer signature type: //p' |
    head -1
)

temp_key=$(
    printf '%s\n' "$BRIEF" |
    sed -n 's/^Server Temp Key: //p' |
    head -1
)


alpn=$(
    printf '%s\n' "$HANDSHAKE" |
    sed -n 's/^ALPN protocol: //p' |
    head -1
)


if [[ -z "$alpn" ]] &&
   grep -q 'No ALPN negotiated' <<< "$HANDSHAKE"
then
    alpn="none"
fi


###############################################################################
# Detailed certificate/default output
###############################################################################

if verbose_output; then

    echo
    echo "${BOLD}=== Certificate ===${RESET}"

    printf 'Subject:           %s\n' "${subject:-unknown}"
    printf 'Issuer:            %s\n' "${issuer:-unknown}"
    printf 'Valid from:        %s\n' "${not_before:-unknown}"
    printf 'Valid until:       %s\n' "${not_after:-unknown}"

    if [[ -n "$expiry_days" ]]; then
        printf 'Expires in:        %s days\n' "$expiry_days"
    fi

    printf 'Verification:      %s\n' "$verify_status"

    if [[ -n "$pubkey_bits" ]]; then

        printf 'Public key:        %s (%s bits)\n' \
            "${pubkey_algorithm:-unknown}" \
            "$pubkey_bits"

    else

        printf 'Public key:        %s\n' \
            "${pubkey_algorithm:-unknown}"

    fi

    printf 'Signature:         %s\n' \
        "${signature_algorithm:-unknown}"

    printf 'Serial:            %s\n' \
        "${serial:-unknown}"

    printf 'SHA256 fingerprint: %s\n' \
        "${fingerprint:-unknown}"


    echo
    echo "${BOLD}=== Default Negotiation ===${RESET}"

    printf 'Protocol:          %s\n' \
        "${default_protocol:-unknown}"

    printf 'Cipher:            %s\n' \
        "${default_cipher:-unknown}"

    printf 'Peer signature:    %s\n' \
        "${peer_signature:-unknown}"

    printf 'Ephemeral key:     %s\n' \
        "${temp_key:-unknown}"

    printf 'ALPN:              %s\n' \
        "${alpn:-unknown}"

fi


###############################################################################
# TLS 1.0 - TLS 1.2
###############################################################################

test_legacy_protocol()
{
    local proto="$1"
    local label
    local cipher
    local result
    local error
    local -a ciphers

    label=$(protocol_label "$proto")

    if verbose_output; then
        echo
        echo "${BOLD}=== $label ===${RESET}"
    fi


    if ! protocol_supported_locally "$proto"; then

        ((local_unsupported++))

        if verbose_output; then
            echo \
                "${YELLOW}Local OpenSSL cannot test this protocol.${RESET}"
        fi

        return

    fi


    mapfile -t ciphers < <(
        "$OPENSSL" ciphers \
            "-$proto" \
            'ALL:eNULL:@SECLEVEL=0' \
            2>/dev/null |
        tr ':' '\n' |
        grep -v '^TLS_' |
        sort -u
    )


    if [[ ${#ciphers[@]} -eq 0 ]]; then

        ((local_unsupported++))

        if verbose_output; then
            echo \
                "${YELLOW}No locally available cipher suites.${RESET}"
        fi

        return

    fi


    for cipher in "${ciphers[@]}"; do

        if verbose_output; then
            printf '  %-48s ' "$cipher"
        fi


        result=$(
            "$OPENSSL" s_client \
                -brief \
                "-$proto" \
                -cipher "${cipher}:@SECLEVEL=0" \
                -connect "$SERVER" \
                -servername "$HOST" \
                </dev/null 2>&1
        )


        if grep -Fq \
            "Ciphersuite: $cipher" \
            <<< "$result"
        then

            ((supported++))
            record_supported "$proto" "$cipher"

            if verbose_output; then
                echo "${GREEN}SUPPORTED${RESET}"
            fi

        else

            error=$(extract_error "$result")

            if grep -qiE \
                'no cipher match|unsupported|no ciphers available|library has no ciphers' \
                <<< "$result"
            then

                ((local_unsupported++))

                if verbose_output; then

                    printf '%sLOCAL UNSUPPORTED%s' \
                        "$YELLOW" "$RESET"

                    if [[ -n "$error" ]]; then
                        printf ' (%s)' "$error"
                    fi

                    echo

                fi

            else

                ((rejected++))

                if verbose_output; then

                    printf '%sREJECTED%s' \
                        "$RED" "$RESET"

                    if [[ -n "$error" ]]; then
                        printf ' (%s)' "$error"
                    fi

                    echo

                fi

            fi

        fi


        if [[ "$DELAY" != "0" ]]; then
            sleep "$DELAY"
        fi

    done
}


test_legacy_protocol tls1
test_legacy_protocol tls1_1
test_legacy_protocol tls1_2


###############################################################################
# TLS 1.3
###############################################################################

test_tls13()
{
    local cipher
    local result
    local error
    local -a ciphers

    if verbose_output; then
        echo
        echo "${BOLD}=== TLS 1.3 ===${RESET}"
    fi


    if ! protocol_supported_locally tls1_3; then

        ((local_unsupported++))

        if verbose_output; then
            echo \
                "${YELLOW}TLS 1.3 cannot be tested by this OpenSSL.${RESET}"
        fi

        return

    fi


    mapfile -t ciphers < <(
        "$OPENSSL" ciphers \
            -tls1_3 \
            2>/dev/null |
        tr ':' '\n' |
        grep '^TLS_' |
        sort -u
    )


    if [[ ${#ciphers[@]} -eq 0 ]]; then

        ((local_unsupported++))

        if verbose_output; then
            echo \
                "${YELLOW}No local TLS 1.3 cipher suites found.${RESET}"
        fi

        return

    fi


    for cipher in "${ciphers[@]}"; do

        if verbose_output; then
            printf '  %-48s ' "$cipher"
        fi


        result=$(
            "$OPENSSL" s_client \
                -brief \
                -tls1_3 \
                -ciphersuites "$cipher" \
                -connect "$SERVER" \
                -servername "$HOST" \
                </dev/null 2>&1
        )


        if grep -Fq \
            "Ciphersuite: $cipher" \
            <<< "$result"
        then

            ((supported++))
            record_supported tls1_3 "$cipher"

            if verbose_output; then
                echo "${GREEN}SUPPORTED${RESET}"
            fi

        else

            error=$(extract_error "$result")

            if grep -qiE \
                'no cipher match|unsupported|no ciphers available|library has no ciphers' \
                <<< "$result"
            then

                ((local_unsupported++))

                if verbose_output; then
                    echo \
                        "${YELLOW}LOCAL UNSUPPORTED${RESET}"
                fi

            else

                ((rejected++))

                if verbose_output; then

                    printf '%sREJECTED%s' \
                        "$RED" "$RESET"

                    if [[ -n "$error" ]]; then
                        printf ' (%s)' "$error"
                    fi

                    echo

                fi

            fi

        fi


        if [[ "$DELAY" != "0" ]]; then
            sleep "$DELAY"
        fi

    done
}


test_tls13


###############################################################################
# Audit analysis
###############################################################################

if [[ ${#TLS10_SUPPORTED[@]} -gt 0 ]]; then

    add_issue \
        "WARN" \
        "TLS 1.0 is enabled."

else

    add_issue \
        "PASS" \
        "TLS 1.0 not detected."

fi


if [[ ${#TLS11_SUPPORTED[@]} -gt 0 ]]; then

    add_issue \
        "WARN" \
        "TLS 1.1 is enabled."

else

    add_issue \
        "PASS" \
        "TLS 1.1 not detected."

fi


if [[ ${#TLS12_SUPPORTED[@]} -gt 0 ]]; then

    add_issue \
        "PASS" \
        "TLS 1.2 is enabled."

else

    add_issue \
        "INFO" \
        "TLS 1.2 not detected."

fi


if [[ ${#TLS13_SUPPORTED[@]} -gt 0 ]]; then

    add_issue \
        "PASS" \
        "TLS 1.3 is enabled."

else

    add_issue \
        "INFO" \
        "TLS 1.3 not detected."

fi


###############################################################################
# Certificate audit
###############################################################################

if [[ "$verify_status" == "OK" ]]; then

    add_issue \
        "PASS" \
        "Certificate verification succeeded."

else

    add_issue \
        "FAIL" \
        "Certificate verification failed: $verify_status"

fi


if [[ -n "$expiry_days" ]]; then

    if (( expiry_days < 0 )); then

        add_issue \
            "FAIL" \
            "Certificate has expired."

    elif (( expiry_days <= 7 )); then

        add_issue \
            "WARN" \
            "Certificate expires in $expiry_days days."

    elif (( expiry_days <= 30 )); then

        add_issue \
            "INFO" \
            "Certificate expires in $expiry_days days."

    else

        add_issue \
            "PASS" \
            "Certificate expires in $expiry_days days."

    fi

fi


###############################################################################
# Legacy/bad cipher audit
###############################################################################

ALL_SUPPORTED=$(
    printf '%s\n' \
        "${TLS10_SUPPORTED[@]}" \
        "${TLS11_SUPPORTED[@]}" \
        "${TLS12_SUPPORTED[@]}" \
        "${TLS13_SUPPORTED[@]}"
)


if grep -qE \
    '(^|-)NULL($|-)' \
    <<< "$ALL_SUPPORTED"
then

    add_issue \
        "FAIL" \
        "NULL encryption cipher detected."

fi


if grep -qE \
    '(^|-)RC4($|-)' \
    <<< "$ALL_SUPPORTED"
then

    add_issue \
        "FAIL" \
        "RC4 cipher detected."

fi


if grep -qE \
    '(^|-)DES($|-)|(^|-)3DES($|-)|DES-CBC3' \
    <<< "$ALL_SUPPORTED"
then

    add_issue \
        "WARN" \
        "DES/3DES cipher detected."

fi


if grep -qE \
    '(^|-)EXPORT($|-)|EXP-' \
    <<< "$ALL_SUPPORTED"
then

    add_issue \
        "FAIL" \
        "Export-grade cipher detected."

fi


if grep -qE \
    '^ADH-|^AECDH-' \
    <<< "$ALL_SUPPORTED"
then

    add_issue \
        "FAIL" \
        "Anonymous authentication cipher detected."

fi


###############################################################################
# Public-key observation
###############################################################################

case "$pubkey_algorithm" in

    *id-ecPublicKey*|*EC*)

        add_issue \
            "INFO" \
            "Server certificate uses an EC public key."
        ;;

    *rsaEncryption*|*RSA*)

        add_issue \
            "INFO" \
            "Server certificate uses an RSA public key."
        ;;

esac


###############################################################################
# Human-readable output
###############################################################################

print_cipher_group()
{
    local label="$1"
    shift

    local -a suites=("$@")
    local suite

    printf '\n%s%s%s\n' \
        "$CYAN" "$label" "$RESET"

    if [[ ${#suites[@]} -eq 0 ]]; then

        echo "  ${DIM}None detected${RESET}"
        return

    fi

    for suite in "${suites[@]}"; do

        printf '  %s%s%s\n' \
            "$GREEN" "$suite" "$RESET"

    done
}


print_human_summary()
{
    local entry
    local severity
    local message

    echo
    echo "${BOLD}======================================================================"
    echo "SUPPORTED CIPHER SUITES"
    echo "======================================================================${RESET}"

    print_cipher_group \
        "TLS 1.0" \
        "${TLS10_SUPPORTED[@]}"

    print_cipher_group \
        "TLS 1.1" \
        "${TLS11_SUPPORTED[@]}"

    print_cipher_group \
        "TLS 1.2" \
        "${TLS12_SUPPORTED[@]}"

    print_cipher_group \
        "TLS 1.3" \
        "${TLS13_SUPPORTED[@]}"


    echo
    echo
    echo "${BOLD}======================================================================"
    echo "AUDIT OBSERVATIONS"
    echo "======================================================================${RESET}"


    for entry in "${AUDIT_MESSAGES[@]}"; do

        severity="${entry%%|*}"
        message="${entry#*|}"

        case "$severity" in

            PASS)
                printf '%s[+]%s %s\n' \
                    "$GREEN" "$RESET" "$message"
                ;;

            INFO)
                printf '%s[i]%s %s\n' \
                    "$CYAN" "$RESET" "$message"
                ;;

            WARN)
                printf '%s[!]%s %s\n' \
                    "$YELLOW" "$RESET" "$message"
                ;;

            FAIL)
                printf '%s[!]%s %s\n' \
                    "$RED" "$RESET" "$message"
                ;;

        esac

    done


    echo
    echo
    echo "${BOLD}======================================================================"
    echo "SCAN STATISTICS"
    echo "======================================================================${RESET}"

    printf 'Target:                         %s\n' \
        "$SERVER"

    printf 'Default protocol:               %s\n' \
        "${default_protocol:-unknown}"

    printf 'Default cipher:                 %s\n' \
        "${default_cipher:-unknown}"

    printf 'Supported cipher tests:         %d\n' \
        "$supported"

    printf 'Rejected cipher tests:          %d\n' \
        "$rejected"

    printf 'Locally unsupported tests:      %d\n' \
        "$local_unsupported"

    printf 'Audit issues requiring review:  %d\n' \
        "$issues"

    echo
}


###############################################################################
# JSON output
###############################################################################

print_json()
{
    local first=1
    local entry
    local severity
    local message

    printf '{\n'

    printf '  "target": "%s",\n' \
        "$(json_escape "$HOST")"

    printf '  "port": %d,\n' \
        "$PORT"

    printf '  "openssl": "%s",\n' \
        "$(json_escape "$OPENSSL_VERSION")"


    printf '  "certificate": {\n'

    printf '    "subject": "%s",\n' \
        "$(json_escape "$subject")"

    printf '    "issuer": "%s",\n' \
        "$(json_escape "$issuer")"

    printf '    "not_before": "%s",\n' \
        "$(json_escape "$not_before")"

    printf '    "not_after": "%s",\n' \
        "$(json_escape "$not_after")"

    if [[ -n "$expiry_days" ]]; then
        printf '    "expiry_days": %d,\n' \
            "$expiry_days"
    else
        printf '    "expiry_days": null,\n'
    fi

    printf '    "verification": "%s",\n' \
        "$(json_escape "$verify_status")"

    printf '    "public_key_algorithm": "%s",\n' \
        "$(json_escape "$pubkey_algorithm")"

    if [[ -n "$pubkey_bits" ]]; then
        printf '    "public_key_bits": %d,\n' \
            "$pubkey_bits"
    else
        printf '    "public_key_bits": null,\n'
    fi

    printf '    "signature_algorithm": "%s",\n' \
        "$(json_escape "$signature_algorithm")"

    printf '    "serial": "%s",\n' \
        "$(json_escape "$serial")"

    printf '    "sha256_fingerprint": "%s"\n' \
        "$(json_escape "$fingerprint")"

    printf '  },\n'


    printf '  "negotiated": {\n'

    printf '    "protocol": "%s",\n' \
        "$(json_escape "$default_protocol")"

    printf '    "cipher": "%s",\n' \
        "$(json_escape "$default_cipher")"

    printf '    "peer_signature": "%s",\n' \
        "$(json_escape "$peer_signature")"

    printf '    "ephemeral_key": "%s",\n' \
        "$(json_escape "$temp_key")"

    printf '    "alpn": "%s"\n' \
        "$(json_escape "$alpn")"

    printf '  },\n'


    printf '  "supported_ciphers": {\n'

    printf '    "TLSv1.0": '
    json_array "${TLS10_SUPPORTED[@]}"
    printf ',\n'

    printf '    "TLSv1.1": '
    json_array "${TLS11_SUPPORTED[@]}"
    printf ',\n'

    printf '    "TLSv1.2": '
    json_array "${TLS12_SUPPORTED[@]}"
    printf ',\n'

    printf '    "TLSv1.3": '
    json_array "${TLS13_SUPPORTED[@]}"
    printf '\n'

    printf '  },\n'


    printf '  "statistics": {\n'

    printf '    "supported": %d,\n' \
        "$supported"

    printf '    "rejected": %d,\n' \
        "$rejected"

    printf '    "locally_unsupported": %d,\n' \
        "$local_unsupported"

    printf '    "audit_issues": %d\n' \
        "$issues"

    printf '  },\n'


    printf '  "observations": [\n'


    for entry in "${AUDIT_MESSAGES[@]}"; do

        severity="${entry%%|*}"
        message="${entry#*|}"

        if [[ "$first" -eq 0 ]]; then
            printf ',\n'
        fi

        printf '    {'

        printf '"severity":"%s",' \
            "$(json_escape "$severity")"

        printf '"message":"%s"' \
            "$(json_escape "$message")"

        printf '}'

        first=0

    done


    printf '\n  ]\n'
    printf '}\n'
}


###############################################################################
# CSV output
###############################################################################

print_csv()
{
    local cipher
    local entry
    local severity
    local message

    echo \
'"record_type","host","port","protocol","cipher","severity","message"'


    for cipher in "${TLS10_SUPPORTED[@]}"; do

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$(csv_escape "cipher")" \
            "$(csv_escape "$HOST")" \
            "$(csv_escape "$PORT")" \
            "$(csv_escape "TLSv1.0")" \
            "$(csv_escape "$cipher")" \
            "$(csv_escape "SUPPORTED")" \
            "$(csv_escape "")"

    done


    for cipher in "${TLS11_SUPPORTED[@]}"; do

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$(csv_escape "cipher")" \
            "$(csv_escape "$HOST")" \
            "$(csv_escape "$PORT")" \
            "$(csv_escape "TLSv1.1")" \
            "$(csv_escape "$cipher")" \
            "$(csv_escape "SUPPORTED")" \
            "$(csv_escape "")"

    done


    for cipher in "${TLS12_SUPPORTED[@]}"; do

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$(csv_escape "cipher")" \
            "$(csv_escape "$HOST")" \
            "$(csv_escape "$PORT")" \
            "$(csv_escape "TLSv1.2")" \
            "$(csv_escape "$cipher")" \
            "$(csv_escape "SUPPORTED")" \
            "$(csv_escape "")"

    done


    for cipher in "${TLS13_SUPPORTED[@]}"; do

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$(csv_escape "cipher")" \
            "$(csv_escape "$HOST")" \
            "$(csv_escape "$PORT")" \
            "$(csv_escape "TLSv1.3")" \
            "$(csv_escape "$cipher")" \
            "$(csv_escape "SUPPORTED")" \
            "$(csv_escape "")"

    done


    for entry in "${AUDIT_MESSAGES[@]}"; do

        severity="${entry%%|*}"
        message="${entry#*|}"

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$(csv_escape "observation")" \
            "$(csv_escape "$HOST")" \
            "$(csv_escape "$PORT")" \
            "$(csv_escape "")" \
            "$(csv_escape "")" \
            "$(csv_escape "$severity")" \
            "$(csv_escape "$message")"

    done
}


###############################################################################
# Final output
###############################################################################

case "$OUTPUT_MODE" in

    normal|summary)
        print_human_summary
        ;;

    json)
        print_json
        ;;

    csv)
        print_csv
        ;;

esac


###############################################################################
# Exit status
###############################################################################

if (( issues > 0 )); then
    exit 1
fi

exit 0
