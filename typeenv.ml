open Types

exception TypeCheckError of string

type type_variable_id = int
type type_environment = (var_name * type_struct) list
and type_struct =
  | TypeEnvironmentType of code_range * type_environment
  | UnitType     of code_range
  | IntType      of code_range
  | StringType   of code_range
  | BoolType     of code_range
  | FuncType     of code_range * type_struct * type_struct
  | ListType     of code_range * type_struct
  | RefType      of code_range * type_struct
  | ProductType  of code_range * (type_struct list)
  | ForallType   of type_variable_id * type_struct
  | TypeVariable of code_range * type_variable_id

(* !!!! ---- global variable ---- !!!! *)
let global_hash_env : environment = Hashtbl.create 32

(* -- for test -- *)
let rec string_of_utast (_, utast) =
  match utast with
  | UTStringEmpty         -> "{}"
  | UTNumericConstant(nc) -> string_of_int nc
  | UTBooleanConstant(bc) -> string_of_bool bc
  | UTStringConstant(sc)  -> "{" ^ sc ^ "}"
  | UTUnitConstant        -> "()"
  | UTContentOf(varnm)    -> varnm
  | UTConcat(ut1, ut2)    -> "(" ^ (string_of_utast ut1) ^ " ^ " ^ (string_of_utast ut2) ^ ")"
  | UTApply(ut1, ut2)     -> "(" ^ (string_of_utast ut1) ^ " " ^ (string_of_utast ut2) ^ ")"
  | UTListCons(hd, tl)    -> "(" ^ (string_of_utast hd) ^ " :: " ^ (string_of_utast tl) ^ ")" 
  | UTEndOfList           -> "[]"
  | UTTupleCons(hd, tl)   -> "(" ^ (string_of_utast hd) ^ ", " ^ (string_of_utast tl) ^ ")"
  | UTEndOfTuple          -> "$"
  | UTBreakAndIndent      -> "{\\break;}"
  | UTLetIn(umlc, ut)     -> "(let ... in " ^ (string_of_utast ut) ^ ")"
  | UTIfThenElse(ut1, ut2, ut3)
      -> "(if " ^ (string_of_utast ut1) ^ " then " ^ (string_of_utast ut2) ^ " else " ^ (string_of_utast ut3) ^ ")"
  | UTLambdaAbstract(_, varnm, ut) -> "(" ^ varnm ^ " -> " ^ (string_of_utast ut) ^ ")"
  | UTFinishHeaderFile    -> "finish"
  | UTPatternMatch(ut, pmcons) -> "(match " ^ (string_of_utast ut) ^ " with" ^ (string_of_pmcons pmcons) ^ ")"
  | _ -> "?"
and string_of_pmcons (_, pmcons) =
  match pmcons with
  | UTEndOfPatternMatch -> ""
  | UTPatternMatchCons(pat, ut, tail)
      -> " | " ^ (string_of_pat pat) ^ " -> " ^ (string_of_utast ut) ^ (string_of_pmcons tail)
and string_of_pat (_, pat) =
  match pat with
  | UTPNumericConstant(nc) -> string_of_int nc
  | UTPBooleanConstant(bc) -> string_of_bool bc
  | UTPUnitConstant        -> "()"
  | UTPListCons(hd, tl)    -> (string_of_pat hd) ^ " :: " ^ (string_of_pat tl)
  | UTPEndOfList           ->  "[]"
  | UTPTupleCons(hd, tl)   -> "(" ^ (string_of_pat hd) ^ ", " ^ (string_of_pat tl) ^ ")"
  | UTPEndOfTuple          -> "$"
  | UTPWildCard            -> "_"
  | UTPVariable(varnm)     -> varnm


