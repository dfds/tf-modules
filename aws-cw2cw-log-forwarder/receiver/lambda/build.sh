#!/bin/sh
GOOS="linux" GOARCH="amd64" CGO_ENABLED="0" go build main.go
zip function.zip main
openssl sha256 -binary < function.zip > function.zip.sha256.sum
openssl md5 -hex < function.zip > function.zip.md5.sum