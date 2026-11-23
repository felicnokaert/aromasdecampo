alter table public.ajustes add column if not exists google_resena_url text default 'https://search.google.com/local/writereview?placeid=ChIJn7-yVu8trpURfWGnk6a6PHQ';
update public.ajustes set google_resena_url = 'https://search.google.com/local/writereview?placeid=ChIJn7-yVu8trpURfWGnk6a6PHQ' where google_resena_url is null;
grant select (google_resena_url) on public.ajustes to anon, authenticated;
