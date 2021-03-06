(** Toplevel. *)

module Ctx = Context

(** Should the interactive shell be run? *)
let interactive_shell = ref true

(** The command-line wrappers that we look for. *)
let wrapper = ref (Some ["rlwrap"; "ledit"])

(** The predule file *)
let prelude = ref (Some "Prelude.tt")

(** The usage message. *)
let usage = "Usage: tt [option] ... [file] ..."

(** The help text printed when [#help] is used. *)
let help_text = "Toplevel directives:
#eval <expr> ;;                evaluate <expr>
#context ;;                    print current contex
#help ;;                       print this help
#quit ;;                       exit

assume <ident> : <sort> ;;     assume variable <ident> has sort <sort>
define <ident> := <expr> ;;    define <ident> to be <expr>
" ;;

(** A list of files to be loaded and run. *)
let files = ref []

(** Add a file to the list of files to be loaded, and record whether it should
    be processed in interactive mode. *)
let add_file interactive filename = (files := (filename, interactive) :: !files)

(** A list of command-line wrappers to look for. *)
let wrapper = ref (Some ["rlwrap"; "ledit"])

(** Command-line options *)
let options = Arg.align [
  ("--wrapper",
    Arg.String (fun str -> wrapper := Some [str]),
    "<program> Specify a command-line wrapper to be used (such as rlwrap or ledit)");
  ("--no-wrapper",
    Arg.Unit (fun () -> wrapper := None),
    " Do not use a command-line wrapper");
  ("--prelude",
    Arg.String (fun str -> prelude := Some str),
    "<file> Specify an alternate prelude file");
  ("--raw",
    Arg.Unit (fun () ->
       begin
         prelude := None;
         Interp.wrap := false
       end),
    "No wrappers or prelude"
    );
  ("-v",
    Arg.Unit (fun () ->
      print_endline ("tt " ^ Version.version ^ "(" ^ Sys.os_type ^ ")");
      exit 0),
    " Print version information and exit");
  ("-V",
   Arg.Int (fun k -> Print.verbosity := k),
   "<int> Set verbosity level");
  ("-n",
    Arg.Clear interactive_shell,
    " Do not run the interactive toplevel");
  ("-l",
    Arg.String (fun str -> add_file false str),
    "<file> Load <file> into the initial environment");
]

(** Treat anonymous arguments as files to be run. *)
let anonymous str =
  begin
    add_file true str;
    interactive_shell := false
  end

(** Parser wrapper that reads extra lines on demand. *)
let parse parse_it lex =
  try
    parse_it LexerTT.token lex
  with
  | ParserTT.Error ->
      Error.syntax ~loc:(Position.of_lex lex) ""
  | Failure "lexing: empty token" ->
      Error.syntax ~loc:(Position.of_lex lex) "unrecognised symbol."


let uncaught_exception_count = ref 0

(** [exec_cmd env d] executes toplevel directive [d] in context [env]. It prints the
    result if in interactive mode, and returns the new context. *)
let rec exec_cmd interactive (ctx,env) (d, loc) =
  match d with
    | InputTT.Context ->
        let _ = Ctx.print ctx  in
        ctx, env
    | InputTT.TopParam (xs, comp) ->
        begin
          match Interp.toprun ctx env comp with
          | InputTT.RVal v ->
              begin
                let t =
                  match v with
                  | InputTT.VType t, _ -> t
                  | InputTT.VTerm b, _ ->
                      begin
                        match Equal.as_universe ctx (Typing.type_of ctx b) with
                        | Some alpha -> (Syntax.El(alpha, b), loc)
                        | None -> Error.runtime ~loc
                             "Cannot see why classifier %s of %s belongs to a universe"
                             (InputTT.string_of_value ctx v)
                             (String.concat "," xs)
                      end
                  | _ -> Error.runtime ~loc "Classifier %s of %s is not a Andromeda value@."
                               (InputTT.string_of_value ctx v)
                               (String.concat "," xs)  in
                (*let t = Equal.whnf_ty ~use_rws:false ctx t in*)
                let t = Syntax.simplify_ty t in
                      Ctx.add_vars (List.map (fun x -> (x,t)) xs) ctx, env
              end
          | InputTT.ROp (op, _, _, _) ->
              (incr uncaught_exception_count;
              Error.runtime "Uncaught operation %s@." op)
        end
    | InputTT.TopLet (x, comp) ->
        begin
          match Interp.toprun ctx env comp with
          | InputTT.RVal v ->
              ctx, Interp.insert_ttvar x v ctx env
          | InputTT.ROp (op, _, _, _) ->
              (incr uncaught_exception_count;
              Error.runtime "Uncaught operation %s@." op)
        end
    | InputTT.TopEval comp ->
        (begin
          match Interp.toprun ctx env comp with
          | InputTT.RVal v ->
              Format.printf "%s@." (InputTT.string_of_value ~brief:true ctx v)
          | InputTT.ROp (op, _, _, _) ->
              (incr uncaught_exception_count;
              Format.printf "Uncaught operation %s@." op)
        end;
        ctx, env)
    | InputTT.TopDef (x, comp) ->
        begin
          match Interp.toprun ctx env comp with
          | InputTT.RVal v ->
              begin
                match fst v with
                | InputTT.VTerm b ->
                    let b = Syntax.simplify b  in
                    let t = Typing.type_of ctx b  in
                    let t = Syntax.simplify_ty t  in
                    let ctx = Ctx.add_def x t b ctx  in
                    ctx, env
                | _ -> Error.runtime "Result of definition is %s, not a term"
                            (InputTT.string_of_value ~brief:true ctx v)
              end
          | InputTT.ROp (op, _, _, _) ->
              (incr uncaught_exception_count;
              Error.runtime "Uncaught operation %s@." op)
        end
    (*| Input.TopHandler hs ->*)
        (*let hs   = Input.desugar_handler env_names hs   in*)
        (*let env' = Typing.Infer.addHandlers env loc hs in*)
        (*env'*)
    | InputTT.Help ->
      print_endline help_text ;
      ctx, env
    | InputTT.Quit -> exit 0

(** Load directives from the given file. *)
and use_file env (filename, interactive) =
  if Sys.file_exists filename then
    let cmds = LexerTT.read_file (parse ParserTT.file) filename in
    let answer = List.fold_left (exec_cmd interactive) env cmds  in
    let n = ! uncaught_exception_count in
    if n > 0 then
      failwith (string_of_int n ^ " uncaught exceptions")
    else
      answer
  else
    failwith ("No such file: " ^ filename)

(** Interactive toplevel *)
let toplevel env =
  let eof = match Sys.os_type with
    | "Unix" | "Cygwin" -> "Ctrl-D"
    | "Win32" -> "Ctrl-Z"
    | _ -> "EOF"
  in
  print_endline ("tt " ^ Version.version);
  print_endline ("[Type " ^ eof ^ " to exit or \"#help;;\" for help.]");
  try
    let env = ref env in
    while true do
      try
        let cmd = Lexer.read_toplevel (parse ParserTT.commandline) () in
        env := exec_cmd true !env cmd
      with
        | Error.Error err -> Print.error err
        | Sys.Break -> prerr_endline "Interrupted."
    done
  with End_of_file -> ()

(** Main program *)
let main =
  Sys.catch_break true;
  (* Parse the arguments. *)
  Arg.parse options anonymous usage;
  (* Attempt to wrap yourself with a line-editing wrapper. *)
  if !interactive_shell then
    begin match !wrapper with
      | None -> ()
      | Some lst ->
          let n = Array.length Sys.argv + 2 in
          let args = Array.make n "" in
            Array.blit Sys.argv 0 args 1 (n - 2);
            args.(n - 1) <- "--no-wrapper";
            List.iter
              (fun wrapper ->
                 try
                   args.(0) <- wrapper;
                   Unix.execvp wrapper args
                 with Unix.Unix_error _ -> ())
              lst
    end;
  (* Files were listed in the wrong order, so we reverse them *)
  files := List.rev !files;
  (* Set the maximum depth of pretty-printing, after which it prints ellipsis. *)
  Format.set_max_boxes 42 ;
  Format.set_ellipsis_text "..." ;
  try
    (* Load and run the prelude *)
    let env0 = (Context.empty, InputTT.StringMap.empty)  in
    let env0 =
      (match !prelude with
      | Some filename -> use_file env0 (filename, true)
      | None -> env0)  in
    (* Run and load all the specified files. *)
    let env = List.fold_left use_file env0 !files in
    if !interactive_shell then
      toplevel env
    else
      () (*Andromeda.Verify.verifyContext env*)
  with
    Error.Error err -> Print.error err; exit 1
