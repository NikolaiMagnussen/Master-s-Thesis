open Mirage

let port =
  let doc = Key.Arg.info ~doc:"What port to listen on." ["port"] in
  Key.(create "port" Arg.(opt int 8000 doc))

let aot =
  let doc = Key.Arg.info ~doc:"Should unikernels be spawned ahead-of-time." ["aot"] in
  Key.(create "aot" Arg.(opt bool false doc))

let main =
  foreign
    ~keys:[Key.abstract port; Key.abstract aot]
    "Unikernel.Proxy" (conduit @-> job)

let () =
  let packages = [
    package "uri";
    package "biniou";
    package "yojson";
    package "ezjsonm";
    package "atdgen";
    package "mirage-conduit";
    package "cohttp-mirage";
    package ~ocamlfind:[] "mirage-solo5";
  ] in
  register ~packages "proxy" [main $ conduit_direct (generic_stackv4 default_network)]
