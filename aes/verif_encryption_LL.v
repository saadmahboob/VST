Require Import aes.verif_utils.
Require Import aes.spec_encryption_LL.
Require Import aes.bitfiddling.

Definition encryption_spec_ll :=
  DECLARE _mbedtls_aes_encrypt
  WITH ctx : val, input : val, output : val, (* arguments *)
       ctx_sh : share, in_sh : share, out_sh : share, (* shares *)
       plaintext : list Z, (* 16 chars *)
       exp_key : list Z, (* expanded key, 4*(Nr+1)=60 32-bit integers *)
       tables : val (* global var *)
  PRE [ _ctx OF (tptr t_struct_aesctx), _input OF (tptr tuchar), _output OF (tptr tuchar) ]
    PROP (Zlength plaintext = 16; Zlength exp_key = 60;
          readable_share ctx_sh; readable_share in_sh; writable_share out_sh)
    LOCAL (temp _ctx ctx; temp _input input; temp _output output; gvar _tables tables)
    SEP (data_at ctx_sh (t_struct_aesctx) (
          (Vint (Int.repr Nr)),
          ((field_address t_struct_aesctx [StructField _buf] ctx),
          (map Vint (map Int.repr (exp_key ++ (list_repeat (8%nat) 0)))))
          (* The following weaker precondition would also be provable, but less conveniently, and   *)
          (* since mbedtls_aes_init zeroes the whole buffer, we exploit this to simplify the proof  *)
          (* ((map Vint (map Int.repr exp_key)) ++ (list_repeat (8%nat) Vundef))) *)
         ) ctx;
         data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
         data_at_ out_sh (tarray tuchar 16) output;
         tables_initialized tables)
  POST [ tvoid ]
    PROP() LOCAL()
    SEP (data_at ctx_sh (t_struct_aesctx) (
          (Vint (Int.repr Nr)),
          ((field_address t_struct_aesctx [StructField _buf] ctx),
          (map Vint (map Int.repr (exp_key ++ (list_repeat (8%nat) 0)))))
         ) ctx;
         data_at in_sh  (tarray tuchar 16)
                 (map Vint (map Int.repr plaintext)) input;
         data_at out_sh (tarray tuchar 16)
                 (map Vint (mbed_tls_aes_enc plaintext (exp_key ++ (list_repeat (8%nat) 0)))) output;
         tables_initialized tables).

Definition Gprog : funspecs := ltac:(with_library prog [ encryption_spec_ll ]).

Ltac simpl_Int := repeat match goal with
| |- context [ (Int.mul (Int.repr ?A) (Int.repr ?B)) ] =>
    let x := fresh "x" in (pose (x := (A * B)%Z)); simpl in x;
    replace (Int.mul (Int.repr A) (Int.repr B)) with (Int.repr x); subst x; [|reflexivity]
| |- context [ (Int.add (Int.repr ?A) (Int.repr ?B)) ] =>
    let x := fresh "x" in (pose (x := (A + B)%Z)); simpl in x;
    replace (Int.add (Int.repr A) (Int.repr B)) with (Int.repr x); subst x; [|reflexivity]
end.

