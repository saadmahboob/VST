Require Import sepcomp.semantics.
Require Import sepcomp.simulations.
Require Import veric.base.
Require Import veric.Clight_lemmas.
Require compcert.common.Globalenvs.
Require Import compcert.common.Events.
Require Import compcert.cfrontend.Clight.

Inductive CC_core : Type :=
    CC_core_State : function ->
            statement -> cont -> env -> temp_env -> CC_core
  | CC_core_Callstate : fundef -> list val -> cont -> CC_core
  | CC_core_Returnstate : val -> cont -> CC_core.

Definition CC_core_to_CC_state (c:CC_core) (m:mem) : state :=
  match c with
     CC_core_State f st k e te => State f st k e te m
  |  CC_core_Callstate fd args k => Callstate fd args k m
  | CC_core_Returnstate v k => Returnstate v k m
 end.
Definition CC_state_to_CC_core (c:state): CC_core * mem :=
  match c with
     State f st k e te m => (CC_core_State f st k e te, m)
  |  Callstate fd args k m => (CC_core_Callstate fd args k, m)
  | Returnstate v k m => (CC_core_Returnstate v k, m)
 end.

Lemma  CC_core_CC_state_1: forall c m,
   CC_state_to_CC_core  (CC_core_to_CC_state c m) = (c,m).
  Proof. intros. destruct c; auto. Qed.

Lemma  CC_core_CC_state_2: forall s c m,
   CC_state_to_CC_core  s = (c,m) -> s= CC_core_to_CC_state c m.
  Proof. intros. destruct s; simpl in *.
      destruct c; simpl in *; inv H; trivial.
      destruct c; simpl in *; inv H; trivial.
      destruct c; simpl in *; inv H; trivial.
  Qed.

Lemma  CC_core_CC_state_3: forall s c m,
   s= CC_core_to_CC_state c m -> CC_state_to_CC_core  s = (c,m).
  Proof. intros. subst. apply CC_core_CC_state_1. Qed.

Lemma  CC_core_CC_state_4: forall s, exists c, exists m, s =  CC_core_to_CC_state c m.
  Proof. intros. destruct s.
             exists (CC_core_State f s k e le). exists m; reflexivity.
             exists (CC_core_Callstate fd args k). exists m; reflexivity.
             exists (CC_core_Returnstate res k). exists m; reflexivity.
  Qed.

Lemma CC_core_to_CC_state_inj: forall c m c' m',
     CC_core_to_CC_state c m = CC_core_to_CC_state c' m' -> (c',m')=(c,m).
  Proof. intros.
       apply  CC_core_CC_state_3 in H. rewrite  CC_core_CC_state_1 in H.  inv H. trivial.
  Qed.

Definition cl_halted (c: CC_core) : option val := None.

Definition empty_function : function := mkfunction Tvoid cc_default nil nil nil Sskip.

Fixpoint temp_bindings (i: positive) (vl: list val) :=
 match vl with
 | nil => PTree.empty val
 | v::vl' => PTree.set i v (temp_bindings (i+1)%positive vl')
 end.

Fixpoint params_of_types (i: positive) (l : list type) : list (ident * type) :=
  match l with
  | nil => nil
  | t :: l => (i, t) :: params_of_types (i+1)%positive l
  end.

Fixpoint typelist2list (tl: typelist) : list type :=
  match tl with
  | Tcons t r => t::typelist2list r
  | Tnil => nil
  end.

Definition params_of_fundef (f: fundef) : list type :=
  match f with
  | Internal {| fn_params := fn_params |} => map snd fn_params
  | External _ t _ _ => typelist2list t
  end.

Definition cl_initial_core (ge: genv) (v: val) (args: list val) : option CC_core :=
  match v with
    Vptr b i =>
    if Int.eq_dec i Int.zero then
      match Genv.find_funct_ptr ge b with
        Some f =>
        Some (CC_core_State empty_function 
                    (Scall None
                                 (Etempvar 1%positive (type_of_fundef f))
                                 (map (fun x => Etempvar (fst x) (snd x))
                                      (params_of_types 2%positive
                                                       (params_of_fundef f))))
                     (Kseq (Sloop Sskip Sskip) Kstop)
             empty_env
             (temp_bindings 1%positive (v::args)))
      | _ => None end
    else None
  | _ => None
  end.

Definition cl_at_external (c: CC_core) : option (external_function * list val) :=
  match c with
  | CC_core_Callstate (External ef _ _ _) args _ => Some (ef, args)
  | _ => None
end.

Definition cl_after_external (vret: option val) (c: CC_core) : option CC_core :=
   match c with
   | CC_core_Callstate (External ef _ _ _) _ k => 
        Some (CC_core_Returnstate (match vret with Some v => v | _ => Vundef end) k)
   | _ => None
   end.

Definition cl_step ge (q: CC_core) (m: mem) (q': CC_core) (m': mem) : Prop :=
    cl_at_external q = None /\ 
     Clight.step ge (Clight.function_entry2 ge)
      (CC_core_to_CC_state q m) Events.E0 (CC_core_to_CC_state q' m').

Lemma cl_corestep_not_at_external:
  forall ge m q m' q', 
          cl_step ge q m q' m' -> cl_at_external q = None.
Proof.
  intros.
  unfold cl_step in H. destruct H; auto.  
Qed.

Lemma cl_corestep_not_halted :
  forall ge m q m' q', cl_step ge q m q' m' -> cl_halted q = None.
Proof.
  intros.
  simpl; auto.
Qed.

Lemma cl_after_at_external_excl :
  forall retv q q', cl_after_external retv q = Some q' -> cl_at_external q' = None.
Proof.
intros until q'; intros H.
unfold cl_after_external in H.
destruct q; inv H. destruct f; inv H1. reflexivity.
Qed.

Program Definition cl_core_sem :
  @CoreSemantics genv CC_core mem :=
  @Build_CoreSemantics _ _ _
    (*deprecated cl_init_mem*)
    cl_initial_core
    cl_at_external
    cl_after_external
    cl_halted
    cl_step
    cl_corestep_not_at_external
    cl_corestep_not_halted _.
