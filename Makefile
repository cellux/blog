.PHONY: build preview push
build:
	wintersmith build --clean
	rsync -av --delete --exclude .git build/ blog/

preview:
	wintersmith preview

push:
	sh push.sh
