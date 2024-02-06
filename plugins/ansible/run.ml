open Lwt.Infix

type t = {
  commit : Current_git.Commit.t;
}

let id = "ansible-playbook"

module Key = struct
  type t = {
    playbook : Playbook.t;
  }

  let digest t = Playbook.marshal t.playbook

  let pp f t = Playbook.pp f t.playbook
end

module Value = Current.Unit

let with_context ~job context fn =
  let open Lwt_result.Infix in
  match context with
  | `No_context -> Current.Process.with_tmpdir ~prefix:"ansible-context-" fn
  | `Dir path ->
      Current.Process.with_tmpdir ~prefix:"ansible-context-" @@ fun dir ->
      Current.Process.exec ~cwd:dir ~cancellable:true ~job ("", [| "rsync"; "-aHq"; Fpath.to_string path ^ "/"; "." |]) >>= fun () ->
      fn dir
  | `Git commit -> Current_git.with_checkout ~job commit fn

let build { commit } job key =
  let { Key.playbook } = key in
  Current.Job.start job ~level:Current.Level.Mostly_harmless >>= fun () ->
  Current_git.with_checkout ~job commit @@ fun dir ->
          (*
          let _ = playbook in
          let _ = commit in
          Lwt_result.return ()
          *)
  let inventory = match Playbook.inventory playbook with
  | Some i -> ["-i"; i]
  | None -> [] in
  let limit = match Playbook.limit playbook with
  | Some l -> ["--limit"; String.concat "," l]
  | None -> [] in
  let cmd = "", Array.of_list (["ansible-playbook"] @ inventory @ limit @ [Playbook.name playbook]) in
  let pp_error_command f = Fmt.string f "ansible-playbook" in
  Current.Process.exec ~cwd:dir ~cancellable:true ~pp_error_command ~job cmd >|= function
  | Error _ as e -> e
  | Ok () -> Stdlib.Result.ok ()

let pp f key = Fmt.pf f "@[<v2>Ansible parameters %a@]" Key.pp key

let auto_cancel = true
