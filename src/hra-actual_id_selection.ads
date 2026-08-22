with HRA.Actual_Admission;

--  Clock-free selection of one fresh source-durable identity candidate for an
--  ordinary Actual publication.
--
--  No counter file, machine clock, randomness, or filesystem observation is an
--  authority here. Selection depends only on the already-admitted effective
--  Actual identity universe. Publication staleness remains Writer's concern.
package HRA.Actual_Id_Selection is

   type Selection_Status is
     (Success,
      Identity_Space_Exhausted,
      Generated_Identity_Invalid);

   --  Choose the first unused canonical identity of the form:
   --
   --    hra-actual-N
   --
   --  where N is a positive decimal integer. Effective identities are checked,
   --  not only explicit event-id provenance, so the selector cannot knowingly
   --  collide with any identity already admitted by Actual_Admission.
   function Select_Next
     (Observation : HRA.Actual_Admission.Actual_Observation;
      ID          : out HRA.Actual_Admission.Actual_Id;
      Status      : out Selection_Status) return Boolean;

end HRA.Actual_Id_Selection;
