#!/bin/sh
# Sign OptTab with a stable local identity so Accessibility grants survive rebuilds.
# The private key stays in ~/Library/Application Support/OptTab, not in git.

sign_opttab() {
    app=$1
    support="${HOME}/Library/Application Support/OptTab"
    keychain="${support}/signing.keychain-db"
    crt="${support}/opttab.crt"
    key="${support}/opttab.key"
    p12="${support}/opttab.p12"
    cnf="${support}/openssl.cnf"
    pass=opttab-local
    login="${HOME}/Library/Keychains/login.keychain-db"
    cn=OptTab

    mkdir -p "$support"

    if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
        cat > "$cnf" << 'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = OptTab
[ v3 ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
        openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
            -keyout "$key" -out "$crt" -config "$cnf" >/dev/null 2>&1
        chmod 600 "$key"
    fi

    if [ ! -f "$p12" ]; then
        openssl pkcs12 -export -inkey "$key" -in "$crt" -out "$p12" \
            -passout "pass:${pass}" -name "$cn" \
            -legacy -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
            >/dev/null 2>&1 \
        || openssl pkcs12 -export -inkey "$key" -in "$crt" -out "$p12" \
            -passout "pass:${pass}" -name "$cn" >/dev/null 2>&1
        chmod 600 "$p12"
    fi

    if [ ! -f "$keychain" ]; then
        security create-keychain -p "$pass" "$keychain" >/dev/null
        security set-keychain-settings "$keychain" >/dev/null
    fi

    security unlock-keychain -p "$pass" "$keychain" >/dev/null

    if ! security find-identity -p codesigning -v "$keychain" 2>/dev/null | grep -q "\"${cn}\""; then
        security import "$p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign -T /usr/bin/security >/dev/null || true
        security add-trusted-cert -d -r trustRoot -k "$keychain" "$crt" >/dev/null 2>&1 || true
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$keychain" >/dev/null || true
    fi

    security list-keychains -d user -s "$keychain" "$login" >/dev/null
    if ! codesign --force --sign "$cn" --keychain "$keychain" --identifier com.mmdmcy.opttab --timestamp=none "$app"; then
        security list-keychains -d user -s "$login" >/dev/null
        printf '%s\n' "Stable signing failed; falling back to ad-hoc." >&2
        codesign --force --sign - --identifier com.mmdmcy.opttab --timestamp=none "$app"
        return
    fi
    security list-keychains -d user -s "$login" >/dev/null
}
