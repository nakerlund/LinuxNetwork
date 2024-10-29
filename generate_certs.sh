#!/bin/sh

echo "Generating certificates"

bits=2048
days=10950
server=mosquitto
client=client

path="certs/"

mkdir -p "$path"

rm "$path/ca.key" "$path/ca.crt" "$path/client.key" "$path/client.csr" "$path/client.crt"

subject="//windows=fix/C=SE/ST=Stockholm/L=Nacka/O=Nackademin/CN="

# Generate CA key
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:"$bits" -out "${path}ca.key"

# Sign the CA key
openssl req -new -x509 -days "$days" -subj "${subject}${server}" -key "${path}ca.key" -out "${path}ca.crt"

# Generate a key for the client
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:"$bits" -out "${path}client.key"

# Generate a signing request for the client
openssl req -new -key "${path}client.key" -out "${path}client.csr" -subj "${subject}${client}@${server}" 

# Sign the client signing request with the CA to create the client certificate
openssl x509 -req -in "${path}client.csr" -CA "${path}ca.crt" -CAkey "${path}ca.key" -out "${path}client.crt" -days "$days"