let rec string_of_ast ast =
  match ast with
  | LambdaAbstract(x, m)         -> "(" ^ x ^ " -> " ^ (string_of_ast m) ^ ")"
  | FuncWithEnvironment(x, m, _) -> "(" ^ x ^ " *-> " ^ (string_of_ast m) ^ ")"
  | ContentOf(v)           -> v
  | Apply(m, n)            -> "(" ^ (string_of_ast m) ^ " " ^ (string_of_ast n) ^ ")"
  | Concat(s, t)           -> (string_of_ast s) ^ (string_of_ast t)
  | StringEmpty            -> ""
  | StringConstant(sc)     -> "{" ^ sc ^ "}"
  | NumericConstant(nc)    -> string_of_int nc
  | BooleanConstant(bc)    -> string_of_bool bc
  | IfThenElse(b, t, f)    ->
      "(if " ^ (string_of_ast b) ^ " then " ^ (string_of_ast t) ^ " else " ^ (string_of_ast f) ^ ")"
  | IfClassIsValid(t, f)   -> "(if-class-is-valid " ^ (string_of_ast t) ^ " else " ^ (string_of_ast f) ^ ")"
  | Reference(a)           -> "!" ^ (string_of_ast a)
  | ReferenceFinal(a)      -> "!!" ^ (string_of_ast a)
  | Overwrite(vn, n)       -> "(" ^ vn ^ " <- " ^ (string_of_ast n) ^ ")"
  | MutableValue(mv)       -> "(mutable " ^ (string_of_ast mv) ^ ")"
  | UnitConstant           -> "()"
  | LetMutableIn(vn, d, f) -> "(let-mutable " ^ vn ^ " <- " ^ (string_of_ast d) ^ " in " ^ (string_of_ast f) ^ ")"
  | _ -> "..."


let print_for_debug msg =
(* enable below to see the process of type inference *)
(*
  print_string msg ;
*)
  ()

(* untyped_abstract_tree -> code_range *)
let get_range utast =
  let (rng, _) = utast in rng

let is_invalid_range rng =
  let (sttln, _, _, _) = rng in sttln <= 0

let get_range_from_type tystr =
  match tystr with
  | IntType(rng)         -> rng
  | StringType(rng)      -> rng
  | BoolType(rng)        -> rng
  | UnitType(rng)        -> rng
  | TypeVariable(rng, _) -> rng
  | FuncType(rng, _, _)  -> rng
  | ListType(rng, _)     -> rng
  | RefType(rng, _)      -> rng
  | ProductType(rng, _)  -> rng
  | TypeEnvironmentType(rng, _) -> rng
  | ForallType(_, _)     -> (-31, 0, 0, 0)

let overwrite_range_of_type tystr rng =
  match tystr with
  | IntType(_)                -> IntType(rng)
  | StringType(_)             -> StringType(rng)
  | BoolType(_)               -> BoolType(rng)
  | UnitType(_)               -> UnitType(rng)
  | TypeVariable(_, tvid)     -> TypeVariable(rng, tvid)
  | FuncType(_, tydom, tycod) -> FuncType(rng, tydom, tycod)
  | ListType(_, tycont)       -> ListType(rng, tycont)
  | RefType(_, tycont)        -> RefType(rng, tycont)
  | ProductType(_, tylist)    -> ProductType(rng, tylist)
  | TypeEnvironmentType(_, tyenv)  -> TypeEnvironmentType(rng, tyenv)
  | ForallType(tvid, tycont)       -> ForallType(tvid, tycont)

let rec erase_range_of_type tystr =
  let dummy = (-2048, 0, 0, 0) in
    match tystr with
    | IntType(_)                -> IntType(dummy)
    | StringType(_)             -> StringType(dummy)
    | BoolType(_)               -> BoolType(dummy)
    | UnitType(_)               -> UnitType(dummy)
    | TypeVariable(_, tvid)     -> TypeVariable(dummy, tvid)
    | FuncType(_, tydom, tycod) -> FuncType(dummy, erase_range_of_type tydom, erase_range_of_type tycod)
    | ListType(_, tycont)       -> ListType(dummy, erase_range_of_type tycont)
    | RefType(_, tycont)        -> RefType(dummy, erase_range_of_type tycont)
    | ProductType(_, tylist)    -> ProductType(dummy, erase_range_of_type_list tylist)
    | TypeEnvironmentType(_, tyenv) -> TypeEnvironmentType(dummy, tyenv)
    | ForallType(tvid, tycont)      -> ForallType(tvid, erase_range_of_type tycont)

