package HRA.Terminal_Layout is

   type Alignment is (Left, Right);

   --  Return the number of terminal cells occupied by UTF-8 Text. The caller
   --  must first activate the process locale through Terminal_UTF8.Initialize.
   --  The shared C terminal boundary owns multibyte decoding and wcwidth policy.
   --  Invalid UTF-8 or a glyph without a terminal width raises Constraint_Error.
   function Display_Width (Text : String) return Natural;

   --  Padding is measured in terminal cells, not String bytes.  Text is never
   --  truncated when it is already as wide as (or wider than) Width.
   function Pad_Left (Text : String; Width : Natural) return String;
   function Pad_Right (Text : String; Width : Natural) return String;

   function Align
     (Text          : String;
      Width         : Natural;
      Justification : Alignment) return String;

end HRA.Terminal_Layout;
