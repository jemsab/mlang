(* FIXME: scope is only to know variables stored in ctx by previous computation.
          We don't check that local variables read have been defined previously *)
open Mpp_ast

let to_scoped_var ?(scope=Input) (p: Mvg.program) (var: Cst.var) : scoped_var =
  if String.uppercase_ascii var = var then begin
    (* we have an MBased variable *)
      Mbased (Mvg.find_var_by_name p var, scope)
    end
  else Local var

let to_mpp_callable cname translated_names =
  match cname with
  | "present" -> Present
  | "abs" -> Abs
  | "cast" -> Cast
  | "exists_deposit_defined_variables" -> DepositDefinedVariables
  | "exists_taxbenefit_defined_variables" -> TaxbenefitDefinedVariables
  | "exists_taxbenefit_ceiled_variables" -> TaxbenefitCeiledVariables
  | "evaluate_program" -> Program
  | x -> if List.mem x translated_names then MppFunction x
         else raise (Errors.ParsingError (Format.asprintf "unknown callable %s" x))

let rec to_mpp_expr p translated_names scope (e: Cst.expr) : mpp_expr * Cst.var list =
  match e with
  | Constant i ->
     Constant i, scope
  | Variable v ->
     Variable (to_scoped_var ~scope:(if List.mem v scope then Output else Input) p v), scope
  | Unop(Minus, e) ->
     let e', scope = to_mpp_expr p translated_names scope e in
     Unop(Minus, e'), scope
  | Call(c, args) ->
     let c' = to_mpp_callable c translated_names in
     let new_scope = args in
     let args' = List.map (to_scoped_var p) args in
     Call(c', args'), new_scope
  | Binop(e1, b, e2) ->
     Binop(
         fst @@ to_mpp_expr p translated_names scope e1,
         b,
         fst @@ to_mpp_expr p translated_names scope e2), scope

let to_mpp_filter f =
  if f = "var_is_taxbenefit" then
    VarIsTaxBenefit
  else
    raise (Errors.ParsingError (Format.asprintf "unknown filter %s" f))

let rec to_mpp_stmt p translated_names scope (stmt: Cst.stmt) : mpp_stmt * Cst.var list =
  match stmt with
  | Assign(v, e) ->
     Assign(
         to_scoped_var p v,
         fst @@ to_mpp_expr p translated_names scope e), scope
  | Conditional(b, t, f) ->
     Conditional(
         fst @@ to_mpp_expr p translated_names scope b,
         to_mpp_stmts p translated_names ~scope:scope t,
         to_mpp_stmts p translated_names ~scope:scope f), scope
  | Delete v ->
     Delete (to_scoped_var p v), scope
  | Expr e ->
     let e', scope = to_mpp_expr p translated_names scope e in
     Expr e', scope
  | Partition (f, body) ->
     Partition(
         to_mpp_filter f,
         to_mpp_stmts p translated_names ~scope:scope body), scope


and to_mpp_stmts p translated_names ?(scope=[]) (stmts: Cst.stmt list) : mpp_stmt list =
  List.rev @@ fst @@ List.fold_left
                       (fun (translated_stmts, scope) cstmt ->
                         let stmt, scope = to_mpp_stmt p translated_names scope cstmt in
                         stmt :: translated_stmts, scope)
                       ([], scope) stmts

let cdef_to_adef p translated_names cdef : Mpp_ast.mpp_compute =
  let name = cdef.Cst.name in
  assert(not @@ List.mem name translated_names);
  {name;
   args=[]; (* FIXME *)
   body=to_mpp_stmts p translated_names cdef.body}

let cst_to_ast (c: Cst.program) (p: Mvg.program) : Mpp_ast.mpp_program =
  List.rev @@ fst @@ List.fold_left (fun (mpp_acc, translated_names) cdef ->
                  (cdef_to_adef p translated_names cdef :: mpp_acc, cdef.Cst.name :: translated_names)) ([], []) c

let process (ompp_file: string option) (p: Mvg.program) : mpp_program option =
  match ompp_file with
  | None -> None
  | Some mpp_file ->
      Cli.debug_print "Reading m++ file %s" mpp_file;
      let f = open_in mpp_file in
      let buf = Lexing.from_channel f in
      buf.lex_curr_p <- { buf.lex_curr_p with pos_fname = mpp_file };
      try
        let cst = Mpp_parser.file Mpp_lexer.next_token buf in
        close_in f; Some (cst_to_ast cst p)
      with
      | Mpp_parser.Error ->
         let b = Lexing.lexeme_start_p buf in
         let e = Lexing.lexeme_end_p buf in
         let l = b.pos_lnum in
         let fc = b.pos_cnum - b.pos_bol + 1 in
         let lc = e.pos_cnum - b.pos_bol + 1 in
         let () = Cli.error_print "File \"%s\", line %d, characters %d-%d:\n@." mpp_file l fc lc in
         None
      | Errors.LexingError e
        | Errors.ParsingError e ->
         let () = Cli.error_print "Parsing Error %s" e in
         None
