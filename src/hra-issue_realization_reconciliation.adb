with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Actual_Candidate;

package body HRA.Issue_Realization_Reconciliation is

   use type HRA.Actual_Admission.Actual_Id;
   use type HRA.Dates.Date;
   use type HRA.Issue_Relation.Relation_Event_Id;
   use type HRA.Issue_Relation.Relation_Kind;
   use type HRA.Issue_Relation.Sidecar.Presence;
   use type HRA.Issues.Issue_Closed_Kind;
   use type HRA.Issues.Issue_Id;
   use type HRA.Issues.Issue_Status;
   use type HRA.Ledger.Transaction;

   function Reconcile
     (State                : HRA.Household.Household_State;
      Tx                   : HRA.Ledger.Transaction;
      Issue_ID             : HRA.Issues.Issue_Id;
      Actual_ID            : HRA.Actual_Admission.Actual_Id;
      Relation_Event_ID    : HRA.Issue_Relation.Relation_Event_Id;
      Relation_Recorded_On : HRA.Dates.Date;
      Closed_On            : HRA.Dates.Date;
      Relation_Details     : String;
      Relation_Observation : HRA.Issue_Relation.Sidecar.Observation;
      World                : out Recognized_World;
      Diag                 : out Reconciliation_Diagnostic) return Boolean
   is
      Actual_Block : HRA.Actual_Candidate.Candidate_Block;
      Actual_Diag  : HRA.Actual_Candidate.Candidate_Diagnostic;
      Requested_Relation : HRA.Issue_Relation.Relation_Event;
      Relation_Creation  : HRA.Issue_Relation.Create_Status :=
        HRA.Issue_Relation.Create_Success;
      Relations     : HRA.Issue_Relation.Admission.Admitted_History;
      Relation_Diag : HRA.Issue_Relation.Admission.Admission_Diagnostic :=
        (Status => HRA.Issue_Relation.Admission.Success);
      Issue_Index    : Natural := 0;
      Actual_Index   : Natural := 0;
      Relation_Index : Natural := 0;

      pragma Unreferenced (Actual_Block);

      procedure Set_Diagnostic
        (Status  : Reconciliation_Status;
         Message : String) is
      begin
         Diag :=
           (Status             => Status,
            Actual             => Actual_Diag,
            Relation_Creation  => Relation_Creation,
            Relation_Admission => Relation_Diag,
            Message            => To_Unbounded_String (Message));
      end Set_Diagnostic;

      function Relation_Matches
        (Existing : HRA.Issue_Relation.Relation_Event) return Boolean is
      begin
         return
           HRA.Issue_Relation.Kind (Existing) =
             HRA.Issue_Relation.Kind (Requested_Relation)
           and then HRA.Issue_Relation.Event_Id (Existing) =
             HRA.Issue_Relation.Event_Id (Requested_Relation)
           and then HRA.Issue_Relation.Recorded_On (Existing) =
             HRA.Issue_Relation.Recorded_On (Requested_Relation)
           and then HRA.Issue_Relation.Issue_Id (Existing) =
             HRA.Issue_Relation.Issue_Id (Requested_Relation)
           and then HRA.Issue_Relation.Actual_Id (Existing) =
             HRA.Issue_Relation.Actual_Id (Requested_Relation)
           and then HRA.Issue_Relation.Details (Existing) =
             HRA.Issue_Relation.Details (Requested_Relation);
      end Relation_Matches;

      function Is_Open_Prefix_Issue
        (Issue : HRA.Issues.Household_Issue) return Boolean is
        (Issue.Status = HRA.Issues.Open
         and then Issue.Closed.Kind = HRA.Issues.Not_Closed);

      function Is_Requested_Resolved_Issue
        (Issue : HRA.Issues.Household_Issue) return Boolean is
        (Issue.Status = HRA.Issues.Resolved
         and then Issue.Closed.Kind = HRA.Issues.Closed_On
         and then Issue.Closed.Closed_Date = Closed_On);
   begin
      World := W0;

      --  Validate the caller's Actual request through the same source-local
      --  round-trip used by ordinary preparation. This deliberately does not
      --  append it to the current graph, so an already published matching ID is
      --  available for semantic comparison rather than misread as a fresh add.
      if not HRA.Actual_Candidate.Prepare_Identified
        (Tx, Actual_ID, Actual_Block, Actual_Diag)
      then
         Set_Diagnostic
           (Actual_Request_Rejected,
            "re-presented identified Actual request is not a valid candidate");
         return False;
      end if;

      if not HRA.Issue_Relation.Create_Realized_As
        (Event_ID    => Relation_Event_ID,
         Recorded_On => Relation_Recorded_On,
         Issue_ID    => Issue_ID,
         Actual_ID   => Actual_ID,
         Details     => Relation_Details,
         Event       => Requested_Relation,
         Status      => Relation_Creation)
      then
         Set_Diagnostic
           (Relation_Request_Rejected,
            "re-presented Realized_As request is not valid");
         return False;
      end if;

      if not HRA.Issue_Relation.Sidecar.Is_For_Root
        (Relation_Observation, To_String (State.Root_Path))
      then
         Set_Diagnostic
           (Relation_Observation_Root_Mismatch,
            "Issue relation observation belongs to a different Household root");
         return False;
      end if;

      for I in 1 .. HRA.Issues.Count (State.Issues) loop
         if HRA.Issues.Element (State.Issues, I).ID = Issue_ID then
            Issue_Index := I;
            exit;
         end if;
      end loop;

      if Issue_Index = 0 then
         Set_Diagnostic
           (Issue_Not_Found,
            "requested Issue identity is absent from the admitted Household");
         return False;
      end if;

      --  Admit the current relation source as a whole before interpreting one
      --  event ID. A malformed or dangling sidecar is not a prefix witness.
      if HRA.Issue_Relation.Sidecar.State_Of (Relation_Observation) =
           HRA.Issue_Relation.Sidecar.Present
      then
         if not HRA.Issue_Relation.Admission.Admit
           (HRA.Issue_Relation.Sidecar.Text_Of (Relation_Observation),
            State.Issues,
            State.Actual_Identity,
            Relations,
            Relation_Diag)
         then
            Set_Diagnostic
              (Relation_Source_Admission_Rejected,
               "current Issue relation source does not admit against current endpoints");
            return False;
         end if;

         for I in 1 .. HRA.Issue_Relation.Admission.Count (Relations) loop
            if HRA.Issue_Relation.Event_Id
              (HRA.Issue_Relation.Admission.Element (Relations, I)) =
                Relation_Event_ID
            then
               Relation_Index := I;
               exit;
            end if;
         end loop;
      end if;

      --  Find the request ID in the complete effective identity universe first.
      --  A plan-derived identity collision cannot be reinterpreted as the
      --  source-durable Actual required by Realized_As.
      for I in 1 .. HRA.Actual_Admission.Transaction_Count
        (State.Actual_Identity)
      loop
         declare
            Actual_Item : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At (State.Actual_Identity, I);
         begin
            if Actual_Item.Identity.Present
              and then Actual_Item.Identity.Value = Actual_ID
            then
               Actual_Index := I;
               exit;
            end if;
         end;
      end loop;

      if Actual_Index > 0 then
         declare
            Actual_Item : constant HRA.Actual_Admission.Actual_Transaction_Entry :=
              HRA.Actual_Admission.Transaction_At
                (State.Actual_Identity, Positive (Actual_Index));
            Expected : HRA.Ledger.Transaction := Tx;
         begin
            if not Actual_Item.Source_Durable_Identity.Present
              or else Actual_Item.Source_Durable_Identity.Value /= Actual_ID
            then
               Set_Diagnostic
                 (Actual_Identity_Collision,
                  "existing Actual identity is not the requested source-durable identity");
               return False;
            end if;

            Expected.Event_ID :=
              To_Unbounded_String (HRA.Actual_Admission.Text (Actual_ID));
            if Actual_Item.Tx /= Expected then
               Set_Diagnostic
                 (Actual_Meaning_Mismatch,
                  "existing source-durable Actual ID has different Transaction meaning");
               return False;
            end if;
         end;
      end if;

      if Relation_Index > 0
        and then not Relation_Matches
          (HRA.Issue_Relation.Admission.Element
             (Relations, Positive (Relation_Index)))
      then
         Set_Diagnostic
           (Relation_Meaning_Mismatch,
            "existing relation event ID has different Realized_As meaning");
         return False;
      end if;

      declare
         Issue : constant HRA.Issues.Household_Issue :=
           HRA.Issues.Element (State.Issues, Positive (Issue_Index));
      begin
         if Actual_Index = 0 then
            if Relation_Index /= 0 then
               Set_Diagnostic
                 (Relation_Meaning_Mismatch,
                  "requested relation exists without the requested Actual prefix");
               return False;
            elsif not Is_Open_Prefix_Issue (Issue) then
               Set_Diagnostic
                 (Issue_Lifecycle_Mismatch,
                  "W0 requires the requested Issue to remain Open");
               return False;
            end if;

            World := W0;

         elsif Relation_Index = 0 then
            if not Is_Open_Prefix_Issue (Issue) then
               Set_Diagnostic
                 (Issue_Lifecycle_Mismatch,
                  "W1 requires the requested Issue to remain Open");
               return False;
            end if;

            World := W1;

         elsif Is_Open_Prefix_Issue (Issue) then
            World := W2;

         elsif Is_Requested_Resolved_Issue (Issue) then
            World := W3;

         else
            Set_Diagnostic
              (Issue_Lifecycle_Mismatch,
               "Issue lifecycle does not match the requested W2/W3 realization prefix");
            return False;
         end if;
      end;

      Set_Diagnostic (Success, "");
      return True;
   end Reconcile;

end HRA.Issue_Realization_Reconciliation;
