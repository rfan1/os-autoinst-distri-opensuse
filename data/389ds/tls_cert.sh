#!/bin/bash

set -euo pipefail

CN_NAME=$1
CA_DIR=$2
rm -rf $CA_DIR
mkdir -p $CA_DIR
cd $CA_DIR
openssl req -new -x509 -newkey rsa:2048 -keyout myca.key -days 3560 -out myca.pem -nodes -subj "/C=CN/ST=Beijing/L=Beijing/O=QA/OU=security/CN=389ds.example.com
e.com"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -subj "/C=CN/ST=Beijing/L=Beijing/O=QA/OU=security/CN=$1.example.com"
openssl x509 -req -days 3560 -CA myca.pem -CAkey myca.key -CAcreateserial -in server.csr -out server.pem
openssl pkcs12 -export -inkey server.key -in server.pem -out crt.p12 -nodes -name Server-Cert -password pass:""
openssl verify -verbose -CAfile myca.pem server.pem
