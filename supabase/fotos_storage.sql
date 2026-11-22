-- Bucket público de fotos (solo los administradores suben o borran).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg','image/webp','image/png'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists fotos_subir on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and public.es_admin());
drop policy if exists fotos_cambiar on storage.objects;
create policy fotos_cambiar on storage.objects for update to authenticated using (bucket_id = 'fotos' and public.es_admin());
drop policy if exists fotos_borrar on storage.objects;
create policy fotos_borrar on storage.objects for delete to authenticated using (bucket_id = 'fotos' and public.es_admin());
drop policy if exists fotos_ver on storage.objects;
create policy fotos_ver on storage.objects for select to authenticated using (bucket_id = 'fotos' and public.es_admin());
