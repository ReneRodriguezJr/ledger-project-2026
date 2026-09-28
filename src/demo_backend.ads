--  TEMPORARY one-record backend for learning the crash/recovery workflow.
--  Replace this package's uses with the team's WAL and storage interfaces.
--  Text_IO.Close makes the bytes available across a PROCESS crash. It is
--  not an fsync/FlushFileBuffers guarantee against machine power loss.
package Demo_Backend with SPARK_Mode => Off is
   type Record_Data is record
      Key   : Integer;
      Value : Integer;
   end record;

   procedure Write_WAL (Data : Record_Data);
   procedure Apply_To_Store (Data : Record_Data);
   procedure Replay;
   function Read_Store return Record_Data;
   function Image (Data : Record_Data) return String;
end Demo_Backend;
