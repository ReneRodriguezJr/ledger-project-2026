with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Demo_Backend is
   WAL_Path   : constant String := "wal.txt";
   Store_Path : constant String := "store.txt";

   procedure Write_Record (Path : String; Data : Record_Data);
   function Read_Record (Path : String) return Record_Data;

   function Image (Data : Record_Data) return String is
   begin
      return Ada.Strings.Fixed.Trim
        (Integer'Image (Data.Key), Ada.Strings.Both)
        & " " & Ada.Strings.Fixed.Trim
          (Integer'Image (Data.Value), Ada.Strings.Both);
   end Image;

   procedure Write_Record (Path : String; Data : Record_Data) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Image (Data));
      Ada.Text_IO.Flush (File);
      Ada.Text_IO.Close (File);
   end Write_Record;

   function Read_Record (Path : String) return Record_Data is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      declare
         Line      : constant String := Ada.Text_IO.Get_Line (File);
         Separator : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
      begin
         --  The demo accepts exactly one line containing two integers.
         if Separator = 0 or else not Ada.Text_IO.End_Of_File (File) then
            raise Ada.Text_IO.Data_Error with "expected exactly one record";
         end if;
         Ada.Text_IO.Close (File);
         return
           (Key   => Integer'Value (Line (Line'First .. Separator - 1)),
            Value => Integer'Value (Line (Separator + 1 .. Line'Last)));
      end;
   end Read_Record;

   procedure Write_WAL (Data : Record_Data) is
   begin
      --  This intentionally replaces a SINGLE record, not a production log.
      --  For this demo, the complete closed record is a committed operation.
      Write_Record (WAL_Path, Data);
   end Write_WAL;

   procedure Apply_To_Store (Data : Record_Data) is
   begin
      Write_Record (Store_Path, Data);
   end Apply_To_Store;

   procedure Replay is
      Data : constant Record_Data := Read_Record (WAL_Path);
   begin
      --  The recovered value comes from the WAL, not the test's oracle.
      Apply_To_Store (Data);
   end Replay;

   function Read_Store return Record_Data is
   begin
      return Read_Record (Store_Path);
   end Read_Store;
end Demo_Backend;
