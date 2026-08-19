package HRA.Output is

   --  Write String values as their exact UTF-8 bytes. GNAT's Ada.Text_IO may
   --  transcode Character values according to the wide-character encoding
   --  method, which double-encodes UTF-8 source bytes held in String.
   procedure Put (Text : String);
   procedure Put_Line (Text : String);
   procedure New_Line;

   procedure Put_Error (Text : String);
   procedure Put_Error_Line (Text : String);

end HRA.Output;
