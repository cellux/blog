#!/bin/bash

if [ -n "$(cd . && git status -s)" ]; then
  echo "There are uncommitted changes in ."
  exit 1
fi

wintersmith build --clean
rsync -av --delete --exclude .git build/ blog/

if [ -n "$(cd blog && git status -s)" ]; then
  echo "There are uncommitted changes in ./blog"
  exit 1
fi

(cd . && git push)
(cd ./blog && git push)

