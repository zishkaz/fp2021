open Ast
open Env

type exval =
  | IntV of int
  | BoolV of bool
  | StringV of string
  | TupleV of exval list
  | ListV of exval list
  | FunV of pat * exp * exval Env.t

let str_converter = function
  | IntV x -> string_of_int x
  | BoolV x -> string_of_bool x
  | StringV x -> x
  | _ -> failwith "Interpretation error: not basic type."
;;

let exval_to_str = function
  | Some (IntV x) -> str_converter (IntV x)
  | Some (BoolV x) -> str_converter (BoolV x)
  | Some (StringV x) -> str_converter (StringV x)
  | Some (TupleV x) -> String.concat " " (List.map str_converter x)
  | Some (ListV x) -> String.concat " " (List.map str_converter x)
  | Some (FunV (pat, _, _)) ->
    (match pat with
    | PVar x -> x
    | _ -> "error")
  | None -> "error"
;;

type env = exval Env.t

exception Tuple_compare
exception Match_fail

let rec vars_pat = function
  | PVar name -> [ name ]
  | PCons (pat1, pat2) -> vars_pat pat1 @ vars_pat pat2
  | PTuple pats | PList pats ->
    List.fold_left (fun binds pat -> binds @ vars_pat pat) [] pats
  | _ -> raise Match_fail
;;

let rec match_pat pat var =
  match pat, var with
  | PWild, _ -> []
  | PVar name, v -> [ name, v ]
  | PCons (pat1, pat2), ListV (hd :: tl) -> match_pat pat1 hd @ match_pat pat2 (ListV tl)
  | (PTuple pats, TupleV vars | PList pats, ListV vars)
    when List.length pats = List.length vars ->
    List.fold_left2 (fun binds pat var -> binds @ match_pat pat var) [] pats vars
  | PConst x, v ->
    (match x, v with
    | CInt a, IntV b when a = b -> []
    | CString a, StringV b when a = b -> []
    | CBool a, BoolV b when a = b -> []
    | _ -> raise Match_fail)
  | _ -> raise Match_fail
;;

let apply_infix_op op x y =
  match op, x, y with
  | Add, IntV x, IntV y -> IntV (x + y)
  | Sub, IntV x, IntV y -> IntV (x - y)
  | Mul, IntV x, IntV y -> IntV (x * y)
  | Div, IntV x, IntV y -> IntV (x / y)
  (* "<" block *)
  | Less, IntV x, IntV y -> BoolV (x < y)
  | Less, StringV x, StringV y -> BoolV (x < y)
  | Less, BoolV x, BoolV y -> BoolV (x < y)
  | Less, TupleV x, TupleV y when List.length x = List.length y -> BoolV (x < y)
  | Less, ListV x, ListV y -> BoolV (x < y)
  (* "<=" block *)
  | Leq, IntV x, IntV y -> BoolV (x <= y)
  | Leq, StringV x, StringV y -> BoolV (x <= y)
  | Leq, BoolV x, BoolV y -> BoolV (x <= y)
  | Leq, TupleV x, TupleV y when List.length x = List.length y -> BoolV (x <= y)
  | Leq, ListV x, ListV y -> BoolV (x <= y)
  (* ">" block *)
  | Gre, IntV x, IntV y -> BoolV (x > y)
  | Gre, StringV x, StringV y -> BoolV (x > y)
  | Gre, BoolV x, BoolV y -> BoolV (x > y)
  | Gre, TupleV x, TupleV y when List.length x = List.length y -> BoolV (x > y)
  | Gre, ListV x, ListV y -> BoolV (x > y)
  (* ">=" block *)
  | Geq, IntV x, IntV y -> BoolV (x >= y)
  | Geq, StringV x, StringV y -> BoolV (x >= y)
  | Geq, BoolV x, BoolV y -> BoolV (x >= y)
  | Geq, TupleV x, TupleV y when List.length x = List.length y -> BoolV (x >= y)
  | Geq, ListV x, ListV y -> BoolV (x >= y)
  (* "=" block *)
  | Eq, IntV x, IntV y -> BoolV (x = y)
  | Eq, StringV x, StringV y -> BoolV (x = y)
  | Eq, BoolV x, BoolV y -> BoolV (x = y)
  | Eq, TupleV x, TupleV y -> BoolV (x = y)
  | Eq, ListV x, ListV y -> BoolV (x = y)
  (* "!=" block *)
  | Neq, IntV x, IntV y -> BoolV (x != y)
  | Neq, StringV x, StringV y -> BoolV (x != y)
  | Neq, BoolV x, BoolV y -> BoolV (x != y)
  | Neq, TupleV x, TupleV y -> BoolV (x != y)
  | Neq, ListV x, ListV y -> BoolV (x != y)
  (* Other bool ops *)
  | And, BoolV x, BoolV y -> BoolV (x && y)
  | Or, BoolV x, BoolV y -> BoolV (x || y)
  (* failures *)
  | _, TupleV x, TupleV y when List.length x != List.length y -> raise Tuple_compare
  | _ -> failwith "Interpretation error: Wrong infix operation."