and erase_range_of_type_list tylist =
  match tylist with
  | []           -> []
  | head :: tail -> (erase_range_of_type head) :: (erase_range_of_type_list tail)

let describe_position (sttln, sttpos, endln, endpos) =
  if sttln = endln then
    "line " ^ (string_of_int sttln) ^ ", characters " ^ (string_of_int sttpos)
      ^ "-" ^ (string_of_int endpos)
  else
    "line " ^ (string_of_int sttln) ^ ", character " ^ (string_of_int sttpos)
      ^ " to line " ^ (string_of_int endln) ^ ", character " ^ (string_of_int endpos)

let error_reporting rng errmsg = (describe_position rng) ^ ":\n    " ^ errmsg


(* -- for debug -- *)
let rec string_of_type_struct_basic tystr =
  let (sttln, _, _, _) = get_range_from_type tystr in
    match tystr with
    | StringType(_) -> if sttln <= 0 then "string" else "string+"
    | IntType(_)    -> if sttln <= 0 then "int"    else "int+"
    | BoolType(_)   -> if sttln <= 0 then "bool"   else "bool+"
    | UnitType(_)   -> if sttln <= 0 then "unit"   else "unit+"
    | TypeEnvironmentType(_, _)  -> if sttln <= 0 then "env" else "env+"
    | TypeVariable(_, tvid)      -> "'" ^ (string_of_int tvid) ^ (if sttln <= 0 then "+" else "")

    | FuncType(_, tydom, tycod)  ->
        let strdom = string_of_type_struct_basic tydom in
        let strcod = string_of_type_struct_basic tycod in
        ( match tydom with
          | FuncType(_, _, _) -> "(" ^ strdom ^ ")"
          | ProductType(_, _) -> "(" ^ strdom ^ ")"
          | _                 -> strdom
        ) ^ " ->" ^ (if sttln <= 0 then "+ " else " ") ^ strcod

    | ListType(_, tycont)        ->
        let strcont = string_of_type_struct_basic tycont in
        ( match tycont with
          | FuncType(_, _, _) -> "(" ^ strcont ^ ")"
          | ProductType(_, _) -> "(" ^ strcont ^ ")"
          | _                 -> strcont
        ) ^ " list" ^ (if sttln <= 0 then "+" else "")

    | RefType(_, tycont)         ->
        let strcont = string_of_type_struct_basic tycont in
        ( match tycont with
          | FuncType(_, _, _) -> "(" ^ strcont ^ ")"
          | ProductType(_, _) -> "(" ^ strcont ^ ")"
          | _                 -> strcont
        ) ^ " ref" ^ (if sttln <= 0 then "+" else "")

    | ProductType(_, tylist)     -> string_of_type_struct_list_basic tylist
    | ForallType(tvid, tycont)   ->
        "('" ^ (string_of_int tvid) ^ ". " ^ (string_of_type_struct_basic tycont) ^ ")" ^ (if sttln <= 0 then "+" else "")

and string_of_type_struct_list_basic tylist =
  match tylist with
  | []           -> ""
  | head :: []   ->
      let strhd = string_of_type_struct_basic head in
      ( match head with
        | ProductType(_, _) -> "(" ^ strhd ^ ")"
        | _                 -> strhd
      )
  | head :: tail ->
      let strhd = string_of_type_struct_basic head in
      let strtl = string_of_type_struct_list_basic tail in
      ( match head with
        | ProductType(_, _) -> "(" ^ strhd ^ ")"
        | _                 -> strhd
      ) ^ " * " ^ strtl


let meta_max    : type_variable_id ref = ref 0
let unbound_max : type_variable_id ref = ref 0
let unbound_type_valiable_name_list : (type_variable_id * string ) list ref = ref []

