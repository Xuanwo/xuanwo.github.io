setup:
	# gitalk related assets
	cp node_modules/gitalk/dist/gitalk.css assets/css/gitalk.css
	cp node_modules/gitalk/dist/gitalk.min.js assets/javascript/gitalk.min.js
	# docsearch related assets
	cp node_modules/docsearch.js/dist/cdn/docsearch.min.css assets/css/docsearch.min.css
	cp node_modules/alpinejs/dist/alpine.js assets/javascript/alpine.js

.PHONY: server
server: setup
	hugo server --minify --disableFastRender -F --ignoreCache -w

.PHONY: build
build: setup
	hugo --minify
