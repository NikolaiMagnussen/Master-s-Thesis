open Lwt
open Cohttp
open Cohttp_mirage
open Capability_t

module Auth (CON : Conduit_mirage.S) = struct
  module S = Cohttp_mirage.Server(Conduit_mirage.Flow)

  let token_map =
    let tbl = Hashtbl.create 0 in
    Hashtbl.add tbl "4a183696-c4cc-48fe-90b9-831147ec12a2" `Unclassified;
    Hashtbl.add tbl "fefb7751-7893-435e-82fd-25f0becb3c64" `TopSecret;
    tbl

  let unauthorized_login =
    let headers = Header.init_with "www-authenticate" "Bearer realm=\"proxy.local\"" in
    S.respond ~headers ~status: `Unauthorized ~body: `Empty

  let check_token token =
    match Hashtbl.find_opt token_map token with
    | Some cap -> let headers = Header.init_with "capabilities" (Capability_j.string_of_capability cap) in
      S.respond ~status: `OK ~headers ~body: `Empty ()
    | None -> unauthorized_login ()

  let handle_token token =
    match String.split_on_char ' ' token with
    | "Bearer" :: content_l -> 
      let content = String.concat "" content_l in
      check_token content
    | _ -> unauthorized_login ()

  let handle path meth headers body conduit =
    match Header.get_authorization headers with
    | Some `Other token -> handle_token token
    | Some `Basic _ | None -> let headers = Header.init_with "www-authenticate" "Bearer realm=\"proxy.local\"" in
      S.respond ~headers ~status: `Unauthorized ~body: `Empty ()

  let start conduit =
    let callback _conn req body =
      let path = req |> Request.uri |> Uri.path in
      let meth = Request.meth req in
      let headers = Request.headers req in
      handle path meth headers body conduit
    in
    let spec = S.make ~callback () in
    CON.listen conduit (`TCP (Key_gen.port ())) (S.listen spec)
end
