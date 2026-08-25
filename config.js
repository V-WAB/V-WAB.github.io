/* Banini Butter, front-end configuration.

   Both values below are public by design. The anon key is meant to sit in a
   browser: every table is behind row level security, the catalogue is the only
   thing readable, and the two write paths are functions that validate their
   input and take prices from the database rather than from the page.

   Never put the service_role key in this file. That one bypasses row level
   security and belongs only in the Supabase dashboard and your own machine.

   Find these two under Project Settings, API, in your Supabase project. */

window.BANINI_CONFIG = {
  supabaseUrl: "",      // e.g. "https://abcdefghijklmnop.supabase.co"
  supabaseAnonKey: ""   // the "anon public" key
};
