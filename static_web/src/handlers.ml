open Lwt
open Cohttp
open Cohttp_lwt

module Handlers = struct
  let static_page _body _headers _conduit =
    Lwt.return (`OK, "This is a static string", [])
end
