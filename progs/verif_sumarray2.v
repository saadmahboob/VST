Require Import floyd.proofauto. (* Import the Verifiable C system *)
Require Import progs.sumarray2. (* Import the AST of this C program *)
(* The next line is "boilerplate", always required after importing an AST. *)
Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs.  mk_varspecs prog. Defined.


(* Some definitions relating to the functional spec of this particular program.  *)
Definition sum_Z : list Z -> Z := fold_right Z.add 0.

Lemma sum_Z_app:
  forall a b, sum_Z (a++b) =  sum_Z a + sum_Z b.
Proof.
  intros. induction a; simpl; omega.
Qed.

(* Beginning of the API spec for the sumarray.c program *)
Definition sumarray_spec :=
 DECLARE _sumarray
  WITH a: val, sh : share, contents : list Z, size: Z
  PRE [ _a OF (tptr tint), _n OF tint ]
          PROP  (readable_share sh; 0 <= size <= Int.max_signed;
                     Forall (fun x => Int.min_signed <= x <= Int.max_signed) contents)
          LOCAL (temp _a a; temp _n (Vint (Int.repr size)))
          SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)
  POST [ tint ]
        PROP () LOCAL(temp ret_temp  (Vint (Int.repr (sum_Z contents))))
           SEP (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a).

(* The spec of "int main(void){}" always looks like this. *)
Definition main_spec :=
 DECLARE _main
  WITH u : unit
  PRE  [] main_pre prog nil u
  POST [ tint ] main_post prog nil u.

(* Packaging the API spec all together. *)
Definition Gprog : funspecs :=
        ltac:(with_library prog [sumarray_spec; main_spec]).

(** Proof that f_sumarray, the body of the sumarray() function,
 ** satisfies sumarray_spec, in the global context (Vprog,Gprog).
 **)
Lemma body_sumarray: semax_body Vprog Gprog f_sumarray sumarray_spec.
Proof.
start_function.  (* Always do this at the beginning of a semax_body proof *)
(* The next two lines do forward symbolic execution through
   the first two executable statements of the function body *)
forward.  (* s = 0; *)
forward_for_simple_bound size
  (EX i: Z,
   PROP  ((*0 <= i <= size*))
   LOCAL (temp _a a;
          (*temp _i (Vint (Int.repr i)); *)
          temp _n (Vint (Int.repr size));
          temp _s (Vint (Int.repr (sum_Z (sublist 0 i contents)))))
   SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)).

* (* Prove that current precondition implies loop invariant *)
entailer!.
* (* Prove postcondition of loop body implies loop invariant *)

  (*Insertion of this property is suiggested by an error message in the ensuing forward.
    The property allows forward to discharge a nontrivial typechecking condition, namely that
    the array-subscript index is in range;  not just in the bounds of the array, but in
    the _initialized_ portion of the array.*)    
  assert_PROP (0 <= i < Zlength (map Vint (map Int.repr contents))) as I by entailer!.
  rewrite 2 Zlength_map in I.

  forward. (* x = a[i] *)
forward. (* s += x; *)
entailer!.
 f_equal. f_equal.
 rewrite (sublist_split 0 i (i+1)) by omega.
 rewrite sum_Z_app. rewrite (sublist_one i) with (d:=0) by omega.
 simpl. rewrite Z.add_0_r. reflexivity.
* (* After the loop *)
forward.  (* return s; *)
 (* Here we prove that the postcondition of the function body
    entails the postcondition demanded by the function specification. *)
simpl.
apply prop_right.
autorewrite with sublist.
reflexivity.
Qed.

(* Contents of the extern global initialized array "_four" *)
Definition four_contents := [1; 2; 3; 4].

