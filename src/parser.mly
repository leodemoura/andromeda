%{
  open Input

  (* Build nested lambdas *)
  let rec make_lambda e = function
    | [] -> e
    | ((xs, t), loc) :: lst ->
      let e = make_lambda e lst in
        List.fold_right (fun x e -> (Lambda (x, t, e), loc)) xs e

  (* Build nested pi's *)
  let rec make_pi e = function
    | [] -> e
    | ((xs, t), loc) :: lst ->
      let e = make_pi e lst in
        List.fold_right (fun x e -> (Pi (x, t, e), loc)) xs e

  (* Build nested sigma's *)
  let rec make_sigma e = function
    | [] -> e
    | ((xs, t), loc) :: lst ->
      let e = make_sigma e lst in
        List.fold_right (fun x e -> (Sigma (x, t, e), loc)) xs e

%}

%token FORALL EXISTS FUN
%token <int> QUASITYPE
%token <int> TYPE
%token <string> NAME
%token LPAREN RPAREN LBRACK RBRACK
%token COLON DCOLON ASCRIBE COMMA QUESTIONMARK SEMISEMI
%token ARROW DARROW STAR
%token COERCE
%token DOT
%token COLONEQ
%token EQ EQEQ AT
(* %token EVAL *)
%token DEFINE
(*%token LET IN*)
%token ASSUME
%token HANDLE WITH BAR END
(*%token RETURN*)
%token REFLEQUIV REFLEQUAL
%token IND
%token ADMIT
%token QUIT HELP  CONTEXT
%token EOF



%start <Common.variable Input.toplevel list> file
%start <Common.variable Input.toplevel> commandline

%%

(* Toplevel syntax *)

file:
  | filecontents EOF            { $1 }

filecontents:
  |                                { [] }
  | topdef sso filecontents        { $1 :: $3 }
  | topdirective sso filecontents  { $1 :: $3 }
  | tophandler sso filecontents    { $1 :: $3 }

tophandler: mark_position(plain_tophandler) { $1 }
plain_tophandler:
  | WITH handler { TopHandler($2) }

commandline:
  | topdef SEMISEMI        { $1 }
  | topdirective SEMISEMI  { $1 }

(* Things that can be defined on toplevel. *)
topdef: mark_position(plain_topdef) { $1 }
plain_topdef:
  | DEFINE NAME COLONEQ term               { TopDef ($2, $4) }
  | ASSUME nonempty_list(NAME) COLON term  { TopParam ($2, $4) }

(* Toplevel directive. *)
topdirective: mark_position(plain_topdirective) { $1 }
plain_topdirective:
  | CONTEXT    { Context }
  | HELP       { Help }
  | QUIT       { Quit }

sso :
  |          {}
  | SEMISEMI {}

(* Main syntax tree *)

term: mark_position(plain_term) { $1 }
plain_term:
  | plain_arrow_term                  { $1 }
  | FORALL quantifier_abstraction COMMA term  { fst (make_pi $4 $2) }
  | EXISTS quantifier_abstraction COMMA term  { fst (make_sigma $4 $2) }
  | FUN fun_abstraction DARROW term   { fst (make_lambda $4 $2) }
  | t1 = arrow_term ASCRIBE t2 = term { Ascribe (t1, t2) }
  | HANDLE term WITH handler END      { Handle ($2, $4) }

arrow_term: mark_position(plain_arrow_term) { $1 }
plain_arrow_term:
  | plain_star_term              { $1 }
  | star_term ARROW arrow_term   { Pi ("_", $1, $3) }
  | LPAREN NAME COLON term RPAREN ARROW arrow_term      { Pi($2, $4, $7) }

star_term: mark_position(plain_star_term) { $1 }
plain_star_term:
  | plain_equiv_term                               { $1 }
  | equiv_term STAR star_term                      { Sigma ("_", $1, $3) }
  | LPAREN NAME COLON term RPAREN STAR star_term   { Sigma($2, $4, $7) }

equiv_term: mark_position(plain_equiv_term) { $1 }
plain_equiv_term:
    | plain_app_term                       { $1 }
    | app_term EQEQ app_term AT app_term   { Equiv (Ju, $1, $3, $5) }
    | app_term EQ app_term AT app_term     { Equiv (Pr, $1, $3, $5) }

app_term: mark_position(plain_app_term) { $1 }
plain_app_term:
  | plain_simple_term      { $1 }
  | app_term simple_term   { App ($1, $2) }
  | REFLEQUIV simple_term          { Refl(Ju, $2) }
  | REFLEQUAL simple_term          { Refl(Pr, $2) }
  | IND LPAREN
          q = term
        COMMA
          x = NAME DOT
          y = NAME DOT
          p = NAME DOT
          t = term
        COMMA
          z = NAME DOT
          u = term
        RPAREN
        { Ind((x, y, p, t), (z, u), q) }

simple_term: mark_position(plain_simple_term) { $1 }
plain_simple_term:
  | NAME                           { Var $1 }
  | TYPE                 { Universe (Fib $1) }
  | QUASITYPE            { Universe (NonFib $1) }
  | LPAREN plain_term RPAREN       { $2 }
  | LPAREN term COMMA term RPAREN  { Pair($2, $4) }
  | LBRACK plain_operation RBRACK  { let (tag,args) = $2 in Operation(tag,args) }
  | simple_term DOT NAME           { Proj($3, $1) }
  | QUESTIONMARK                   { Wildcard }
  | ADMIT                          { Admit }

handler:
  | BAR? cs=separated_list(BAR, handler_case)  { cs }

handler_case:
  | LBRACK plain_operation RBRACK DARROW computation
                                            { let (tag,args) = $2 in (tag,args, $5) }
  | term                                    { (Inhabit, [], $1) }

(*
computation: mark_position(plain_computation) { $1 }
plain_computation:
  | RETURN term                                  { Return $2 }
  | LPAREN plain_computation RPAREN              { $2 }
  | LET NAME COLONEQ term IN computation         { Let ($2, $4, $6) }
  *)
computation: term { $1 }

(*operation: mark_position(plain_operation) { $1 }*)
plain_operation:
    | QUESTIONMARK DCOLON term        { (Inhabit, [$3]) }
    | term                            { (Inhabit, [$1]) }
    | term COERCE term                { (Coerce, [$1; $3]) }

quantifier_abstraction:
  | quantifier_bind1  { [$1] }
  | quantifier_binds  { $1 }

quantifier_bind1: mark_position(plain_quantifier_bind1) { $1 }
plain_quantifier_bind1:
  | xs=nonempty_list(NAME) COLON t=term  { (xs, t) }

quantifier_binds:
  | LPAREN quantifier_bind1 RPAREN           { [$2] }
  | LPAREN quantifier_bind1 RPAREN quantifier_binds  { $2 :: $4 }

fun_abstraction:
  | fun_bind1  { [$1] }
  | fun_binds  { $1 }

fun_bind1: mark_position(plain_fun_bind1) { $1 }
plain_fun_bind1:
  | xs=nonempty_list(NAME)             { (xs, None) }
  | xs=nonempty_list(NAME) COLON term  { (xs, Some $3) }

fun_binds:
  | LPAREN fun_bind1 RPAREN            { [$2] }
  | LPAREN fun_bind1 RPAREN fun_binds  { $2 :: $4 }

mark_position(X):
  x = X
  { x, Common.Position ($startpos, $endpos) }

%%