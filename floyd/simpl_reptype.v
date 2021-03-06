Require Import floyd.base.
Require Import floyd.nested_field_lemmas.
Require Import floyd.reptype_lemmas.
Require Import floyd.proj_reptype_lemmas.
Require Import floyd.replace_refill_reptype_lemmas.
Require Import floyd.simple_reify.

Section SIMPL_REPTYPE.

Context {cs: compspecs}.

(* We assume type and gfield list are compatible. *)

Definition is_effective_array (t: type) (n: Z) (a: attr) (i: Z) (v: reptype_skeleton) : option reptype_skeleton := None.

Fixpoint is_effective_struct i (m: members) (v: reptype_skeleton) : option reptype_skeleton :=
  match m with
  | nil => None
  | _ :: nil => Some v
  | (i', _) :: tl =>
    match v with
    | RepPair v1 v2 => if (ident_eq i i') then Some v1 else is_effective_struct i tl v2
    | _ => None
    end
  end.

Fixpoint is_effective_union i (m: members) (v: reptype_skeleton) : option reptype_skeleton :=
  match m with
  | nil => None
  | _ :: nil => Some v
  | (i', _) :: tl =>
    match v with
    | RepInl v0 => if (ident_eq i i') then Some v0 else None
    | RepInr v0 => if (ident_eq i i') then None else is_effective_struct i tl v0
    | _ => None
    end
  end.

Definition is_effective (t: type) (gf: gfield) (v: reptype_skeleton) : option reptype_skeleton :=
  match t, gf with
  | Tarray t0 hi a, ArraySubsc i => is_effective_array t0 hi a i v
  | Tstruct id _, StructField i => is_effective_struct i (co_members (get_co id)) v
  | Tunion id _, UnionField i => is_effective_union i (co_members (get_co id)) v
  | _, _ => None
  end.

(*
(*
Currently, array type data are treated as a string of data. In fact,
they can also be treated as sets of data or other forms of collection
of data. User should choose the way to specify that. However, we
treated them as string and simplify the expression in this way as
default. In the future, this default should be deleted.
*)

Fixpoint extra_simpl_len (rgfs: list gfield) : nat :=
  match rgfs with
  | ArraySubsc _ :: rgfs0 => S (extra_simpl_len rgfs0)
  | _ => 0%nat
  end.

Fixpoint effective_len_rec (t: type) (rgfs: list gfield) (v: reptype_skeleton) : nat :=
  match rgfs with
  | nil => 0%nat
  | gf :: rgfs0 =>
     match is_effective t gf v with
     | Some v0 => S (effective_len_rec (gfield_type t gf) rgfs0 v0)
     | None => extra_simpl_len rgfs
     end
  end.

Fixpoint effective_len (t: type) (gfs: list gfield) (v: reptype_skeleton) : nat
  := effective_len_rec t (rev gfs) v.
*)

(* This is how we control the length of computation. *)
Fixpoint effective_len (t: type) (gfs: list gfield) (v: reptype_skeleton) : nat
  := length gfs.

End SIMPL_REPTYPE.

Ltac firstn_tac A n l :=
  match n with
    | 0%nat => constr:(@nil A)
    | S ?n0 => match l with
               | @nil A => constr: (@nil A)
               | @cons A ?a ?l => let res := firstn_tac A n0 l in constr: (@cons A a res)
             end
  end.

Ltac skipn_tac A n l :=
  match n with
    | 0%nat => constr: (l)
    | S ?n0 => match l with
               | @nil A => constr: (@nil A)
               | @cons A ?a ?l => let res := skipn_tac A n0 l in constr: (res)
             end
  end.

Ltac remember_indexes gfs :=
  match gfs with
  | ArraySubsc ?i :: ?g' => remember i; remember_indexes g'
  | _ :: ?g' => remember_indexes g'
  | nil => idtac
  end.

Ltac solve_load_rule_evaluation_old :=
  clear;
  repeat
  match goal with
  | A : _ |- _ => clear A
  | A := _ |- _ => clear A
  end;
  match goal with
  | |- JMeq (@proj_reptype _ _ ?name_of_gfs ?name_of_v) _ =>
    subst name_of_gfs;
    try subst name_of_v
  end;
  match goal with
  | |- JMeq (@proj_reptype _ _ ?gfs _) _ =>
    remember_indexes gfs
  end;
  match goal with
  | |- JMeq (@proj_reptype ?cs ?t ?gfs ?v) _ =>
    let s := simple_reify.simple_reify v in
    let len_opaque := eval vm_compute in (length gfs - effective_len t gfs s)%nat in
    let gfs_opaque := (firstn_tac gfield len_opaque gfs) in
    let gfs_compute := (skipn_tac gfield len_opaque gfs) in
    match gfs_opaque with
    | nil =>
      let opaque_function := fresh "opaque_function" in
      let opaque_v := fresh "v" in
      (* TODO: the next line seems unuseful *)
      pose (proj_reptype (nested_field_type t gfs_compute) gfs_opaque) as opaque_function;
      set (opaque_v := v);
      lazy beta zeta iota delta - [opaque_v sublist.Znth Int.repr];
      subst opaque_v; subst; apply JMeq_refl
    | @cons _ _ _ =>
      (* TODO: this part needs debug *)
      let opaque_function := fresh "opaque_function" in
      let opaque_v := fresh "v" in
      pose (proj_reptype (nested_field_type t gfs_compute) gfs_opaque) as opaque_function;
      set (opaque_v := v);
      lazy beta zeta iota delta - [opaque_function opaque_v sublist.Znth Int.repr];
      subst opaque_v opaque_function; subst; apply JMeq_refl
    end
  end.

Ltac solve_load_rule_evaluation :=
  clear;
  repeat
  match goal with
  | A : _ |- _ => clear A 
  | A := _ |- _ => clear A 
  end;
  match goal with
  | |- JMeq (@proj_reptype _ _ ?name_of_gfs ?name_of_v) _ =>
    subst name_of_gfs;
    try subst name_of_v
  end;
  match goal with
  | |- JMeq (@proj_reptype _ _ ?gfs _) _ =>
    remember_indexes gfs
  end;
  match goal with
  | |- JMeq (@proj_reptype ?cs ?t ?gfs ?v) _ =>
      let opaque_v := fresh "opaque_v" in
      set (opaque_v := v);
      cbv - [opaque_v sublist.Znth Int.repr];
      subst opaque_v; subst; apply JMeq_refl
  end.
