with Ada.Environment_Variables;
with Ada.Text_IO;

package body Crash_Points is
   procedure After_WAL_Persist is
      Ready : Ada.Text_IO.File_Type;
   begin
      --  Normal runs return immediately. Only a test child enables this.
      if Ada.Environment_Variables.Value ("LEDGER_CRASH_POINT", "") /=
        "after_wal_persist"
      then
         return;
      end if;

      --  Reaching this hook means the caller has finished its WAL write.
      Ada.Text_IO.Create (Ready, Ada.Text_IO.Out_File, "crash.ready");
      Ada.Text_IO.Put_Line (Ready, "after_wal_persist");
      Ada.Text_IO.Close (Ready);

      --  Never proceed to the storage update. The harness forcibly kills
      --  this process; raising an exception would allow normal cleanup.
      loop
         delay 0.05;
      end loop;
   end After_WAL_Persist;
end Crash_Points;