(* This is to make sure do_compute_expr (invoked by load_tac and others), which calls hnf on the
   expression it's computing, does not unfold field_address.
   TODO floyd: Ideally, we'd have "Global Opaque field_address field_address0" in the library,
   but some proofs want to unfold field_address (they shouldn't, though). *)
Opaque field_address.

(* entailer! calls simpl, and if simpl tries to evaluate a column of the final AES encryption result,
   it takes forever, so we have to prevent this: *)
Arguments col _ _ : simpl never.
(* Same problem with "Z.land _ 255" *)
Arguments Z.land _ _ : simpl never.

(* This one is to prevent simplification of "12 - _", which is fast, but produces silly verbose goals *)
Arguments Nat.sub _ _ : simpl never.

Lemma body_aes_encrypt: semax_body Vprog Gprog f_mbedtls_aes_encrypt encryption_spec_ll.
Proof.
  idtac "Starting body_aes_encrypt".
  start_function.
  reassoc_seq.

  (* RK = ctx->rk; *)
  forward.
  { entailer!. auto with field_compatible. (* TODO floyd: why is this not done automatically? *) }

  assert_PROP (field_compatible t_struct_aesctx [StructField _buf] ctx) as Fctx. entailer!.
  assert ((field_address t_struct_aesctx [StructField _buf] ctx)
        = (field_address t_struct_aesctx [ArraySubsc 0; StructField _buf] ctx)) as Eq. {
    do 2 rewrite field_compatible_field_address by auto with field_compatible.
    reflexivity.
  }
  rewrite Eq in *. clear Eq.
  remember (exp_key ++ list_repeat 8 0) as buf.
  (* TODO floyd: This is important for automatic rewriting of (Znth (map Vint ...)), and if
     it's not done, the tactics might become very slow, especially if they try to simplify complex
     terms that they would never attempt to simplify if the rewriting had succeeded.
     How should the user be told to put prove such assertions before continuing? *)
  assert (Zlength buf = 68) as LenBuf. {
    subst. rewrite Zlength_app. rewrite H0. reflexivity.
  }

  assert_PROP (forall i, 0 <= i < 60 -> force_val (sem_add_pi tuint
       (field_address t_struct_aesctx [ArraySubsc  i   ; StructField _buf] ctx) (Vint (Int.repr 1)))
     = (field_address t_struct_aesctx [ArraySubsc (i+1); StructField _buf] ctx)) as Eq. {
    entailer!. intros.
    do 2 rewrite field_compatible_field_address by auto with field_compatible.
    simpl. destruct ctx; inversion PNctx; try reflexivity.
    simpl. rewrite Int.add_assoc.
    replace (Int.mul (Int.repr 4) (Int.repr 1)) with (Int.repr 4) by reflexivity.
    rewrite add_repr.
    replace (8 + 4 * (i + 1)) with (8 + 4 * i + 4) by omega.
    reflexivity.
  }

  (* GET_UINT32_LE( X0, input,  0 ); X0 ^= *RK++;
     GET_UINT32_LE( X1, input,  4 ); X1 ^= *RK++;
     GET_UINT32_LE( X2, input,  8 ); X2 ^= *RK++;
     GET_UINT32_LE( X3, input, 12 ); X3 ^= *RK++; *)
  do 4 forward. simpl. forward. forward. forward. simpl. rewrite Eq by omega. simpl. forward. forward.
  do 4 forward. simpl. forward. forward. forward. simpl. rewrite Eq by omega. simpl. forward. forward.
  do 4 forward. simpl. forward. forward. forward. simpl. rewrite Eq by omega. simpl. forward. forward.
  do 4 forward. simpl. forward. forward. forward. simpl. rewrite Eq by omega. simpl. forward. forward.

  pose (S0 := mbed_tls_initial_add_round_key plaintext buf).

  match goal with |- context [temp _X0 (Vint ?E)] => change E with (col 0 S0) end.
  match goal with |- context [temp _X1 (Vint ?E)] => change E with (col 1 S0) end.
  match goal with |- context [temp _X2 (Vint ?E)] => change E with (col 2 S0) end.
  match goal with |- context [temp _X3 (Vint ?E)] => change E with (col 3 S0) end.

  forward. unfold Sfor. forward.

  (* ugly hack to avoid type mismatch between
   "(val * (val * list val))%type" and "reptype t_struct_aesctx" *)
  assert (exists (v: reptype t_struct_aesctx), v =
       (Vint (Int.repr Nr),
          (field_address t_struct_aesctx [ArraySubsc 0; StructField _buf] ctx,
          map Vint (map Int.repr buf))))
  as EE by (eexists; reflexivity).

  destruct EE as [vv EE].

  remember (mbed_tls_enc_rounds 12 S0 buf 4) as S12.

  apply semax_pre with (P' := 
  (EX i: Z, PROP ( 
     0 <= i <= 6
  ) LOCAL (
     temp _i (Vint (Int.repr i));
     temp _RK (field_address t_struct_aesctx [ArraySubsc (52 - i*8); StructField _buf] ctx);
     temp _X3 (Vint (col 3 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _X2 (Vint (col 2 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _X1 (Vint (col 1 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _X0 (Vint (col 0 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx
  ))).
  { subst vv. Exists 6. entailer!. }

  eapply semax_seq' with (P' :=
  PROP ( )
  LOCAL (
     temp _RK (field_address t_struct_aesctx [ArraySubsc 52; StructField _buf] ctx);
     temp _X3 (Vint (col 3 S12));
     temp _X2 (Vint (col 2 S12));
     temp _X1 (Vint (col 1 S12));
     temp _X0 (Vint (col 0 S12));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx 
  )).
  { apply semax_loop with (
  (EX i: Z, PROP ( 
     0 < i <= 6
  ) LOCAL (
     temp _i (Vint (Int.repr i));
     temp _RK (field_address t_struct_aesctx [ArraySubsc (52 - (i-1)*8); StructField _buf] ctx);
     temp _X3 (Vint (col 3 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat (i-1))) S0 buf 4)));
     temp _X2 (Vint (col 2 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat (i-1))) S0 buf 4)));
     temp _X1 (Vint (col 1 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat (i-1))) S0 buf 4)));
     temp _X0 (Vint (col 0 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat (i-1))) S0 buf 4)));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx
  ))).
  { (* loop body *) 
  Intro i.
  reassoc_seq.

  forward_if
  (EX i: Z, PROP ( 
     0 < i <= 6
  ) LOCAL (
     temp _i (Vint (Int.repr i));
     temp _RK (field_address t_struct_aesctx [ArraySubsc (52 - i*8); StructField _buf] ctx);
     temp _X3 (Vint (col 3 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _X2 (Vint (col 2 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _X1 (Vint (col 1 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _X0 (Vint (col 0 (mbed_tls_enc_rounds (12 - 2 * (Z.to_nat i)) S0 buf 4)));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx
  )).
  { (* then-branch: Sskip to body *)
  Intros. forward. Exists i.
  rewrite Int.signed_repr in *; [ | repable_signed ]. (* TODO floyd why is this not automatic? *)
  entailer!.
  }
  { (* else-branch: exit loop *)
  Intros.
  rewrite Int.signed_repr in *; [ | repable_signed ]. (* TODO floyd why is this not automatic? *)
  forward. assert (i = 0) by omega. subst i.
  change (52 - 0 * 8) with 52.
  change (12 - 2 * Z.to_nat 0)%nat with 12%nat.
  replace (mbed_tls_enc_rounds 12 S0 buf 4) with S12 by reflexivity. (* interestingly, if we use
     "change" instead of "replace", it takes much longer *)
  entailer!.
  }
  { (* rest: loop body *)
  clear i. Intro i. Intros. 
  unfold tables_initialized. subst vv.
  pose proof masked_byte_range.

  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.

  replace (52 - i * 8 + 1 + 1 + 1 + 1) with (52 - i * 8 + 4) by omega.
  replace (52 - i * 8 + 1 + 1 + 1)     with (52 - i * 8 + 3) by omega.
  replace (52 - i * 8 + 1 + 1)         with (52 - i * 8 + 2) by omega.

  pose (S' := mbed_tls_fround (mbed_tls_enc_rounds (12-2*Z.to_nat i) S0 buf 4) buf (52-i*8)).

  match goal with |- context [temp _Y0 (Vint ?E0)] =>
    match goal with |- context [temp _Y1 (Vint ?E1)] =>
      match goal with |- context [temp _Y2 (Vint ?E2)] =>
        match goal with |- context [temp _Y3 (Vint ?E3)] =>
          assert (S' = (E0, (E1, (E2, E3)))) as Eq2
        end
      end
    end
  end.
  {
    subst S'.
    rewrite (split_four_ints (mbed_tls_enc_rounds (12 - 2 * Z.to_nat i) S0 buf 4)).
    reflexivity.
  }
  apply split_four_ints_eq in Eq2. destruct Eq2 as [EqY0 [EqY1 [EqY2 EqY3]]].
  rewrite EqY0. rewrite EqY1. rewrite EqY2. rewrite EqY3.
  clear EqY0 EqY1 EqY2 EqY3.

  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.

  pose (S'' := mbed_tls_fround S' buf (52-i*8+4)).

  replace (52 - i * 8 + 4 + 1 + 1 + 1 + 1) with (52 - i * 8 + 4 + 4) by omega.
  replace (52 - i * 8 + 4 + 1 + 1 + 1)     with (52 - i * 8 + 4 + 3) by omega.
  replace (52 - i * 8 + 4 + 1 + 1)         with (52 - i * 8 + 4 + 2) by omega.

  match goal with |- context [temp _X0 (Vint ?E0)] =>
    match goal with |- context [temp _X1 (Vint ?E1)] =>
      match goal with |- context [temp _X2 (Vint ?E2)] =>
        match goal with |- context [temp _X3 (Vint ?E3)] =>
          assert (S'' = (E0, (E1, (E2, E3)))) as Eq2
        end
      end
    end
  end.
  {
    subst S''.
    rewrite (split_four_ints S').
    reflexivity.
  }
  apply split_four_ints_eq in Eq2. destruct Eq2 as [EqX0 [EqX1 [EqX2 EqX3]]].
  rewrite EqX0. rewrite EqX1. rewrite EqX2. rewrite EqX3.
  clear EqX0 EqX1 EqX2 EqX3.

  Exists i.
  replace (52 - i * 8 + 4 + 4) with (52 - (i - 1) * 8) by omega.
  subst S' S''.
  assert (
    (mbed_tls_fround
      (mbed_tls_fround
         (mbed_tls_enc_rounds (12 - 2 * Z.to_nat i) S0 buf 4)
         buf
         (52 - i * 8))
      buf
      (52 - i * 8 + 4))
  = (mbed_tls_enc_rounds (12 - 2 * Z.to_nat (i - 1)) S0 buf 4)) as Eq2. {
    replace (12 - 2 * Z.to_nat (i - 1))%nat with (S (S (12 - 2 * Z.to_nat i))).
    - unfold mbed_tls_enc_rounds (*at 2*). fold mbed_tls_enc_rounds.
      f_equal.
      * f_equal.
        rewrite Nat2Z.inj_sub. {
          change (Z.of_nat 12) with 12.
          rewrite Nat2Z.inj_mul.
          change (Z.of_nat 2) with 2.
          rewrite Z2Nat.id; omega.
        }
        assert (Z.to_nat i <= 6)%nat. {
          change 6%nat with (Z.to_nat 6).
          apply Z2Nat.inj_le; omega.
        }
        omega.
      * rewrite Nat2Z.inj_succ.
        change 2%nat with (Z.to_nat 2) at 2.
        rewrite <- Z2Nat.inj_mul; [ | omega | omega ].
        change 12%nat with (Z.to_nat 12).
        rewrite <- Z2Nat.inj_sub; [ | omega ].
        rewrite Z2Nat.id; omega.
    - rewrite Z2Nat.inj_sub; [ | omega ].
      change (Z.to_nat 1) with 1%nat.
      assert (Z.to_nat i <= 6)%nat. {
        change 6%nat with (Z.to_nat 6).
        apply Z2Nat.inj_le; omega.
      }
      assert (0 < Z.to_nat i)%nat. {
        change 0%nat with (Z.to_nat 0).
        apply Z2Nat.inj_lt; omega.
      }
      omega.
  }
  rewrite Eq2. clear Eq2.
  remember (mbed_tls_enc_rounds (12 - 2 * Z.to_nat (i - 1)) S0 buf 4) as S''.
  remember (mbed_tls_fround (mbed_tls_enc_rounds (12 - 2 * Z.to_nat i) S0 buf 4) buf (52 - i * 8)) as S'.
  replace (52 - i * 8 + 4 + 4) with (52 - (i - 1) * 8) by omega.
  entailer!.
  }} { (* loop decr *)
  Intro i. forward. unfold loop2_ret_assert. Exists (i-1). entailer!.
  }} {
  abbreviate_semax. subst vv. unfold tables_initialized.
  pose proof masked_byte_range.

  (* 2nd-to-last AES round: just a normal AES round, but not inside the loop *)

  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.

  remember (mbed_tls_fround S12 buf 52) as S13.

  match goal with |- context [temp _Y0 (Vint ?E0)] =>
    match goal with |- context [temp _Y1 (Vint ?E1)] =>
      match goal with |- context [temp _Y2 (Vint ?E2)] =>
        match goal with |- context [temp _Y3 (Vint ?E3)] =>
          assert (S13 = (E0, (E1, (E2, E3)))) as Eq2
        end
      end
    end
  end.
  {
    subst S13.
    rewrite (split_four_ints S12).
    forget 12%nat as N.
    reflexivity.
  }
  apply split_four_ints_eq in Eq2. destruct Eq2 as [EqY0 [EqY1 [EqY2 EqY3]]].
  rewrite EqY0. rewrite EqY1. rewrite EqY2. rewrite EqY3.
  clear EqY0 EqY1 EqY2 EqY3.

  (* last AES round: special (uses S-box instead of forwarding tables) *)
  assert (forall i, Int.unsigned (Znth i FSb Int.zero) <= Byte.max_unsigned). {
    intros. pose proof (FSb_range i) as P. change 256 with (Byte.max_unsigned + 1) in P. omega.
  }

  (* We have to hide the definition of S12 and S13 for subst, because otherwise the entailer
     will substitute them and then call my_auto, which calls now, which calls easy, which calls
     inversion on a hypothesis containing the substituted S12, which takes forever, because it
     tries to simplify S12.
     TODO floyd or documentation: What should users do if "forward" takes forever? *)
  pose proof (HeqS12, HeqS13) as hidden. clear HeqS12 HeqS13.

  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.
  forward. forward. simpl (temp _RK _). rewrite Eq by omega. forward. do 4 forward. forward.

  remember (mbed_tls_final_fround S13 buf 56) as S14.

  match goal with |- context [temp _X0 (Vint ?E0)] =>
    match goal with |- context [temp _X1 (Vint ?E1)] =>
      match goal with |- context [temp _X2 (Vint ?E2)] =>
        match goal with |- context [temp _X3 (Vint ?E3)] =>
          assert (S14 = (E0, (E1, (E2, E3)))) as Eq2
        end
      end
    end
  end.
  {
    subst S14.
    rewrite (split_four_ints S13).
    forget 12%nat as N.
    reflexivity.
  }
  apply split_four_ints_eq in Eq2. destruct Eq2 as [EqX0 [EqX1 [EqX2 EqX3]]].
  rewrite EqX0. rewrite EqX1. rewrite EqX2. rewrite EqX3.
  clear EqX0 EqX1 EqX2 EqX3.

  Ltac entailer_for_load_tac ::= idtac.

  Ltac remember_temp_Vints done :=
  lazymatch goal with
  | |- context [ ?T :: done ] => match T with
    | temp ?Id (Vint ?V) =>
      let V0 := fresh "V" in remember V as V0;
      remember_temp_Vints ((temp Id (Vint V0)) :: done)
    | _ => remember_temp_Vints (T :: done)
    end
  | |- semax _ (PROPx _ (LOCALx done (SEPx _))) _ _ => idtac
  | _ => fail 100 "assertion failure: did not find" done
  end.

  remember_temp_Vints (@nil localdef).
  forward.

  Ltac simpl_upd_Znth := match goal with
  | |- context [ (upd_Znth ?i ?l (Vint ?v)) ] =>
    let vv := fresh "vv" in remember v as vv;
    let a := eval cbv in (upd_Znth i l (Vint vv)) in change (upd_Znth i l (Vint vv)) with a
  end.

  simpl_upd_Znth.
  forward. simpl_upd_Znth. forward. simpl_upd_Znth. forward. simpl_upd_Znth.
  do 4 (forward; simpl_upd_Znth).
  do 4 (forward; simpl_upd_Znth).
  do 4 (forward; simpl_upd_Znth).

  cbv [cast_int_int] in *.
  rewrite zero_ext_mask in *.
  rewrite zero_ext_mask in *.
  rewrite Int.and_assoc in *.
  rewrite Int.and_assoc in *.
  rewrite Int.and_idem in *.
  rewrite Int.and_idem in *.
  repeat subst. remember (exp_key ++ list_repeat 8 0) as buf.

  match goal with
  | |- context [ field_at _ _ _ ?res output ] =>
     assert (res = (map Vint (mbed_tls_aes_enc plaintext buf))) as Eq3
  end. {
  unfold mbed_tls_aes_enc. progress unfold output_four_ints_as_bytes. progress unfold put_uint32_le.
  repeat match goal with
  | |- context [ Int.and ?a ?b ] => let va := fresh "va" in remember (Int.and a b) as va
  end.
  cbv.
  repeat subst. remember (exp_key ++ list_repeat 8 0) as buf.
  destruct hidden as [? ?].
  subst S0 S12 S13.
  remember 12%nat as twelve.
  unfold mbed_tls_enc_rounds. fold mbed_tls_enc_rounds.
  assert (4 + 4 * Z.of_nat twelve = 52) as Eq4. { subst twelve. reflexivity. }
  rewrite Eq4. clear Eq4.
  reflexivity.
  }
  rewrite Eq3. clear Eq3.

  Ltac entailer_for_return ::= idtac.

  (* TODO reuse from above *)
  assert ((field_address t_struct_aesctx [StructField _buf] ctx)
        = (field_address t_struct_aesctx [ArraySubsc 0; StructField _buf] ctx)) as EqBuf. {
    do 2 rewrite field_compatible_field_address by auto with field_compatible.
    reflexivity.
  }
  rewrite <- EqBuf in *.

  (* return None *)
  forward.
  remember (mbed_tls_aes_enc plaintext buf) as Res.
  unfold tables_initialized.
  entailer!.
  }

  Show.
Time Qed.

(* TODO floyd: sc_new_instantiate: distinguish between errors caused because the tactic is trying th
   wrong thing and errors because of user type errors such as "tuint does not equal t_struct_aesctx" *)

(* TODO floyd: compute_nested_efield should not fail silently *)

(* TODO floyd: if field_address is given a gfs which doesn't match t, it should not fail silently,
   or at least, the tactics should warn.
   And same for nested_field_offset. *)

(* TODO floyd: I want "omega" for int instead of Z
   maybe "autorewrite with entailer_rewrite in *"
*)

(* TODO floyd: when load_tac should tell that it cannot handle memory access in subexpressions *)

(* TODO floyd: for each tactic, test how it fails when variables are missing in Pre *)

(*
Note:
field_compatible/0 -> legal_nested_field/0 -> legal_field/0:
  legal_field0 allows an array index to point 1 past the last array cell, legal_field disallows this
*)
