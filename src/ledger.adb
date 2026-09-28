with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;
with Crash_Points;
with Demo_Backend;

--  The demo performs OS/file I/O, so it is outside the SPARK proof boundary.
procedure Ledger with SPARK_Mode => Off is
   use Ada.Command_Line;

   procedure Usage;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line ("Ledger crash/recovery learning demo");
      Ada.Text_IO.Put_Line
        ("  ledger demo-write <integer-key> <integer-value>");
      Ada.Text_IO.Put_Line ("  ledger demo-recover");
      Ada.Text_IO.Put_Line ("  ledger demo-dump");
      Ada.Text_IO.Put_Line
        ("Run in an empty TEST directory; files use that directory.");
   end Usage;
begin
   if Argument_Count = 0 then
      Usage;
   elsif Argument (1) = "demo-write" and then Argument_Count = 3 then
      declare
         Data : constant Demo_Backend.Record_Data :=
           (Key   => Integer'Value (Argument (2)),
            Value => Integer'Value (Argument (3)));
      begin
         Demo_Backend.Write_WAL (Data);
         Crash_Points.After_WAL_Persist;
         Demo_Backend.Apply_To_Store (Data);
      end;
   elsif Argument (1) = "demo-recover" and then Argument_Count = 1 then
      Demo_Backend.Replay;
   elsif Argument (1) = "demo-dump" and then Argument_Count = 1 then
      --  Read the storage component; do not read the WAL for the comparison.
      Ada.Text_IO.Put_Line (Demo_Backend.Image (Demo_Backend.Read_Store));
   else
      Usage;
      Set_Exit_Status (Failure);
   end if;
exception
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Ada.Exceptions.Exception_Name (Error) & ": " &
           Ada.Exceptions.Exception_Message (Error));
      Set_Exit_Status (Failure);
end Ledger;