;;

let apply_unary_op op x =
  match op, x with
  | Minus, IntV x -> IntV (-x)
  | Not, BoolV x -> BoolV (not x)
  | _ -> failwith "Interpretation error: Wrong unary operation."
;;

let rec eval_exp env = function
  | EConst x ->
    (match x with
    | CInt x -> IntV x
    | CBool x -> BoolV x
    | CString x -> StringV x)
  | EVar x ->
    (try Env.lookup x env with
    | Env.Not_bound -> failwith "Interpretation error: undef variable.")
  | EOp (op, x, y) ->
    let exp_x = eval_exp env x in
    let exp_y = eval_exp env y in
    apply_infix_op op exp_x exp_y
  | EUnOp (op, x) ->
    let exp_x = eval_exp env x in
    apply_unary_op op exp_x
  | EList exps -> ListV (List.map (eval_exp env) exps)
  | ETuple exps -> TupleV (List.map (eval_exp env) exps)
  | ECons (exp1, exp2) ->
    let exp1_evaled = eval_exp env exp1 in
    let exp2_evaled = eval_exp env exp2 in
    (match exp2_evaled with
    | ListV list -> ListV ([ exp1_evaled ] @ list)
    | x -> ListV [ exp1_evaled; x ])
  | EIf (exp1, exp2, exp3) ->
    (match eval_exp env exp1 with
    | BoolV true -> eval_exp env exp2
    | BoolV false -> eval_exp env exp3
    | _ -> failwith "Interpretation error: couldn't interpret \"if\" expression")
  | ELet (bindings, exp1) ->
    let gen_env =
      List.fold_left
        (fun env binding ->
          match binding with
          | false, pat, exp ->
            let evaled = eval_exp env exp in
            let binds = match_pat pat evaled in
            List.fold_left (fun env (id, v) -> extend id v env) env binds
          | true, pat, exp ->
            let vars = vars_pat pat in
            let env = List.fold_left (fun env id -> reserve id env) env vars in
            let vb = eval_exp env exp in
            let binds = match_pat pat vb in
            List.iter (fun (id, v) -> emplace id v env) binds;
            env)
        env
        bindings
    in
    eval_exp gen_env exp1
  | EFun (pat, exp) -> FunV (pat, exp, env)
  | EApp (exp1, exp2) ->
    (match eval_exp env exp1 with
    | FunV (pat, exp, fenv) ->
      let binds = match_pat pat (eval_exp env exp2) in
      let new_env = List.fold_left (fun env (id, v) -> extend id v env) fenv binds in
      eval_exp new_env exp
    | _ -> failwith "Interpretation error: wrong application")
  | EMatch (exp, mathchings) ->
    let evaled = eval_exp env exp in
    let rec do_match = function
      | [] -> failwith "Interpretation error: match fail"
      | (pat, exp) :: tl ->
        (try
           let binds = match_pat pat evaled in
           let env = List.fold_left (fun env (id, v) -> extend id v env) env binds in
           eval_exp env exp
         with
        | Match_fail -> do_match tl)
    in
    do_match mathchings
