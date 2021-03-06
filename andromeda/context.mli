type t

type hint = int * Pattern.ty * Pattern.term * Pattern.term

val empty : t

val names : t -> string list

val add_var : Syntax.name -> Syntax.ty -> t -> t

val add_vars : (Syntax.name * Syntax.ty) list -> t -> t

val for_J : Syntax.ty -> Syntax.name -> Syntax.name -> Syntax.name -> Syntax.name -> t -> t * t

val add_def : Syntax.name -> Syntax.ty -> Syntax.term -> t -> t

val add_equation : hint -> t -> t

val add_rewrite : hint -> t -> t

val lookup_var : Syntax.variable -> t -> Syntax.ty

val lookup_def : Syntax.variable -> t -> Syntax.term option

val rewrites : t -> hint list

val equations : t -> hint list

val append : t -> t -> t

val print : ?label:string -> t -> unit

val pop_var : t -> t

val pop_vars: int -> t -> t

