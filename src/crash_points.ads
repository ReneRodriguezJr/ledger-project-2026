--  Test instrumentation. The harness kills the process while it is paused.
package Crash_Points with SPARK_Mode => Off is
   procedure After_WAL_Persist;
end Crash_Points;