;;

let eval_dec env = function
  | DLet bindings ->
    (match bindings with
    | false, pat, exp ->
      let evaled = eval_exp env exp in
      let binds = match_pat pat evaled in
      let env = List.fold_left (fun env (id, v) -> extend id v env) env binds in
      env
    | true, pat, exp ->
      let vars = vars_pat pat in
      let env = List.fold_left (fun env id -> reserve id env) env vars in
      let vb = eval_exp env exp in
      let binds = match_pat pat vb in
      List.iter (fun (id, v) -> emplace id v env) binds;
      env)
  | _ -> failwith "Interpretation error: unimpl"
;;

let eval_test decls expected =
  try
    let init_env = Env.empty in
    let env = List.fold_left (fun env decl -> eval_dec env decl) init_env decls in
    let res =
      IdMap.fold
        (fun k v ln ->
          let new_res = ln ^ Printf.sprintf "%s -> %s " k (exval_to_str !v) in
          new_res)
        env
        ""
    in
    if res = expected
    then true
    else (
      Printf.printf "%s" res;
      false)
  with
  | Tuple_compare ->
    if expected = "Interpretation error: Cannot compare tuples of different size."
    then true
    else false
;;

let test code expected =
  match Parser.parse Parser.prog code with
  | Result.Ok prog -> eval_test prog expected
  | _ -> failwith "Parse error"
;;

(* Eval test 1 *)

(* 
  let x = 1
*)
let%test _ = eval_test [ DLet (false, PVar "x", EConst (CInt 1)) ] "x -> 1 "

(* Eval test 2 *)

(* 
  let (x, y) = (1, 2)
*)
let%test _ =
  eval_test
    [ DLet
        (false, PTuple [ PVar "x"; PVar "y" ], ETuple [ EConst (CInt 1); EConst (CInt 2) ])
    ]
    "x -> 1 y -> 2 "
;;

(* Eval test 3 *)

(* 
  let x = 3 < 2
*)
let%test _ =
  eval_test
    [ DLet (false, PVar "x", EOp (Less, EConst (CInt 3), EConst (CInt 2))) ]
    "x -> false "
;;

(* Eval test 4 *)

(* 
  let x = (1, 2) < (1, 2, 3)
*)
let%test _ =
  eval_test
    [ DLet
        ( false
        , PVar "x"
        , EOp
            ( Less
            , ETuple [ EConst (CInt 1); EConst (CInt 2) ]
            , ETuple [ EConst (CInt 1); EConst (CInt 2); EConst (CInt 3) ] ) )
    ]
    "Interpretation error: Cannot compare tuples of different size."
;;

(* Eval test 5 *)

(* 
  let x =
    let y = 5
    in y
*)
let%test _ =
  eval_test
    [ DLet (false, PVar "x", ELet ([ false, PVar "y", EConst (CInt 5) ], EVar "y")) ]
    "x -> 5 "
;;

(* Eval test 6 *)

(* 
  let x =
    let y = 5 in
    let z = 10 in
    y + z
*)
let%test _ =
  eval_test
    [ DLet
        ( false
        , PVar "x"
        , ELet
            ( [ false, PVar "y", EConst (CInt 5); false, PVar "z", EConst (CInt 10) ]
            , EOp (Add, EVar "y", EVar "z") ) )
    ]
    "x -> 15 "
;;

(* Eval test 7 *)

(* 
  let x =
    let y = 5 in
    let y = 10 in
    y
*)
let%test _ =
  eval_test
    [ DLet
        ( false
        , PVar "x"
        , ELet
            ( [ false, PVar "y", EConst (CInt 5); false, PVar "y", EConst (CInt 10) ]
            , EVar "y" ) )
    ]
    "x -> 10 "
;;

(* Eval test 8 *)

(* 
  let x =
    let y =
      let y = 10 in
      5
    in
    y
*)
let%test _ =
  eval_test
    [ DLet
        ( false
        , PVar "x"
        , ELet
            ( [ ( false
                , PVar "y"
                , ELet ([ false, PVar "y", EConst (CInt 10) ], EConst (CInt 5)) )
              ]
            , EVar "y" ) )
    ]
    "x -> 5 "
