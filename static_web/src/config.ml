open Mirage

let port =
  let doc = Key.Arg.info ~doc:"What port to listen on." ["port"] in
  Key.(create "port" Arg.(opt int 8000 doc))

let main =
  foreign
    ~keys:[Key.abstract port]
    "Unikernel.Static" (conduit @-> job)

let () =
  let packages = [
    package "uri";
    package "mirage-conduit";
    package "cohttp-mirage";
    package ~ocamlfind:[] "mirage-solo5";
  ] in
  register ~packages "static" [main $ conduit_direct (generic_stackv4 default_network)]