let rec variable_name_of_int n =
  ( if n >= 26 then
      variable_name_of_int ((n - n mod 26) / 26 - 1)
    else
      ""
  ) ^ (String.make 1 (Char.chr ((Char.code 'a') + n mod 26)))

let new_meta_type_variable_name () =
  let res = variable_name_of_int (!meta_max) in
    meta_max := !meta_max + 1 ; res

let rec find_meta_type_variable lst tvid =
  match lst with
  | []             -> raise Not_found
  | (k, v) :: tail -> if k = tvid then v else find_meta_type_variable tail tvid

let new_unbound_type_variable_name tvid =
  let res = variable_name_of_int (!unbound_max) in
    unbound_max := !unbound_max + 1 ;
    unbound_type_valiable_name_list := (tvid, res) :: (!unbound_type_valiable_name_list) ;
    res

let find_unbound_type_variable tvid =
  find_meta_type_variable (!unbound_type_valiable_name_list) tvid

let rec string_of_type_struct tystr =
  meta_max := 0 ;
  unbound_max := 0 ;
  unbound_type_valiable_name_list := [] ;
  string_of_type_struct_sub tystr []
(*
  string_of_type_struct_basic tystr
*)
and string_of_type_struct_double tystr1 tystr2 =
  meta_max := 0 ;
  unbound_max := 0 ;
  unbound_type_valiable_name_list := [] ;
  let strty1 = string_of_type_struct_sub tystr1 [] in
  let strty2 = string_of_type_struct_sub tystr2 [] in
    (strty1, strty2)
(*
  let strty1 = string_of_type_struct_basic tystr1 in
  let strty2 = string_of_type_struct_basic tystr2 in
    (strty1, strty2)
*)

(* type_struct -> (type_variable_id * string) list -> string *)
and string_of_type_struct_sub tystr lst =
  match tystr with
  | StringType(_) -> "string"
  | IntType(_)    -> "int"
  | BoolType(_)   -> "bool"
  | UnitType(_)   -> "unit"
  | TypeEnvironmentType(_, _) -> "env"

  | TypeVariable(_, tvid)     ->
      ( try "'" ^ (find_meta_type_variable lst tvid) with
        | Not_found ->
            "'" ^
              ( try find_unbound_type_variable tvid with
                | Not_found -> new_unbound_type_variable_name tvid
              )
      )

  | FuncType(_, tydom, tycod) ->
      let strdom = string_of_type_struct_sub tydom lst in
      let strcod = string_of_type_struct_sub tycod lst in
      ( match tydom with
        | FuncType(_, _, _) -> "(" ^ strdom ^ ")"
        | _                 -> strdom
      ) ^ " -> " ^ strcod

  | ListType(_, tycont)       ->
      let strcont = string_of_type_struct_sub tycont lst in
      ( match tycont with
        | FuncType(_, _, _) -> "(" ^ strcont ^ ")"
        | ProductType(_, _) -> "(" ^ strcont ^ ")"
        | _                 -> strcont
      ) ^ " list"

  | RefType(_, tycont)        ->
      let strcont = string_of_type_struct_sub tycont lst in
      ( match tycont with
        | FuncType(_, _, _) -> "(" ^ strcont ^ ")"
        | ProductType(_, _) -> "(" ^ strcont ^ ")"
        | _                 -> strcont
      ) ^ " ref"

  | ProductType(_, tylist)    ->
      string_of_type_struct_list tylist lst

  | ForallType(tvid, tycont)  ->
      let meta = new_meta_type_variable_name () in
        (string_of_type_struct_sub tycont ((tvid, meta) :: lst))

and string_of_type_struct_list tylist lst =
  match tylist with
  | []           -> ""
  | head :: tail ->
      let strhead = string_of_type_struct_sub head lst in
      let strtail = string_of_type_struct_list tail lst in
      ( match head with
        | FuncType(_, _, _) -> "(" ^ strhead ^ ")"
        | ProductType(_, _) -> "(" ^ strhead ^ ")"
        | _                 -> strhead
      ) ^
      ( match tail with
        | [] -> ""
        | _  -> " * " ^ strtail
      )