(*  discard this...
Lemma split_array':
 forall {cs: compspecs} mid n (sh: Share.t) (t: type)
                            v (v': list (reptype t)) v1 v2 p,
    0 <= mid <= n ->
    JMeq v v' ->
    JMeq v1 (sublist 0 mid v') ->
    JMeq v2 (sublist mid n v') ->
    Zlength v' = n ->
    sizeof (tarray t n) < Int.modulus ->
    field_compatible0 (tarray t mid) [ArraySubsc 0] p ->
    field_compatible0 (tarray t n) [ArraySubsc mid] p ->
    field_compatible0 (tarray t n) [ArraySubsc n] p ->
    data_at sh (tarray t n) v p =
    data_at sh (tarray t mid) v1  p *
    data_at sh (tarray t (n-mid)) v2
            (field_address0 (tarray t n) [ArraySubsc mid] p).
Proof.
intros.
destruct H.
unfold data_at.
erewrite !field_at_Tarray; try reflexivity; try eassumption; try apply JMeq_refl; try reflexivity; try omega.
rewrite (split2_array_at sh _ _ 0 mid n); simpl; try omega.
autorewrite with sublist.
f_equal.
*
unfold array_at.
simpl. f_equal.
f_equal. f_equal.
admit.
admit.
*
rewrite (array_at_data_at_rec sh _ _ mid n); auto.
change (nested_field_array_type _ _ _ _) with (tarray t (n-mid)).
rewrite (array_at_data_at_rec sh _ _ 0 (n-mid)); auto; try omega.
change (nested_field_array_type _ _ _ _) with (tarray t (n-mid-0)).
rewrite H3.
autorewrite with sublist.
f_equal.
rewrite !field_address0_clarify.
simpl. rewrite offset_offset_val. f_equal.
omega.
admit.
admit.
admit.
admit.
Admitted.

Lemma split_arrayx:
 forall {cs: compspecs} mid n (sh: Share.t) (t: type)
                            v (v': list (reptype t)) v1 v2 p,
    0 <= mid <= n ->
    JMeq v v' ->
    JMeq v1 (sublist 0 mid v') ->
    JMeq v2 (sublist mid n v') ->
    Zlength v' = n ->
    sizeof (tarray t n) < Int.modulus ->
    data_at sh (tarray t n) v p =
    data_at sh (tarray t mid) v1  p *
    data_at sh (tarray t (n-mid)) v2
            (field_address0 (tarray t n) [ArraySubsc mid] p).
Proof.
intros.
apply pred_ext.
*
saturate_local.
erewrite <- split_array'; try eassumption; auto.
 +
   destruct H5 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   split3; [ | | split3; [ | | split3]]; auto.
   admit. admit. admit. split; auto. split; auto. hnf. omega.
 +
   destruct H5 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   split3; [ | | split3; [ | | split3]]; auto.
    split; auto. split; auto.
 +
   destruct H5 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   split3; [ | | split3; [ | | split3]]; auto.
    split; auto. split; auto. hnf. omega.
*
 saturate_local.
 erewrite <- split_array'; try eassumption; auto.
 +
   destruct H5 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   split3; [ | | split3; [ | | split3]]; auto. split; auto. split; auto. hnf; omega.
 +
   destruct H5 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   destruct H8 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   split3; [ | | split3; [ | | split3]]; auto.
   admit.
   hnf in G0. rewrite field_address0_clarify in G0.
   clear - H H4 G G0 B. destruct p; try contradiction; simpl in *.
   unfold Int.add in G0; rewrite !Int.unsigned_repr in G0.
   autorewrite with sublist in *.
   rewrite <- Z.add_assoc in G0.
   rewrite <- Z.mul_add_distr_l in G0.
   replace (mid + (n-mid)) with n in G0 by omega; auto.
   autorewrite with sublist in *.
   admit.
   autorewrite with sublist in *.
   rewrite Int.unsigned_repr.
   admit.
   admit.
   clear - B0. auto.
   split; auto.
   split; auto.
 +
   destruct H5 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   destruct H8 as [?B [?C [?D [?E [?F [?G [?J ?K]]]]]]].
   split3; [ | | split3; [ | | split3]]; auto.
   admit.
   admit.
   split; auto. split; auto. hnf;  omega.
Admitted.
*)

Lemma Forall_sublist: forall {A} (P: A->Prop) lo hi (al: list A),
  Forall P al -> Forall P (sublist lo hi al).
Proof.
intros.
apply Forall_forall. rewrite -> Forall_forall in H.
intros.
apply H; auto.
apply sublist_In in H0. auto.
Qed.

Lemma split_array:
 forall {cs: compspecs} mid n (sh: Share.t) (t: type)
                            v (v' v1' v2': list (reptype t)) v1 v2 p,
    0 <= mid <= n ->
    JMeq v (v1'++v2') ->
    JMeq v1 v1' ->
    JMeq v2 v2' ->
    data_at sh (tarray t n) v p =
    data_at sh (tarray t mid) v1  p *
    data_at sh (tarray t (n-mid)) v2
            (field_address0 (tarray t n) [ArraySubsc mid] p).
Admitted.

Lemma body_main:  semax_body Vprog Gprog f_main main_spec.
Proof.
name four _four.
start_function.
change [Int.repr 1; Int.repr 2; Int.repr 3; Int.repr 4] with (map Int.repr four_contents).
set (contents :=  map Vint (map Int.repr four_contents)).
assert (Zlength contents = 4) by (subst contents; reflexivity).
assert_PROP (field_compatible (tarray tint 4) [] four) by entailer!.
assert (Forall (fun x : Z => Int.min_signed <= x <= Int.max_signed) four_contents)
  by (repeat constructor; computable).
 rewrite <- (sublist_same 0 4 contents), (sublist_split 0 2 4)
    by now autorewrite with sublist.
erewrite (split_array 2 4); try apply JMeq_refl; auto; try omega; try reflexivity.
forward_call (*  s = sumarray(four+2,2); *)
  (field_address0 (tarray tint 4) [ArraySubsc 2] four, Ews,
    sublist 2 4 four_contents,2).
+
 clear - GV. unfold gvar_denote, eval_var in *.
  destruct (Map.get (ve_of rho) _four) as [[? ?]|?]; try contradiction.
  destruct (ge_of rho _four); try contradiction. apply I.
+
 entailer!.
 rewrite field_address0_offset. reflexivity.
 auto with field_compatible.
+
 split3.
 auto.
 computable.
 apply Forall_sublist; auto.
+
  gather_SEP 1 2.
  erewrite <- (split_array 2 4); try apply JMeq_refl; auto; try omega; try reflexivity.
  rewrite <- !sublist_map. fold contents. autorewrite with sublist.
  rewrite (sublist_same 0 4) by auto.
  forward. (* return *)
Qed.

Existing Instance NullExtension.Espec.

Lemma all_funcs_correct:
  semax_func Vprog Gprog (prog_funct prog) Gprog.
Proof.
unfold Gprog, prog, prog_funct; simpl.
semax_func_cons body_sumarray.
semax_func_cons body_main.
Qed.

(**  Here begins an alternate proof of the "for" loop.
  Instead of using forward_for_simple_bound, we use the primitive
  axioms: semax_loop, semax_seq, semax_if, etc.

To understand this verification, let's take the program,

  int sumarray(int a[], int n) {
     int i,s,x;
     s=0;
     for (i=0; i<n; i++) {
       x = a[i];
       s += x;
     }
     return s;
  }

and break it down into the "loop" form of Clight:

  int sumarray(int a[], int n) {
     int i,s,x;
     s=0;
     i=0;
     for ( ; ; i++) {
       if (i<n) then ; else break;
       x = a[i];
       s += x;
     }
     return s;
  }

in which "Sloop c1 c2" is basically the same as
  "for ( ; ; c2) c1".

Into this program we put these assertions:


  int sumarray(int a[], int n) {
     int i,s,x;
     s=0;
     i=0;
     assert (sumarray_Pre);
     for ( ; ; i++) {
       assert (sumarray_Inv);
       if (i<n) then ; else break;
       assert (sumarray_PreBody);
       x = a[i];
       s += x;
       assert (sumarray_PostBody);
     }
     assert (sumarray_Post);
     return s;
  }

The assertions are defined in these five definitions:
*)
(*
Definition sumarray_Pre a sh contents size :=
(PROP  ()
   LOCAL (temp _a a;
          temp _i (Vint (Int.repr 0));
          temp _n (Vint (Int.repr size));
          temp _s (Vint (Int.repr (sum_Z (sublist 0 0 contents)))))
   SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)).
*)
Definition sumarray_Inv a sh contents size :=
(EX i: Z,
   PROP  (0 <= i <= size)
   LOCAL (temp _a a;
          temp _i (Vint (Int.repr i));
          temp _n (Vint (Int.repr size));
          temp _s (Vint (Int.repr (sum_Z (sublist 0 i contents)))))
   SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)).

Definition sumarray_PreBody a sh contents size :=
(EX i: Z,
   PROP  (0 <= i < size)
   LOCAL (temp _a a;
          temp _i (Vint (Int.repr i));
          temp _n (Vint (Int.repr size));
          temp _s (Vint (Int.repr (sum_Z (sublist 0 i contents)))))
   SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)).

Definition sumarray_PostBody a sh contents size :=
(EX i: Z,
   PROP  (0 <= i < size)
   LOCAL (temp _a a;
          temp _i (Vint (Int.repr i));
          temp _n (Vint (Int.repr size));
          temp _s (Vint (Int.repr (sum_Z (sublist 0 (i+1) contents)))))
   SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)).

Definition sumarray_Post a sh contents size :=
   (PROP()
   LOCAL (temp _a a;
          temp _i (Vint (Int.repr size));
          temp _n (Vint (Int.repr size));
          temp _s (Vint (Int.repr (sum_Z contents))))
   SEP   (data_at sh (tarray tint size) (map Vint (map Int.repr contents)) a)).

(* . . . and now you can see how these assertions are used
   in the proof, using the semax_loop rule. *)

Lemma body_sumarray_alt: semax_body Vprog Gprog f_sumarray sumarray_spec.
Proof.
start_function.  (* Always do this at the beginning of a semax_body proof *)
(* The next two lines do forward symbolic execution through
   the first two executable statements of the function body *)
forward.  (* s = 0; *)
unfold Sfor.
forward. (* i=0; *)
apply semax_pre with (sumarray_Inv a sh contents size).
  { unfold sumarray_Inv. Exists 0. entailer!. }
apply semax_seq with (sumarray_Post a sh contents size).
*
 apply semax_loop with (sumarray_PostBody a sh contents size).
 +
   unfold sumarray_Inv.
   Intros i.
   forward_if (sumarray_PreBody a sh contents size).
   - (* then clause *)
     forward. (* skip *)
     { unfold sumarray_PreBody. Exists i. entailer!. }
   - (* else clause *)
     forward. (* break *)
     unfold sumarray_Post.
       entailer!.
       autorewrite with sublist in *.
       assert (i=Zlength contents) by omega. subst i.
       autorewrite with sublist. auto.
   - (* after the if *)
     unfold sumarray_PreBody.
     clear i H1.
     Intros i.
     assert_PROP (0 <= i < Zlength (map Vint (map Int.repr contents))) as I by entailer!.
     rewrite 2 Zlength_map in I.
     forward.  (* x = a[i]; *) 
(*     entailer!.
     autorewrite with sublist in *.
     rewrite Znth_map with (d':=Int.zero).
     apply I.
     autorewrite with sublist.
     omega.*)
     forward. (* s+=x; *)
     unfold sumarray_PostBody.
     Exists i. entailer!.
     autorewrite with sublist in *.
     f_equal. f_equal.
     rewrite (sublist_split 0 i (i+1)) by omega.
     rewrite sum_Z_app. rewrite (sublist_one i) with (d:=0) by omega.
     simpl. rewrite Z.add_0_r. reflexivity.
  +
     unfold sumarray_PostBody.
     Intros i.
     forward. (* i++; *)
     simpl loop2_ret_assert.
     unfold sumarray_Inv.
     Exists (i+1).
     entailer!.
 *
  abbreviate_semax.
  unfold sumarray_Post.
  forward. (* return s; *)
Qed.
