#!/bin/bash
set -euo pipefail
umask 077
name='GuYi Input Method Local Development'
directory="$HOME/Library/Application Support/guyi/Signing"
mkdir -p "$directory"
chmod 700 "$directory"
identity="$(security find-identity -v -p codesigning | awk -v name="$name" 'index($0, "\"" name "\"") { print $2; exit }')"
if test -n "$identity"; then
    printf '%s\n' "$identity" > "$directory/identity.txt"
    chmod 600 "$directory/identity.txt"
    printf 'GuYi local signing identity already exists.\n'
    exit 0
fi
if ! test -f "$directory/certificate.pem"; then
    openssl req -x509 -newkey rsa:3072 -noenc -sha256 -days 1825 \
        -subj "/CN=$name/" \
        -addext 'basicConstraints=critical,CA:FALSE' \
        -addext 'keyUsage=critical,digitalSignature' \
        -addext 'extendedKeyUsage=critical,codeSigning' \
        -keyout "$directory/private-key.pem" -out "$directory/certificate.pem" 2>"$directory/generation.log"
fi
keychain="$HOME/Library/Keychains/login.keychain-db"
if test -f "$directory/private-key.pem"; then
    openssl rsa -in "$directory/private-key.pem" -traditional -out "$directory/import-key.pem" 2>"$directory/conversion.log"
    security import "$directory/import-key.pem" -k "$keychain" -t priv -f openssl -x -T /usr/bin/codesign
    rm "$directory/import-key.pem"
    rm "$directory/private-key.pem"
fi
security import "$directory/certificate.pem" -k "$keychain" -t cert -f openssl
printf 'Approve the macOS prompt to trust this certificate for code signing only.\n'
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$directory/certificate.pem"
security find-identity -v -p codesigning
security find-identity -v -p codesigning | awk -v name="$name" 'index($0, "\"" name "\"") { print $2; exit }' > "$directory/identity.txt"
test -s "$directory/identity.txt"
