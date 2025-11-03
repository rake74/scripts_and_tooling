#!/bin/bash

# Defaults
cert_details=(
  '-noout'
  '-subject'
  '-issuer'
  '-dates'
)
url_opts=(
  '-showcerts'
)
FILE=''
URL=''
# If openssl support this option, add it to the array.
if ! openssl x509 -ext subjectAltName <<<"" 2>&1 | grep -q 'unknown option'
  then cert_details+=('-ext subjectAltName')
fi
dns_sed_filter='\n    DNS:'

myname=$(basename $0)
usage() {
  cat << EO_USAGE
$myname - Parse a certificate (or chain) extracting specific information.

USAGE:
  $myname -f CERTFILE [OPTIONS]
  $myname -u HOSTNAME[:PORT] [OPTIONS]
  <command> | $myname [OPTIONS]

INPUT SOURCE:
  -f, --file CERTFILE         Read certificate from a file.
  -u, --url HOSTNAME[:PORT]   Fetch certificate from a remote host (port defaults to 443).
  (<stdin>)                   Read certificate from STDIN (3s timeout).

OUTPUT CONTROL:
  -a, --add-details OPTS      Append comma-separated options for the 'openssl x509' command.
  -d, --details OPTS          Redefine all options for the 'openssl x509' command.
  -D, --DNS-raw               Do not format Subject Alternative Name entries into new lines.
  Currently defined 'x509' details:
$(printf "    %s\n" "${cert_details[@]}")

CONNECTION CONTROL:
  -U, --url-opts OPTS         Append comma-separated options for the 'openssl s_client' command.
  Currently defined 's_client' details:
$(printf "    %s\n" "${url_opts[@]}")
  Examples of useful options:
    -starttls ldap
    -verifyCApath CA_DIR
    -noservername
    -servername HOSTNAME

OTHER OPTIONS:
  -h, --help                  Display this help message and exit.
                              Tip: Append --help to command to validate updated options
                                   for openssl x509 and/or s_client commands.
EO_USAGE
  exit
}

exit_err(){ printf "%b\n" "$@" >&2 ; exit 1 ; }

arr_append(){
  declare -n target_array="$1"
  shift
  local INPUT="$@"
  local E
  while IFS= read -r E ; do
    [[ -z "$E" ]] && continue
    [[ "$E" != -* ]] && E="-${E}"
    target_array+=( "$E" )
  done < <( printf "%s\n" "${INPUT//,/$'\n'}" )
}

while (($# > 0)); do
  ARG=$1 ; shift
  case "$ARG" in
    *=* ) ARGV=${ARG#*=} ; myshift=true  ;;
    *   ) ARGV=${1:-}    ; myshift=shift ;;
  esac
  case "$ARG" in
    -f | --file        | --file=*        ) FILE=$ARGV                      ; $myshift ;;
    -u | --url         | --url=*         ) URL=$ARGV                       ; $myshift ;;
    -U | --url-opts    | --url-opts=*    ) arr_append url_opts "$ARGV"     ; $myshift ;;
    -a | --add-details | --add-details=* ) arr_append cert_details "$ARGV" ; $myshift ;;
    -d | --details     | --details=*     ) cert_details=()
                                           arr_append cert_details "$ARGV" ; $myshift ;;
    -D | --DNS-raw                       ) dns_sed_filter=', DNS:'                    ;;
    -h | --help        | --usage         ) usage ;;
    *                                    ) exit_err "Unknown arg: '$ARG'."
  esac
done

if [ -n "$FILE" -a -n "$URL" ] ; then
  exit_err 'Options --file and --url both set. See --usage.'
fi

if [ -n "$FILE" ] ; then
  if [ ! -e "$FILE" ] ; then
    exit_err "File '$FILE' does not exist. See --usage."
  fi
  raw_cert="$(cat "$FILE")"
elif [ -n "$URL" ] ; then
  # Validate supplied URL
  url=${URL,,}
  if grep -Eq '^[a-z0-9]+[a-z0-9.]*[^_]:[0-9]+$' <<<"$url" ; then
    URL=$url
  elif grep -Eq '^[a-z0-9]+[a-z0-9.]*[^_]' <<< "$url" ; then
    URL="$url:443"
  else
    exit_err "URL '${URL}' does not appear to be a valid domain[:port]."
  fi
  openssl_s_client=$(
    openssl s_client ${url_opts[@]} -connect "${URL}" </dev/null 2>&1
  )
  openssl_s_client_retcode=$?
  
  if (( openssl_s_client_retcode > 0 )) ; then
    exit_err "openssl s_client errored: ${openssl_s_client_retcode}\nOutput:\n${openssl_s_client}"
  fi
  raw_cert="$openssl_s_client"
else
  # Check if STDIN is waiting
  if [ -t 0 ] ; then
    exit_err 'Neither --file, --url, nor STDIN pipe in use. See --usage.'
  fi
  STDIN_cert=$(timeout 3s cat)
  if (( $? == 124 )) ; then
    exit_err 'Timed out waiting for cert at STDIN. See --usage.'
  fi
  if [ -z "$STDIN_cert" ] ; then
    exit_err 'No input found at STDIN. See --usage.'
  fi
  raw_cert="$STDIN_cert"
fi

# Collect certs into array.
mapfile -d '' -t cert_chain < <(
  awk '
    # Set reading_cert flag when a cert starts.
    /-----BEGIN CERTIFICATE-----/ { reading_cert = 1 }
    # If reading_cert (is 1) then add to buffer.
    reading_cert { buffer = buffer $0 "\n" }
    # At end of cert print it and reset both reading_cert and buffer.
    /-----END CERTIFICATE-----/ {
      printf "%s\0", buffer
      reading_cert = 0
      buffer = ""
    }
  ' <<< "$raw_cert"
)

if (( ${#cert_chain[@]} == 0 )) ; then
  exit_err "No error encountered, yet no certs identified."
fi

for cert in "${cert_chain[@]}" ; do
  echo "$cert"                      \
  | openssl x509 ${cert_details[@]} \
  | sed "s/, DNS:/${dns_sed_filter}/g"
  echo
done
