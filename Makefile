.PHONY: build preview push
build:
	wintersmith build

preview:
	wintersmith preview

push:
	sh push.sh
