#!/bin/bash

src=$(dirname $0)
dest=$1

find "$src" -name '*.pm' -type f -print0 | while IFS= read -r -d '' f; do
    install -D "$f" "$dest/${f#$src/}"
done
