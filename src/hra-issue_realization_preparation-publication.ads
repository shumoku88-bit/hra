with HRA.Writer;

--  Ordered single-target publication of one opaque prepared Issue realization.
--
--  This boundary always publishes Actual, relation, then Issue. Each successful
--  step establishes a valid prefix world. A later failure preserves that prefix;
--  no cross-step rollback, lock, multi-target atomicity, or crash durability is
--  provided or implied.
package HRA.Issue_Realization_Preparation.Publication is

   type Confirmed_World is (W0, W1, W2, W3);

   type Publication_Step is
     (Publishing_Actual,
      Publishing_Relation,
      Publishing_Issue);

   type Failure_Kind is
     (Writer_Failure,
      Domain_Admission_Failure,
      Invalid_Prepared_Witness);

   type Result_Kind is (Completed, Failed);

   type Publication_Result (Kind : Result_Kind := Completed) is record
      Last_Confirmed : Confirmed_World := W0;
      Writer_Status  : HRA.Writer.Writer_Status := HRA.Writer.Success;
      Message        : Unbounded_String;
      case Kind is
         when Completed =>
            null;
         when Failed =>
            Failed_Step : Publication_Step := Publishing_Actual;
            Failure     : Failure_Kind := Writer_Failure;
      end case;
   end record;

   function Publish
     (Prepared : Prepared_Realization;
      Result   : out Publication_Result) return Boolean
     with Post =>
       (if Publish'Result
        then Result.Kind = Completed and then Result.Last_Confirmed = W3
        else Result.Kind = Failed);

end HRA.Issue_Realization_Preparation.Publication;
