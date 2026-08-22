with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA.Account;
with HRA.Actual_Admission;
with HRA.Actual_Graph_Admission;

--  Pure Account-universe qualification of an already-admitted Actual graph.
--
--  No Account meaning is inferred from name prefixes. Every posting Account in
--  the complete candidate graph must resolve through the supplied canonical
--  Account_Registry. The registry is copied into the opaque result as the
--  admission premise and is never mutated here.
package HRA.Actual_Account_Admission is

   type Account_Qualified_Graph is private;

   function Observation_Of
     (Candidate : Account_Qualified_Graph)
      return HRA.Actual_Admission.Actual_Observation;

   --  Preserve the exact already-admitted graph for later boundaries that must
   --  consume its retained source witness. Callers still cannot construct an
   --  Account_Qualified_Graph without successful Account-universe admission.
   function Graph_Of
     (Candidate : Account_Qualified_Graph)
      return HRA.Actual_Graph_Admission.Candidate_Graph;

   type Admission_Status is
     (Success,
      Undeclared_Account);

   type Admission_Diagnostic is record
      Status            : Admission_Status := Success;
      Transaction_Index : Natural := 0;
      Posting_Index     : Natural := 0;
      Account_Name      : Unbounded_String;
      Message           : Unbounded_String;
   end record;

   function Admit
     (Registry  : HRA.Account.Account_Registry;
      Graph     : HRA.Actual_Graph_Admission.Candidate_Graph;
      Candidate : out Account_Qualified_Graph;
      Diag      : out Admission_Diagnostic) return Boolean;

private

   type Account_Qualified_Graph is record
      Registry_Premise : HRA.Account.Account_Registry;
      Graph_Value      : HRA.Actual_Graph_Admission.Candidate_Graph;
   end record;

end HRA.Actual_Account_Admission;
