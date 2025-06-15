englishWordsCnt := $(shell find book -iname "*.md" -print0 | grep -z -v zh_CN | grep -z -v _book | grep -z -v node_modules |  wc -m --files0-from - | tail -n 1 | cut -f1)

deploy := https://github.com/hitzhangjie/debugger101-en.io
tmpdir := /tmp/debugger101-en.io
book := book

.PHONY: english chinese stat clean deploy

PWD := $(shell pwd -P)

english:
	rm -rf book/_book
	#gitbook install book
	#gitbook serve book
	docker run --name gitbook --rm -v ${PWD}/book:/root/gitbook hitzhangjie/gitbook-cli:latest gitbook install .
	docker run --name gitbook --rm -v ${PWD}/book:/root/gitbook -p 4000:4000 -p 35729:35729 hitzhangjie/gitbook-cli:latest gitbook serve .

pdf:
	@echo "Warn: must do it mannually so far for lack of proper docker image,"
	@echo "- install 'calibre' first (see https://calibre-ebook.com/download),"
	@echo "- make sure 'ebook-convert' could be found in envvar 'PATH',"
	@echo "  take macOS for example:"
	@echo "  run 'sudo ln -s /Applications/calibre.app/Contents/MacOS/ebook-convert /usr/bin'."
	@echo "- run 'gitbook pdf <book> <book.pdf>'"
	@echo ""

stat:
	@echo "English version, words: ${englishWordsCnt}"

clean:
	rm -rf book/_book
	#rm -rf ./node_modules

deploy:
	# ./deploy.sh
	rm -rf ${tmpdir}
	echo "deploying updates to GitHub..."
	git clone ${deploy} ${tmpdir}
	docker run --name gitbook --rm -v ${PWD}:/root/gitbook -v ${tmpdir}:${tmpdir} hitzhangjie/gitbook-cli:latest gitbook build ${book} tmpdir
	cp -r tmpdir/* ${tmpdir}/
	rm -rf tmpdir
	cd ${tmpdir}
	git add .
	git commit -m "rebuilding site"
	git push -f -u origin master
	rm -rf ${tmpdir}

