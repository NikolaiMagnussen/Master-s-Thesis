open Lwt
open Cohttp
open Cohttp_mirage
open Handlers

module Static (CON : Conduit_mirage.S) = struct
  module S = Cohttp_mirage.Server(Conduit_mirage.Flow)

  (*
  let generate_router routes key =
    List.assoc_opt key routes

  let routes = [
    (("/", `GET), Handlers.static_page);
  ]

  let handle uri meth headers body conduit =     
    let router = generate_router routes in
    let endpoint_handler = router (uri, meth) in
    let h = Header.init() in
    match endpoint_handler with
    | Some fn -> fn body headers conduit >>= fun (s, b, c) ->
      let headers = Header.add_list h c in  
      S.respond_string ~headers ~status: s ~body: b ()  
    | None -> Cohttp_lwt.Body.to_string body >>= fun body ->
      S.respond_string ~status: `Not_found ~body: ("404 NOT FOUND: " ^ (Code.string_of_method meth) ^ " to " ^ uri ^ ": " ^ body) ()  
      *)

  let start conduit =
    let callback _conn _req _body =
      S.respond_string ~status: `OK ~body: "Some static string" ()
    in
    let spec = S.make ~callback () in
    CON.listen conduit (`TCP (Key_gen.port ())) (S.listen spec)
end
