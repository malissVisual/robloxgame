--!strict
-- 8.5.1: the version these scripts were written for (tests/run_tests.py checks it equals Config.Version). Studio does
-- not always take every changed script from a sync (it kept an old ReplicatedStorage.Shared, Config among it, twice
-- after 8.4 and 8.5): server/SandboxBoot.luau and client/Main.client.luau compare this with Config.Version and with
-- the other side's stamp (workspace attribute "ServerBuild") and, when they differ, say so loudly (in Studio: a red
-- banner with what to delete and sync again).
return "9.0"