let rec string_of_type_environment tyenv msg =
    "    #==== " ^ msg ^ " " ^ (String.make (58 - (String.length msg)) '=') ^ "\n"
  ^ (string_of_type_environment_sub tyenv)
  ^ "    #================================================================\n"
and string_of_type_environment_sub tyenv =
  match tyenv with
  | []               -> ""
  | (vn, ts) :: tail ->
      let (a, _, _, _) = get_range_from_type ts in (* dirty code *)
        if -38 <= a && a <= -1 then
          string_of_type_environment_sub tail
        else
          "    #  "
            ^ ( let len = String.length vn in
                  if len >= 16 then vn else vn ^ (String.make (16 - len) ' ') )
            ^ " : " ^ (string_of_type_struct ts) ^ "\n"
            ^ (string_of_type_environment_sub tail)


let rec string_of_control_sequence_type tyenv =
    "    #================================================================\n"
  ^ (string_of_control_sequence_type_sub tyenv)
  ^ "    #================================================================\n"
and string_of_control_sequence_type_sub tyenv =
  match tyenv with
  | []               -> ""
  | (vn, ts) :: tail ->
      ( match String.sub vn 0 1 with
        | "\\" ->
            "    #  "
              ^ ( let len = String.length vn in
                    if len >= 16 then vn else vn ^ (String.make (16 - len) ' ') )
              ^ " : " ^ (string_of_type_struct ts) ^ "\n"
        | _    -> ""
      ) ^ (string_of_control_sequence_type_sub tail)


let rec found_in_list tvid lst =
  match lst with
  | []       -> false
  | hd :: tl -> if hd = tvid then true else found_in_list tvid tl

let rec found_in_type_struct tvid tystr =
  match tystr with
  | TypeVariable(_, tvidx)    -> tvidx = tvid
  | FuncType(_, tydom, tycod) -> (found_in_type_struct tvid tydom) || (found_in_type_struct tvid tycod)
  | ListType(_, tycont)       -> found_in_type_struct tvid tycont
  | RefType(_, tycont)        -> found_in_type_struct tvid tycont
  | _                         -> false

let rec found_in_type_environment tvid tyenv =
  match tyenv with
  | []                 -> false
  | (_, tystr) :: tail ->
      if found_in_type_struct tvid tystr then
        true
      else
        found_in_type_environment tvid tail


let unbound_id_list : type_variable_id list ref = ref []

(* type_struct -> type_environment -> (type_variable_id list) -> unit *)
let rec listup_unbound_id tystr tyenv =
  match tystr with
  | TypeVariable(_, tvid)     ->
      if found_in_type_environment tvid tyenv then ()
      else if found_in_list tvid !unbound_id_list then ()
      else unbound_id_list := tvid :: !unbound_id_list
  | FuncType(_, tydom, tycod) -> ( listup_unbound_id tydom tyenv ; listup_unbound_id tycod tyenv )
  | ListType(_, tycont)       -> listup_unbound_id tycont tyenv
  | RefType(_, tycont)        -> listup_unbound_id tycont tyenv
  | _                         -> ()

(* type_variable_id list -> type_struct -> type_struct *)
let rec add_forall_struct lst tystr =
  match lst with
  | []           -> tystr
  | tvid :: tail -> ForallType(tvid, add_forall_struct tail tystr)

(* type_struct -> type_environment -> type_struct *)
let make_forall_type tystr tyenv =
	unbound_id_list := [] ; listup_unbound_id tystr tyenv ;
	add_forall_struct (!unbound_id_list) tystr


let empty = []

let rec add tyenv varnm tystr =
  match tyenv with
  | []               -> [(varnm, tystr)]
  | (vn, ts) :: tail ->
      if vn = varnm then (varnm, tystr) :: tail else (vn, ts) :: (add tail varnm tystr)

let rec find tyenv varnm =
  match tyenv with
  | []               -> raise Not_found
  | (vn, ts) :: tail -> if vn = varnm then ts else find tail varnm