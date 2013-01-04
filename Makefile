.PHONY: build preview push
build:
	wintersmith build --clean

preview:
	wintersmith preview

push:
	sh push.sh
