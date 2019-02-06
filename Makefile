.PHONY: all build deploy clean
all: build

build: proxy/src/proxy.hvt static_web/src/static.hvt auth/src/auth.hvt

proxy/src/proxy.hvt:
	cd proxy/src/ && mirage configure -t hvt && mirage build

static_web/src/static.hvt:
	cd static_web/src/ && mirage configure -t hvt && mirage build

auth/src/auth.hvt:
	cd auth/src/ && mirage configure -t hvt && mirage build

deploy: build
	proxy/src/solo5-hvt --net=tap0 proxy/src/proxy.hvt --ipv4=10.0.0.2/24 & disown
	auth/src/solo5-hvt --net=tap1 auth/src/auth.hvt --ipv4=10.0.0.3/24 & disown
	static_web/src/solo5-hvt --net=tap2 static_web/src/static.hvt --ipv4=10.0.0.4/24 & disown

destroy:
	pkill solo5-hvt

clean:
	- cd proxy/src/ && rm -rf _build/ && mirage clean
	- cd static_web/src/ && rm -rf _build/ && mirage clean
	- cd auth/src/ && rm -rf _build && mirage clean