;;

(* Eval test 9 *)

(* 
  let f x y = x + y
*)
let%test _ =
  eval_test
    [ DLet
        (false, PVar "f", EFun (PVar "x", EFun (PVar "y", EOp (Add, EVar "x", EVar "y"))))
    ]
    "f -> x "
;;

(* Eval test 10 *)

(* 
  let f x y = x + y
  let a = f 1 2 
*)
let%test _ =
  eval_test
    [ DLet
        (false, PVar "f", EFun (PVar "x", EFun (PVar "y", EOp (Add, EVar "x", EVar "y"))))
    ; DLet (false, PVar "a", EApp (EApp (EVar "f", EConst (CInt 1)), EConst (CInt 2)))
    ]
    "a -> 3 f -> x "
;;

(* Eval test 11 *)

(* 
  let f x y = x + y
  let kek = f 1
  let lol = kek 2 
*)
let%test _ =
  eval_test
    [ DLet
        (false, PVar "f", EFun (PVar "x", EFun (PVar "y", EOp (Add, EVar "x", EVar "y"))))
    ; DLet (false, PVar "kek", EApp (EVar "f", EConst (CInt 1)))
    ; DLet (false, PVar "lol", EApp (EVar "kek", EConst (CInt 2)))
    ]
    "f -> x kek -> y lol -> 3 "
;;

(* Eval test 12 *)

(* 
  let rec fact n =
  match n with
  | 0 -> 1
  | _ -> n * fact (n + -1)
  let x = fact 3
*)
let%test _ =
  eval_test
    [ DLet
        ( true
        , PVar "fact"
        , EFun
            ( PVar "n"
            , EMatch
                ( EVar "n"
                , [ PConst (CInt 0), EConst (CInt 1)
                  ; ( PWild
                    , EOp
                        ( Mul
                        , EVar "n"
                        , EApp
                            ( EVar "fact"
                            , EOp (Add, EVar "n", EUnOp (Minus, EConst (CInt 1))) ) ) )
                  ] ) ) )
    ; DLet (false, PVar "x", EApp (EVar "fact", EConst (CInt 3)))
    ]
    "fact -> n x -> 6 "
;;

(* Eval test 13 *)

(*
  let rec sort lst =
    let sorted =
      match lst with
      | hd1 :: hd2 :: tl ->
        if hd1 > hd2 then hd2 :: sort (hd1 :: tl) else hd1 :: sort (hd2 :: tl)
      | tl -> tl
    in
    if lst = sorted then lst else sort sorted
  ;;

  let l = []
  let sorted = sort l
*)
let%test _ =
  eval_test
    [ DLet
        ( true
        , PVar "sort"
        , EFun
            ( PVar "lst"
            , ELet
                ( [ ( false
                    , PVar "sorted"
                    , EMatch
                        ( EVar "lst"
                        , [ ( PCons (PVar "hd1", PCons (PVar "hd2", PVar "tl"))
                            , EIf
                                ( EOp (Gre, EVar "hd1", EVar "hd2")
                                , ECons
                                    ( EVar "hd2"
                                    , EApp (EVar "sort", ECons (EVar "hd1", EVar "tl")) )
                                , ECons
                                    ( EVar "hd1"
                                    , EApp (EVar "sort", ECons (EVar "hd2", EVar "tl")) )
                                ) )
                          ; PVar "tl", EVar "tl"
                          ] ) )
                  ]
                , EIf
                    ( EOp (Eq, EVar "lst", EVar "sorted")
                    , EVar "lst"
                    , EApp (EVar "sort", EVar "sorted") ) ) ) )
    ; DLet (false, PVar "l", EList [ EConst (CInt 1); EConst (CInt 3); EConst (CInt 2) ])
    ; DLet (false, PVar "sorted", EApp (EVar "sort", EVar "l"))
    ]
    "l -> 1 3 2 sort -> lst sorted -> 1 2 3 "
;;
