.PHONY: all build deploy clean br0 tap%
all: build

build: proxy/src/proxy.hvt static_web/src/static.hvt auth/src/auth.hvt vmmd/src/_build/default/vmmd.exe

proxy/src/proxy.hvt: proxy/src/*.ml
	cd proxy/src/ && mirage configure -t hvt && mirage build

static_web/src/static.hvt: static_web/src/*.ml
	cd static_web/src/ && mirage configure -t hvt && mirage build

auth/src/auth.hvt: auth/src/*.ml
	cd auth/src/ && mirage configure -t hvt && mirage build

vmmd/src/_build/default/vmmd.exe: vmmd/src/*.ml
	cd vmmd/src/ && dune build vmmd.exe

br0: 
	@ip link | grep ": br0:" || ($(info "Bridge not available ($@) - creating one") sudo ip link add br0 type bridge && sudo ip addr add 10.0.0.1/24 dev br0 && sudo ip link set dev br0 up)

tap%: br0
	@ip link | grep ": $@:" || ($(info "Tap not available ($@) - creating one") sudo ip tuntap add $@ mode tap && sudo ip link set $@ master $< && sudo ip link set dev $@ up)

deploy: /dev/kvm tap0 tap1 tap2 build
	proxy/src/solo5-hvt --net=tap0 proxy/src/proxy.hvt --ipv4=10.0.0.2/24 & disown
	auth/src/solo5-hvt --net=tap1 auth/src/auth.hvt --ipv4=10.0.0.3/24 & disown
	static_web/src/solo5-hvt --net=tap2 static_web/src/static.hvt --ipv4=10.0.0.4/24 --interactive=true & disown
	sudo vmmd/src/_build/default/vmmd.exe -v -d -i 129.242.181.244 -p 8000 2>&1 & disown

destroy:
	- sudo pkill solo5-hvt
	- sudo pkill vmmd.exe
	- sudo ip link del dev br0
	- sudo ip tuntap del tap0 mode tap
	- sudo ip tuntap del tap1 mode tap
	- sudo ip tuntap del tap2 mode tap

clean:
	- cd proxy/src/ && rm -rf _build/ && mirage clean
	- cd static_web/src/ && rm -rf _build/ && mirage clean
	- cd auth/src/ && rm -rf _build && mirage clean
	- cd vmmd/src/ && rm -rf _build/
