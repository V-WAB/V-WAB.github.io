/* Banini Butter, front-end configuration.

   Both values below are public by design. The anon key is meant to sit in a
   browser: every table is behind row level security, the catalogue is the only
   thing readable, and the two write paths are functions that validate their
   input and take prices from the database rather than from the page.

   Never put the service_role key in this file. That one bypasses row level
   security and belongs only in the Supabase dashboard and your own machine.

   Find these two under Project Settings, API, in your Supabase project. */

window.BANINI_CONFIG = {
  supabaseUrl: "https://qjwbslwawzhejbjeufkv.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFqd2JzbHdhd3poZWpiamV1Zmt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2NjgzNDEsImV4cCI6MjEwMzI0NDM0MX0.bwnkU9iM98uyhtQX91I0qf24q68shB-DteRWDhXCMdk"
};
