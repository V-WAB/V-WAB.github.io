-- Banini Butter: the fix, in three lines.
--
-- Your create_preorder cannot see gen_random_bytes, because Supabase keeps
-- pgcrypto in a schema called "extensions" and the function was told to look
-- only in "public". These lines widen where it looks. The function body is
-- left exactly as it is.
--
-- Paste all four lines into a NEW query tab, highlight nothing, press Run.
-- The last line prints proof: look for RESERVATION SUCCESS.

alter function public.create_preorder(json)     set search_path = public, extensions;
alter function public.join_waitlist(text, text) set search_path = public, extensions;
notify pgrst, 'reload schema';
select * from public.banini_diagnose();
