#!/bin/bash

if [ -n "$(git status -s)" ]; then
  echo "There are uncommitted changes in ."
  exit 1
fi

wintersmith build

if [ -n "$(git status -s build)" ]; then
  echo "There are uncommitted changes in ./build"
  exit 1
fi

(cd . && git push)
(cd ./build && git push)

