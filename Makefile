BENCH_NUM = 100

.PHONY: all build_bench run_bench bench_tap bench_unikernel build deploy clean br0 tap% no_iptables
all: build

build: proxy/src/proxy.hvt static_web/src/static.hvt auth/src/auth.hvt vmmd/src/_build/default/vmmd.exe

build_bench: benchmarks/src/_build/default/bench_tap.exe benchmarks/src/_build/default/bench_unikernel.exe

run_bench: bench_tap bench_unikernel

bench_tap: benchmarks/src/_build/default/bench_tap.exe br0
	cd benchmarks/src/ && sudo ./_build/default/bench_tap.exe $(BENCH_NUM)

bench_unikernel: benchmarks/src/_build/default/bench_unikernel.exe tap0 /dev/kvm
	cd benchmarks/src/ && sudo ./_build/default/bench_unikernel.exe $(BENCH_NUM)

proxy/src/proxy.hvt: proxy/src/*.ml
	cd proxy/src/ && mirage configure -t hvt && mirage build

static_web/src/static.hvt: static_web/src/*.ml
	cd static_web/src/ && mirage configure -t hvt && mirage build

auth/src/auth.hvt: auth/src/*.ml
	cd auth/src/ && mirage configure -t hvt && mirage build

vmmd/src/_build/default/vmmd.exe: vmmd/src/*.ml
	cd vmmd/src/ && dune build vmmd.exe

no_iptables: /proc/sys/net/bridge/bridge-nf-call-iptables
	echo 0 | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables

br0: no_iptables
	@ip link | grep ": br0:" || ($(info "Bridge not available ($@) - creating one") sudo ip link add br0 type bridge && sudo ip addr add 10.0.0.1/24 dev br0 && sudo ip link set dev br0 up)

tap%: br0
	@ip link | grep ": $@:" || ($(info "Tap not available ($@) - creating one") sudo ip tuntap add $@ mode tap && sudo ip link set $@ master $< && sudo ip link set dev $@ up)


benchmarks/src/_build/default/bench_tap.exe: benchmarks/src/bench_tap.ml
	cd benchmarks/src/ && dune build bench_tap.exe

benchmarks/src/_build/default/bench_unikernel.exe: benchmarks/src/bench_unikernel.ml
	cd benchmarks/src/ && dune build bench_unikernel.exe

deploy: /dev/kvm tap0 tap1 tap2 build
	proxy/src/solo5-hvt --net=tap0 proxy/src/proxy.hvt --ipv4=10.0.0.2/24 & disown
	auth/src/solo5-hvt --net=tap1 auth/src/auth.hvt --ipv4=10.0.0.3/24 & disown
	static_web/src/solo5-hvt --net=tap2 static_web/src/static.hvt --ipv4=10.0.0.4/24 --interactive=true & disown
	sudo vmmd/src/_build/default/vmmd.exe -v -d -i 129.242.181.244 -p 8000 2>&1 & disown

deploy_aot: /dev/kvm tap0 tap1 tap2 build
	sudo vmmd/src/_build/default/vmmd.exe -v --debug -i 129.242.183.7 -p 8000 & disown
	sleep 1
	curl -X POST \
	  http://localhost:8000/ \
	  -H 'Authorization: Bearer fefb7751-7893-435e-82fd-25f0becb3c64' \
	  -H 'Postman-Token: f2f8a9b9-b847-4c96-ad30-b1135850ca38' \
	  -H 'cache-control: no-cache' \
	  -d '{"name": "kake", "path": "/home/kongen/sshfs-dev/Master_Thesis/static_web/src/static.hvt", "level": "TopSecret"}'
	auth/src/solo5-hvt --net=tap1 auth/src/auth.hvt --ipv4=10.0.0.3/24 & disown
	sleep 1
	proxy/src/solo5-hvt --net=tap0 proxy/src/proxy.hvt --ipv4=10.0.0.2/24 --aot=true & disown


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
	- cd vmmd/src/ && dune clean
	- cd benchmarks/src/ && dune clean
